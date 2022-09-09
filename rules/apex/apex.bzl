"""
Copyright (C) 2021 The Android Open Source Project

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

load(":apex_key.bzl", "ApexKeyInfo")
load("//build/bazel/platforms:platform_utils.bzl", "platforms")
load("//build/bazel/rules:prebuilt_file.bzl", "PrebuiltFileInfo")
load("//build/bazel/rules:sh_binary.bzl", "ShBinaryInfo")
load("//build/bazel/rules/cc:stripped_cc_common.bzl", "StrippedCcBinaryInfo")
load("//build/bazel/rules/android:android_app_certificate.bzl", "AndroidAppCertificateInfo")
load("//build/bazel/rules/apex:transition.bzl", "apex_transition", "shared_lib_transition_32", "shared_lib_transition_64")
load("//build/bazel/platforms:transitions.bzl", "default_android_transition")
load("//build/bazel/rules/apex:cc.bzl", "ApexCcInfo", "apex_cc_aspect")
load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load("@bazel_skylib//lib:dicts.bzl", "dicts")
load("@bazel_skylib//lib:paths.bzl", "paths")
load("@soong_injection//apex_toolchain:constants.bzl", "default_manifest_version")

ApexInfo = provider(
    "ApexInfo exports metadata about this apex.",
    fields = {
        "provides_native_libs": "Labels of native shared libs that this apex provides.",
        "requires_native_libs": "Labels of native shared libs that this apex requires.",
        "unsigned_output": "Unsigned .apex file.",
        "signed_output": "Signed .apex file.",
        "bundle_key_pair": "APEX bundle signing public/private key pair (the value of the key: attribute).",
        "container_key_pair": "APEX zip signing public/private key pair (the value of the certificate: attribute).",
    },
)

def _create_file_mapping(ctx):
    """Create a file mapping for the APEX filesystem image.

    This returns a Dict[File, str] where the dictionary keys
    are the input files, and the values are the paths that these
    files should have in the apex staging dir / filesystem image.
    """

    # Dictionary mapping from the path of each dependency to its path in the apex
    file_mapping = {}
    requires = {}
    provides = {}

    def _add_lib_files(dir, libs):
        for dep in libs:
            apex_cc_info = dep[ApexCcInfo]
            for lib in apex_cc_info.requires_native_libs.to_list():
                requires[lib] = True
            for lib in apex_cc_info.provides_native_libs.to_list():
                provides[lib] = True
            for lib_file in apex_cc_info.transitive_shared_libs.to_list():
                file_mapping[lib_file] = paths.join(dir, lib_file.basename)

    # Ensure the split attribute dicts are non-empty
    native_shared_libs_32 = dicts.add({"x86": [], "arm": []}, ctx.split_attr.native_shared_libs_32)
    native_shared_libs_64 = dicts.add({"x86_64": [], "arm64": []}, ctx.split_attr.native_shared_libs_64)

    if platforms.is_target_x86(ctx.attr._platform_utils):
        _add_lib_files("lib", native_shared_libs_32["x86"])
    elif platforms.is_target_x86_64(ctx.attr._platform_utils):
        _add_lib_files("lib", native_shared_libs_32["x86"])
        _add_lib_files("lib64", native_shared_libs_64["x86_64"])
    elif platforms.is_target_arm(ctx.attr._platform_utils):
        _add_lib_files("lib", native_shared_libs_32["arm"])
    elif platforms.is_target_arm64(ctx.attr._platform_utils):
        _add_lib_files("lib", native_shared_libs_32["arm"])
        _add_lib_files("lib64", native_shared_libs_64["arm64"])

    # Handle prebuilts
    for dep in ctx.attr.prebuilts:
        prebuilt_file_info = dep[PrebuiltFileInfo]
        if prebuilt_file_info.filename:
            filename = prebuilt_file_info.filename
        else:
            filename = dep.label.name
        file_mapping[prebuilt_file_info.src] = paths.join(prebuilt_file_info.dir, filename)

    # Handle binaries
    for dep in ctx.attr.binaries:
        if ShBinaryInfo in dep:
            # sh_binary requires special handling on directory/filename construction.
            sh_binary_info = dep[ShBinaryInfo]
            if sh_binary_info:
                directory = "bin"
                if sh_binary_info.sub_dir:
                    directory = paths.join("bin", sh_binary_info.sub_dir)

                filename = dep.label.name
                if sh_binary_info.filename:
                    filename = sh_binary_info.filename

                file_mapping[dep[DefaultInfo].files_to_run.executable] = paths.join(directory, filename)
        elif ApexCcInfo in dep:
            # cc_binary just takes the final executable from the runfiles.
            file_mapping[dep[DefaultInfo].files_to_run.executable] = paths.join("bin", dep.label.name)

            if platforms.get_target_bitness(ctx.attr._platform_utils) == 64:
                _add_lib_files("lib64", [dep])
            else:
                _add_lib_files("lib", [dep])

    return file_mapping, requires.keys(), provides.keys()

def _add_so(label):
    return label.name + ".so"

def _add_apex_manifest_information(
        ctx,
        apex_toolchain,
        requires_native_libs,
        provides_native_libs):
    apex_manifest_json = ctx.file.manifest
    apex_manifest_full_json = ctx.actions.declare_file(ctx.attr.name + "_apex_manifest_full.json")

    args = ctx.actions.args()
    args.add(apex_manifest_json)
    args.add_all(["-a", "requireNativeLibs"])
    args.add_all(requires_native_libs, map_each = _add_so)  # e.g. turn "//foo/bar:baz" to "baz.so"
    args.add_all(["-a", "provideNativeLibs"])
    args.add_all(provides_native_libs, map_each = _add_so)

    args.add_all(["-se", "version", "0", default_manifest_version])

    # TODO: support other optional flags like -v name and -a jniLibs
    args.add_all(["-o", apex_manifest_full_json])

    ctx.actions.run(
        inputs = [apex_manifest_json],
        outputs = [apex_manifest_full_json],
        executable = apex_toolchain.jsonmodify[DefaultInfo].files_to_run,
        arguments = [args],
        mnemonic = "ApexManifestModify",
    )

    return apex_manifest_full_json

# conv_apex_manifest - Convert the JSON APEX manifest to protobuf, which is needed by apexer.
def _convert_apex_manifest_json_to_pb(ctx, apex_toolchain, apex_manifest_json):
    apex_manifest_pb = ctx.actions.declare_file(ctx.attr.name + "_apex_manifest.pb")

    ctx.actions.run(
        outputs = [apex_manifest_pb],
        inputs = [apex_manifest_json],
        executable = apex_toolchain.conv_apex_manifest[DefaultInfo].files_to_run,
        arguments = [
            "proto",
            apex_manifest_json.path,
            "-o",
            apex_manifest_pb.path,
        ],
        mnemonic = "ConvApexManifest",
    )

    return apex_manifest_pb

# TODO(b/236683936): Add support for custom canned_fs_config concatenation.
def _generate_canned_fs_config(ctx, filepaths):
    """Generate filesystem config.

    This encodes the filemode, uid, and gid of each file in the APEX,
    including apex_manifest.json and apex_manifest.pb.
    NOTE: every file must have an entry.
    """

    # Ensure all paths don't start with / and are normalized
    filepaths = [paths.normalize(f).lstrip("/") for f in filepaths]
    filepaths = [f for f in filepaths if f]

    # First, collect a set of all the directories in the apex
    apex_subdirs_set = {}
    for f in filepaths:
        d = paths.dirname(f)
        if d != "":  # The root dir is handled manually below
            # Make sure all the parent dirs of the current subdir are in the set, too
            dirs = d.split("/")
            for i in range(1, len(dirs) + 1):
                apex_subdirs_set["/".join(dirs[:i])] = True

    # The order of entries is significant. Later entries are preferred over
    # earlier entries. Keep this consistent with Soong.
    config_lines = []
    config_lines += ["/ 1000 1000 0755"]
    config_lines += ["/apex_manifest.json 1000 1000 0644"]
    config_lines += ["/apex_manifest.pb 1000 1000 0644"]

    filepaths = sorted(filepaths)

    # Readonly if not executable.
    config_lines += ["/" + f + " 1000 1000 0644" for f in filepaths if not f.startswith("bin/")]

    # Mark all binaries as executable.
    config_lines += ["/" + f + " 0 2000 0755" for f in filepaths if f.startswith("bin/")]

    # All directories have the same permission.
    config_lines += ["/" + d + " 0 2000 0755" for d in sorted(apex_subdirs_set.keys())]

    file = ctx.actions.declare_file(ctx.attr.name + "_canned_fs_config.txt")
    ctx.actions.write(file, "\n".join(config_lines) + "\n")

    return file

# Append an entry for apex_manifest.pb to the file_contexts file for this APEX,
# which is either from /system/sepolicy/apex/<apexname>-file_contexts (set in
# the apex macro) or custom file_contexts attribute value of this APEX. This
# ensures that the manifest file is correctly labeled as system_file.
def _generate_file_contexts(ctx):
    file_contexts = ctx.actions.declare_file(ctx.attr.name + "-file_contexts")

    ctx.actions.run_shell(
        inputs = [ctx.file.file_contexts],
        outputs = [file_contexts],
        mnemonic = "GenerateApexFileContexts",
        command = "cat {i} > {o} && echo >> {o} && echo /apex_manifest\\\\.pb u:object_r:system_file:s0 >> {o} && echo / u:object_r:system_file:s0 >> {o}"
            .format(i = ctx.file.file_contexts.path, o = file_contexts.path),
    )

    return file_contexts

# apexer - generate the APEX file.
def _run_apexer(ctx, apex_toolchain):
    # Inputs
    apex_key_info = ctx.attr.key[ApexKeyInfo]
    privkey = apex_key_info.private_key
    pubkey = apex_key_info.public_key
    android_jar = apex_toolchain.android_jar
    android_manifest = ctx.file.android_manifest

    file_mapping, requires_native_libs, provides_native_libs = _create_file_mapping(ctx)
    canned_fs_config = _generate_canned_fs_config(ctx, file_mapping.values())
    file_contexts = _generate_file_contexts(ctx)
    full_apex_manifest_json = _add_apex_manifest_information(ctx, apex_toolchain, requires_native_libs, provides_native_libs)
    apex_manifest_pb = _convert_apex_manifest_json_to_pb(ctx, apex_toolchain, full_apex_manifest_json)

    file_mapping_file = ctx.actions.declare_file(ctx.attr.name + "_apex_file_mapping.json")
    ctx.actions.write(file_mapping_file, json.encode({k.path: v for k, v in file_mapping.items()}))

    # Outputs
    apex_output_file = ctx.actions.declare_file(ctx.attr.name + ".apex.unsigned")

    apexer_files = apex_toolchain.apexer[DefaultInfo].files_to_run

    # Arguments
    args = ctx.actions.args()
    args.add(file_mapping_file.path)
    args.add(apexer_files.executable.path)
    if ctx.attr._apexer_verbose[BuildSettingInfo].value:
        args.add("--verbose")
    args.add("--force")
    args.add("--include_build_info")
    args.add_all(["--canned_fs_config", canned_fs_config.path])
    args.add_all(["--manifest", apex_manifest_pb.path])
    args.add_all(["--file_contexts", file_contexts.path])
    args.add_all(["--key", privkey.path])
    args.add_all(["--pubkey", pubkey.path])
    args.add_all(["--payload_type", "image"])
    args.add_all(["--target_sdk_version", "10000"])
    args.add_all(["--payload_fs_type", "ext4"])

    # Override the package name, if it's expicitly specified
    if ctx.attr.package_name:
        args.add_all(["--override_apk_package_name", ctx.attr.package_name])

    if ctx.attr.logging_parent:
        args.add_all(["--logging_parent", ctx.attr.logging_parent])

    # TODO(b/215339575): This is a super rudimentary way to convert "current" to a numerical number.
    # Generalize this to API level handling logic in a separate Starlark utility, preferably using
    # API level maps dumped from api_levels.go
    min_sdk_version = ctx.attr.min_sdk_version
    if min_sdk_version == "current":
        min_sdk_version = "10000"
    args.add_all(["--min_sdk_version", min_sdk_version])

    # apexer needs the list of directories containing all auxilliary tools invoked during
    # the creation of an apex
    avbtool_files = apex_toolchain.avbtool[DefaultInfo].files_to_run
    e2fsdroid_files = apex_toolchain.e2fsdroid[DefaultInfo].files_to_run
    mke2fs_files = apex_toolchain.mke2fs[DefaultInfo].files_to_run
    resize2fs_files = apex_toolchain.resize2fs[DefaultInfo].files_to_run
    sefcontext_compile_files = apex_toolchain.sefcontext_compile[DefaultInfo].files_to_run
    apexer_tool_paths = [
        apex_toolchain.aapt2.dirname,
        apexer_files.executable.dirname,
        avbtool_files.executable.dirname,
        e2fsdroid_files.executable.dirname,
        mke2fs_files.executable.dirname,
        resize2fs_files.executable.dirname,
        sefcontext_compile_files.executable.dirname,
    ]

    args.add_all(["--apexer_tool_path", ":".join(apexer_tool_paths)])

    if android_manifest != None:
        args.add_all(["--android_manifest", android_manifest.path])

    args.add("STAGING_DIR_PLACEHOLDER")
    args.add(apex_output_file)

    inputs = [
        file_mapping_file,
        canned_fs_config,
        apex_manifest_pb,
        file_contexts,
        privkey,
        pubkey,
        android_jar,
    ] + file_mapping.keys()

    if android_manifest != None:
        inputs.append(android_manifest)

    tools = [
        apexer_files,
        avbtool_files,
        e2fsdroid_files,
        mke2fs_files,
        resize2fs_files,
        sefcontext_compile_files,
        apex_toolchain.aapt2,
    ]

    ctx.actions.run(
        inputs = inputs,
        tools = tools,
        outputs = [apex_output_file],
        executable = ctx.executable._staging_dir_builder,
        arguments = [args],
        mnemonic = "Apexer",
    )

    return (
        apex_output_file,
        requires_native_libs,
        provides_native_libs,
    )

# Sign a file with signapk.
def _run_signapk(ctx, unsigned_file, signed_file, private_key, public_key, mnemonic):
    # Arguments
    args = ctx.actions.args()
    args.add_all(["-a", 4096])
    args.add_all(["--align-file-size"])
    args.add_all([public_key, private_key])
    args.add_all([unsigned_file, signed_file])

    ctx.actions.run(
        inputs = [
            unsigned_file,
            private_key,
            public_key,
            ctx.executable._signapk,
        ],
        outputs = [signed_file],
        executable = ctx.executable._signapk,
        arguments = [args],
        mnemonic = mnemonic,
    )

    return signed_file

# Compress a file with apex_compression_tool.
def _run_apex_compression_tool(ctx, apex_toolchain, input_file, output_file_name):
    avbtool_files = apex_toolchain.avbtool[DefaultInfo].files_to_run
    apex_compression_tool_files = apex_toolchain.apex_compression_tool[DefaultInfo].files_to_run

    # Outputs
    compressed_file = ctx.actions.declare_file(output_file_name)

    # Arguments
    args = ctx.actions.args()
    args.add_all(["compress"])
    tool_dirs = [apex_toolchain.soong_zip.dirname, avbtool_files.executable.dirname]
    args.add_all(["--apex_compression_tool", ":".join(tool_dirs)])
    args.add_all(["--input", input_file])
    args.add_all(["--output", compressed_file])

    ctx.actions.run(
        inputs = [input_file],
        tools = [
            avbtool_files,
            apex_compression_tool_files,
            apex_toolchain.soong_zip,
        ],
        outputs = [compressed_file],
        executable = apex_compression_tool_files,
        arguments = [args],
        mnemonic = "BazelApexCompressing",
    )
    return compressed_file

# See the APEX section in the README on how to use this rule.
def _apex_rule_impl(ctx):
    apex_toolchain = ctx.toolchains["//build/bazel/rules/apex:apex_toolchain_type"].toolchain_info

    unsigned_apex, requires_native_libs, provides_native_libs = _run_apexer(ctx, apex_toolchain)

    apex_cert_info = ctx.attr.certificate[AndroidAppCertificateInfo]
    private_key = apex_cert_info.pk8
    public_key = apex_cert_info.pem
    signed_apex = ctx.outputs.apex_output

    _run_signapk(ctx, unsigned_apex, signed_apex, private_key, public_key, "BazelApexSigning")

    if ctx.attr.compressible:
        compressed_apex_output_file = _run_apex_compression_tool(ctx, apex_toolchain, signed_apex, ctx.attr.name + ".capex.unsigned")
        signed_capex = ctx.outputs.capex_output
        _run_signapk(ctx, compressed_apex_output_file, signed_capex, private_key, public_key, "BazelCompressedApexSigning")

    apex_key_info = ctx.attr.key[ApexKeyInfo]
    return [
        DefaultInfo(files = depset([signed_apex])),
        ApexInfo(
            signed_output = signed_apex,
            unsigned_output = unsigned_apex,
            requires_native_libs = requires_native_libs,
            provides_native_libs = provides_native_libs,
            bundle_key_pair = [apex_key_info.public_key, apex_key_info.private_key],
            container_key_pair = [public_key, private_key],
        ),
    ]

_apex = rule(
    implementation = _apex_rule_impl,
    cfg = default_android_transition,
    attrs = {
        "manifest": attr.label(allow_single_file = [".json"]),
        "android_manifest": attr.label(allow_single_file = [".xml"]),
        "package_name": attr.string(),
        "logging_parent": attr.string(),
        "file_contexts": attr.label(allow_single_file = True, mandatory = True),
        "key": attr.label(providers = [ApexKeyInfo], mandatory = True),
        "certificate": attr.label(providers = [AndroidAppCertificateInfo], mandatory = True),
        "min_sdk_version": attr.string(default = "current"),
        "updatable": attr.bool(default = True),
        "installable": attr.bool(default = True),
        "compressible": attr.bool(default = False),
        "native_shared_libs_32": attr.label_list(
            providers = [ApexCcInfo],
            aspects = [apex_cc_aspect],
            cfg = shared_lib_transition_32,
            doc = "The libs compiled for 32-bit",
        ),
        "native_shared_libs_64": attr.label_list(
            providers = [ApexCcInfo],
            aspects = [apex_cc_aspect],
            cfg = shared_lib_transition_64,
            doc = "The libs compiled for 64-bit",
        ),
        "binaries": attr.label_list(
            providers = [
                # The dependency must produce _all_ of the providers in _one_ of these lists.
                [ShBinaryInfo],  # sh_binary
                [StrippedCcBinaryInfo, CcInfo, ApexCcInfo],  # cc_binary (stripped)
            ],
            cfg = apex_transition,
            aspects = [apex_cc_aspect],
        ),
        "prebuilts": attr.label_list(providers = [PrebuiltFileInfo], cfg = apex_transition),
        "apex_output": attr.output(doc = "signed .apex output"),
        "capex_output": attr.output(doc = "signed .capex output"),

        # Required to use apex_transition. This is an acknowledgement to the risks of memory bloat when using transitions.
        "_allowlist_function_transition": attr.label(default = "@bazel_tools//tools/allowlists/function_transition_allowlist"),
        "_staging_dir_builder": attr.label(
            cfg = "exec",
            doc = "The staging dir builder to avoid the problem where symlinks are created inside apex image.",
            executable = True,
            default = "//build/bazel/rules:staging_dir_builder",
        ),
        "_signapk": attr.label(
            cfg = "exec",
            doc = "The signapk tool.",
            executable = True,
            default = "//build/make/tools/signapk",
        ),
        "_platform_utils": attr.label(
            default = Label("//build/bazel/platforms:platform_utils"),
        ),
        "_apexer_verbose": attr.label(
            default = "//build/bazel/rules/apex:apexer_verbose",
            doc = "If enabled, make apexer log verbosely.",
        ),
    },
    toolchains = ["//build/bazel/rules/apex:apex_toolchain_type"],
    fragments = ["platform"],
)

def apex(
        name,
        manifest = "apex_manifest.json",
        android_manifest = None,
        file_contexts = None,
        key = None,
        certificate = None,
        min_sdk_version = None,
        updatable = True,
        installable = True,
        compressible = False,
        native_shared_libs_32 = [],
        native_shared_libs_64 = [],
        binaries = [],
        prebuilts = [],
        package_name = None,
        logging_parent = None,
        **kwargs):
    "Bazel macro to correspond with the APEX bundle Soong module."

    # If file_contexts is not specified, then use the default from //system/sepolicy/apex.
    # https://cs.android.com/android/platform/superproject/+/master:build/soong/apex/builder.go;l=259-263;drc=b02043b84d86fe1007afef1ff012a2155172215c
    if file_contexts == None:
        file_contexts = "//system/sepolicy/apex:" + name + "-file_contexts"

    apex_output = name + ".apex"
    capex_output = None
    if compressible:
        capex_output = name + ".capex"

    _apex(
        name = name,
        manifest = manifest,
        android_manifest = android_manifest,
        file_contexts = file_contexts,
        key = key,
        certificate = certificate,
        min_sdk_version = min_sdk_version,
        updatable = updatable,
        installable = installable,
        compressible = compressible,
        native_shared_libs_32 = native_shared_libs_32,
        native_shared_libs_64 = native_shared_libs_64,
        binaries = binaries,
        prebuilts = prebuilts,
        package_name = package_name,
        logging_parent = logging_parent,

        # Enables predeclared output builds from command line directly, e.g.
        #
        # $ bazel build //path/to/module:com.android.module.apex
        # $ bazel build //path/to/module:com.android.module.capex
        apex_output = apex_output,
        capex_output = capex_output,
        **kwargs
    )
