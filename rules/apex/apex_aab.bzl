"""
Copyright (C) 2022 The Android Open Source Project

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
"""

load("@bazel_skylib//lib:paths.bzl", "paths")
load("//build/bazel/platforms:transitions.bzl", "default_android_transition")
load("@soong_injection//product_config:product_variables.bzl", "product_vars")
load(":apex.bzl", "ApexInfo")
load(":apex_key.bzl", "ApexKeyInfo")
load("//build/bazel/rules/android:android_app_certificate.bzl", "AndroidAppCertificateInfo")

def _arch_transition_impl(settings, attr):
    """Implementation of arch_transition.
    Four archs are included for mainline modules: x86, x86_64, arm and arm64.
    """
    return {
        "x86": {
            "//command_line_option:platforms": "//build/bazel/platforms:android_x86",
        },
        "x86_64": {
            "//command_line_option:platforms": "//build/bazel/platforms:android_x86_64",
        },
        "arm": {
            "//command_line_option:platforms": "//build/bazel/platforms:android_arm",
        },
        "arm64": {
            "//command_line_option:platforms": "//build/bazel/platforms:android_arm64",
        },
    }

# Multi-arch transition.
arch_transition = transition(
    implementation = _arch_transition_impl,
    inputs = [],
    outputs = [
        "//command_line_option:platforms",
    ],
)

# Arch to ABI map
_arch_abi_map = {
    "arm64": "arm64-v8a",
    "arm": "armeabi-v7a",
    "x86_64": "x86_64",
    "x86": "x86",
}

def _apex_proto_convert(ctx, aapt2, arch, module_name, apex_file):
    """Run 'aapt2 convert' to convert resource files to protobuf format."""

    # Inputs
    inputs = [
        apex_file,
        aapt2,
    ]

    # Outputs
    filename = apex_file.basename
    pos_dot = filename.rindex(".")
    proto_convert_file = ctx.actions.declare_file("/".join([
        module_name,
        arch,
        filename[:pos_dot] + ".pb" + filename[pos_dot:],
    ]))
    outputs = [proto_convert_file]

    # Arguments
    args = ctx.actions.args()
    args.add_all(["convert"])
    args.add_all(["--output-format", "proto"])
    args.add_all([apex_file])
    args.add_all(["-o", proto_convert_file.path])

    ctx.actions.run(
        inputs = inputs,
        outputs = outputs,
        executable = aapt2,
        arguments = [args],
        mnemonic = "ApexProtoConvert",
    )
    return proto_convert_file

def _apex_base_file(ctx, arch, module_name, apex_proto_file):
    """Run zip2zip to transform the apex file the expected directory structure
    with all files that will be included in the base module of aab file."""

    # Inputs
    inputs = [
        apex_proto_file,
        ctx.executable._zip2zip,
    ]

    # Outputs
    base_file = ctx.actions.declare_file("/".join([module_name, arch, module_name + ".base"]))
    outputs = [base_file]

    # Arguments
    args = ctx.actions.args()
    args.add_all(["-i", apex_proto_file])
    args.add_all(["-o", base_file])
    abi = _arch_abi_map[arch]
    args.add_all([
        "apex_payload.img:apex/%s.img" % abi,
        "apex_build_info.pb:apex/%s.build_info.pb" % abi,
        "apex_manifest.json:root/apex_manifest.json",
        "apex_manifest.pb:root/apex_manifest.pb",
        "AndroidManifest.xml:manifest/AndroidManifest.xml",
        "assets/NOTICE.html.gz:assets/NOTICE.html.gz",
    ])

    ctx.actions.run(
        inputs = inputs,
        outputs = outputs,
        executable = ctx.executable._zip2zip,
        arguments = [args],
        mnemonic = "ApexBaseFile",
    )
    return base_file

def _build_bundle_config(ctx, module_name):
    """Create bundle_config.json as configuration for running bundletool."""
    file_content = {
        "compression": {
            "uncompressed_glob": [
                "apex_payload.img",
                "apex_manifest.*",
            ],
        },
        "apex_config": {},
    }
    bundle_config_file = ctx.actions.declare_file("/".join([module_name, "bundle_config.json"]))
    ctx.actions.write(bundle_config_file, json.encode(file_content))

    return bundle_config_file

def _merge_base_files(ctx, module_name, base_files):
    """Run merge_zips to merge all files created for each arch by _apex_base_file."""

    # Inputs
    inputs = base_files + [ctx.executable._merge_zips]

    # Outputs
    merged_base_file = ctx.actions.declare_file(module_name + "/" + module_name + ".zip")
    outputs = [merged_base_file]

    # Arguments
    args = ctx.actions.args()
    args.add_all(["--ignore-duplicates"])
    args.add_all([merged_base_file])
    args.add_all(base_files)

    ctx.actions.run(
        inputs = inputs,
        outputs = outputs,
        executable = ctx.executable._merge_zips,
        arguments = [args],
        mnemonic = "ApexMergeBaseFiles",
    )
    return merged_base_file

def _apex_bundle(ctx, module_name, merged_base_file, bundle_config_file):
    """Run bundletool to create the aab file."""

    # Inputs
    inputs = [
        bundle_config_file,
        merged_base_file,
        ctx.executable._bundletool,
    ]

    # Outputs
    bundle_file = ctx.actions.declare_file(module_name + "/" + module_name + ".aab")
    outputs = [bundle_file]

    # Arguments
    args = ctx.actions.args()
    args.add_all(["build-bundle"])
    args.add_all(["--config", bundle_config_file])
    args.add_all(["--modules", merged_base_file])
    args.add_all(["--output", bundle_file])

    ctx.actions.run(
        inputs = inputs,
        outputs = outputs,
        executable = ctx.executable._bundletool,
        arguments = [args],
        mnemonic = "ApexBundleFile",
    )
    return bundle_file

def _sign_bundle(ctx, aapt2, avbtool, module_name, bundle_file, apex_info):
    """ Run dev_sign_bundle to sign the bundle_file."""

    # Python3 interpreter for dev_sign_bundle to run other python scripts.
    python_interpreter = ctx.toolchains["@bazel_tools//tools/python:toolchain_type"].py3_runtime.interpreter
    if python_interpreter.basename != "python3":
        python3 = ctx.actions.declare_file("python3")
        ctx.actions.symlink(
            output = python3,
            target_file = python_interpreter,
            is_executable = True,
        )
        python_interpreter = python3

    # Input directory for dev_sign_bundle.
    input_bundle_file = ctx.actions.declare_file(module_name + "/sign_bundle/input_dir/" + bundle_file.basename)
    ctx.actions.symlink(
        output = input_bundle_file,
        target_file = bundle_file,
    )

    # Output directory  for dev_sign_bundle
    output_dir = ctx.actions.declare_directory(module_name + "/sign_bundle/output_dir")

    # Temporary directory for dev_sign_bundle
    tmp_dir = ctx.actions.declare_directory(module_name + "/sign_bundle/tmp_dir")

    # Jar file of prebuilts/bundletool
    bundletool_jarfile = ctx.attr._bundletool_lib.files.to_list()[0]

    # Keystore file
    keystore_file = ctx.attr.dev_keystore.files.to_list()[0]

    # ANDROID_HOST_OUT environment
    debugfs_static = ctx.actions.declare_file(module_name + "/sign_bundle/android_host_out/bin/debugfs_static")
    ctx.actions.symlink(
        output = debugfs_static,
        target_file = ctx.executable._debugfs,
        is_executable = True,
    )
    fsck_erofs = ctx.actions.declare_file(module_name + "/sign_bundle/android_host_out/bin/fsck.erofs")
    ctx.actions.symlink(
        output = fsck_erofs,
        target_file = ctx.executable._fsck_erofs,
        is_executable = True,
    )
    signapk_jar = ctx.actions.declare_file(module_name + "/sign_bundle/android_host_out/framework/signapk.jar")
    ctx.actions.symlink(
        output = signapk_jar,
        target_file = ctx.attr._signapk_jar.files.to_list()[0],
        is_executable = False,
    )
    libconscrypt_openjdk_jni_so = ctx.actions.declare_file(module_name + "/sign_bundle/android_host_out/lib64/libconscrypt_openjdk_jni.so")
    ctx.actions.symlink(
        output = libconscrypt_openjdk_jni_so,
        target_file = ctx.attr._libconscrypt_openjdk_jni.files.to_list()[1],
        is_executable = False,
    )

    # Tools
    tools = [
        ctx.executable.dev_sign_bundle,
        ctx.executable._deapexer,
        ctx.executable._java,
        ctx.executable._sign_apex,
        ctx.executable._openssl,
        aapt2,
        avbtool.files_to_run.executable,
        python_interpreter,
        debugfs_static,
        fsck_erofs,
        bundletool_jarfile,
        signapk_jar,
        libconscrypt_openjdk_jni_so,
    ]

    # Inputs
    inputs = [
        input_bundle_file,
        keystore_file,
        apex_info.bundle_key_info.private_key,
        apex_info.container_key_info.pem,
        apex_info.container_key_info.pk8,
    ]

    # Outputs
    outputs = [output_dir, tmp_dir]

    # Arguments
    args = ctx.actions.args()
    args.add_all(["--input_dir", input_bundle_file.dirname])
    args.add_all(["--output_dir", output_dir.path])
    args.add_all(["--temp_dir", tmp_dir.path])
    args.add_all(["--aapt2_path", aapt2.path])
    args.add_all(["--bundletool_path", bundletool_jarfile.path])
    args.add_all(["--deapexer_path", ctx.executable._deapexer.path])
    args.add_all(["--debugfs_path", ctx.executable._debugfs.path])
    args.add_all(["--java_binary_path", ctx.executable._java.path])
    args.add_all(["--apex_signer_path", ctx.executable._sign_apex])

    ctx.actions.run(
        inputs = inputs,
        outputs = outputs,
        executable = ctx.executable.dev_sign_bundle,
        arguments = [args],
        tools = tools,
        env = {
            "PATH": ":".join(
                [
                    python_interpreter.dirname,
                    ctx.executable._deapexer.dirname,
                    avbtool.files_to_run.executable.dirname,
                    ctx.executable._openssl.dirname,
                    ctx.executable._java.dirname,
                    "/usr/sbin",  # deapexer calls 'blkid' directly and assumes it is in PATH.
                ],
            ),
            "BAZEL_ANDROID_HOST_OUT": paths.dirname(debugfs_static.dirname),
        },
        mnemonic = "ApexSignBundleFile",
    )

    apks_file = ctx.actions.declare_file(module_name + "/" + module_name + ".apks")
    cert_info_file = ctx.actions.declare_file(module_name + "/" + module_name + ".cert_info.txt")
    ctx.actions.run_shell(
        inputs = [output_dir],
        outputs = [apks_file, cert_info_file],
        command = " ".join(["cp", output_dir.path + "/" + module_name + "/*", apks_file.dirname]),
    )

    return [apks_file, cert_info_file]

def _apex_aab_impl(ctx):
    """Implementation of apex_aab rule, which drives the process of creating aab
    file from apex files created for each arch."""
    apex_toolchain = ctx.toolchains["//build/bazel/rules/apex:apex_toolchain_type"].toolchain_info

    signed_apex_files = {}
    prefixed_signed_apex_files = []
    apex_base_files = []
    bundle_config_file = None
    module_name = ctx.attr.mainline_module[0].label.name
    for arch in ctx.split_attr.mainline_module:
        signed_apex = ctx.split_attr.mainline_module[arch][ApexInfo].signed_output
        signed_apex_files[arch] = signed_apex

        # Forward the individual files for all variants in an additional output group,
        # so dependents can easily access the multi-arch base APEX files by building
        # this target with --output_groups=apex_files.
        #
        # Copy them into an arch-specific directory, since they have the same basename.
        prefixed_signed_apex_file = ctx.actions.declare_file(
            "mainline_modules_" + arch + "/" + signed_apex.basename,
        )
        ctx.actions.run_shell(
            inputs = [signed_apex],
            outputs = [prefixed_signed_apex_file],
            command = " ".join(["cp", signed_apex.path, prefixed_signed_apex_file.path]),
        )
        prefixed_signed_apex_files.append(prefixed_signed_apex_file)

        proto_convert_file = _apex_proto_convert(ctx, apex_toolchain.aapt2, arch, module_name, signed_apex)
        base_file = _apex_base_file(ctx, arch, module_name, proto_convert_file)
        apex_base_files.append(base_file)

    # Create .aab file
    bundle_config_file = _build_bundle_config(ctx, module_name)
    merged_base_file = _merge_base_files(ctx, module_name, apex_base_files)
    bundle_file = _apex_bundle(ctx, module_name, merged_base_file, bundle_config_file)

    # Create .apks file
    apex_info = ctx.attr.mainline_module[0][ApexInfo]
    package_name = apex_info.package_name

    if ctx.attr.dev_sign_bundle and ctx.attr.dev_keystore and (package_name.startswith("com.google.android") or package_name.startswith("com.google.mainline")):
        signed_files = _sign_bundle(ctx, apex_toolchain.aapt2, apex_toolchain.avbtool, module_name, bundle_file, apex_info)
        return [
            DefaultInfo(files = depset([bundle_file] + signed_files)),
            OutputGroupInfo(apex_files = depset(prefixed_signed_apex_files), signed_files = signed_files),
        ]

    return [
        DefaultInfo(files = depset([bundle_file])),
        OutputGroupInfo(apex_files = depset(prefixed_signed_apex_files)),
    ]

# apex_aab rule creates multi-arch outputs of a Mainline module, such as the
# Android Apk Bundle (.aab) file of the APEX specified in mainline_module.
# There is no equivalent Soong module, and it is currently done in shell script
# by invoking Soong multiple times.
_apex_aab = rule(
    implementation = _apex_aab_impl,
    cfg = default_android_transition,
    toolchains = [
        "//build/bazel/rules/apex:apex_toolchain_type",
        "@bazel_tools//tools/python:toolchain_type",
    ],
    attrs = {
        "mainline_module": attr.label(
            mandatory = True,
            cfg = arch_transition,
            providers = [ApexInfo],
            doc = "The label of a mainline module target",
        ),
        "dev_sign_bundle": attr.label(
            cfg = "exec",
            executable = True,
        ),
        "dev_keystore": attr.label(
            cfg = "exec",
            executable = False,
        ),
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
            doc = "Allow transition.",
        ),
        "_merge_zips": attr.label(
            allow_single_file = True,
            cfg = "exec",
            executable = True,
            default = "//prebuilts/build-tools:linux-x86/bin/merge_zips",
        ),
        "_zip2zip": attr.label(
            allow_single_file = True,
            cfg = "exec",
            executable = True,
            default = "//build/soong/cmd/zip2zip:zip2zip",
        ),
        "_bundletool": attr.label(
            cfg = "exec",
            executable = True,
            default = "//prebuilts/bundletool",
        ),
        "_bundletool_lib": attr.label(
            cfg = "exec",
            executable = False,
            default = "//prebuilts/bundletool:bundletool-lib",
        ),
        "_deapexer": attr.label(
            cfg = "exec",
            executable = True,
            default = "//system/apex/tools:deapexer",
        ),
        "_debugfs": attr.label(
            cfg = "exec",
            executable = True,
            default = "//external/e2fsprogs/debugfs:debugfs_static",
        ),
        "_sign_apex": attr.label(
            cfg = "exec",
            executable = True,
            default = "//build/make/tools/releasetools:sign_apex",
        ),
        "_signapk_jar": attr.label(
            cfg = "exec",
            executable = False,
            default = "//build/bazel/rules/apex:signapk_deploy_jar",
        ),
        "_libconscrypt_openjdk_jni": attr.label(
            cfg = "exec",
            executable = False,
            default = "//external/conscrypt:libconscrypt_openjdk_jni",
        ),
        "_java": attr.label(
            cfg = "exec",
            executable = True,
            default = "@local_jdk//:java",
        ),
        "_jdk_bin": attr.label(
            cfg = "exec",
            executable = False,
            default = "@local_jdk//:jdk-bin",
        ),
        "_openssl": attr.label(
            allow_single_file = True,
            cfg = "exec",
            executable = True,
            default = "//prebuilts/build-tools:linux-x86/bin/openssl",
        ),
        "_fsck_erofs": attr.label(
            cfg = "exec",
            executable = True,
            default = "//external/erofs-utils:fsck.erofs",
        ),
        "_zipper": attr.label(
            cfg = "exec",
            executable = True,
            default = "@bazel_tools//tools/zip:zipper",
        ),
    },
)

def apex_aab(name, mainline_module, dev_sign_bundle = None, dev_keystore = None, **kwargs):
    _apex_aab(
        name = name,
        mainline_module = mainline_module,
        dev_sign_bundle = dev_sign_bundle,
        dev_keystore = dev_keystore,
        **kwargs
    )
