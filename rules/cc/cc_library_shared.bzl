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

load(
    ":cc_library_common.bzl",
    "add_lists_defaulting_to_none",
    "disable_crt_link",
    "parse_sdk_version",
    "system_dynamic_deps_defaults",
)
load(":cc_library_static.bzl", "cc_library_static")
load(":generate_toc.bzl", "shared_library_toc", _CcTocInfo = "CcTocInfo")
load(":stl.bzl", "stl_info")
load(":stripped_cc_common.bzl", "CcUnstrippedInfo", "stripped_shared_library")
load(":versioned_cc_common.bzl", "versioned_shared_library")
load("@bazel_tools//tools/cpp:toolchain_utils.bzl", "find_cpp_toolchain")

CcTocInfo = _CcTocInfo

def cc_library_shared(
        name,
        suffix = "",
        # Common arguments between shared_root and the shared library
        features = [],
        dynamic_deps = [],
        implementation_dynamic_deps = [],
        linkopts = [],
        target_compatible_with = [],
        # Ultimately _static arguments for shared_root production
        srcs = [],
        srcs_c = [],
        srcs_as = [],
        copts = [],
        cppflags = [],
        conlyflags = [],
        asflags = [],
        hdrs = [],
        implementation_deps = [],
        deps = [],
        whole_archive_deps = [],
        implementation_whole_archive_deps = [],
        system_dynamic_deps = None,
        runtime_deps = [],
        export_includes = [],
        export_absolute_includes = [],
        export_system_includes = [],
        local_includes = [],
        absolute_includes = [],
        rtti = False,
        use_libcrt = True,  # FIXME: Unused below?
        stl = "",
        cpp_std = "",
        c_std = "",
        link_crt = True,
        additional_linker_inputs = None,

        # Purely _shared arguments
        strip = {},

        # TODO(b/202299295): Handle data attribute.
        data = [],
        use_version_lib = False,
        has_stubs = False,
        inject_bssl_hash = False,
        sdk_version = "",
        min_sdk_version = "",
        tags = [],
        **kwargs):
    "Bazel macro to correspond with the cc_library_shared Soong module."

    # There exist modules named 'libtest_missing_symbol' and
    # 'libtest_missing_symbol_root'. Ensure that that the target suffixes are
    # sufficiently unique.
    shared_root_name = name + "__internal_root"
    unstripped_name = name + "_unstripped"
    stripped_name = name + "_stripped"
    toc_name = name + "_toc"

    if system_dynamic_deps == None:
        system_dynamic_deps = system_dynamic_deps_defaults

    # Force crtbegin and crtend linking unless explicitly disabled (i.e. bionic
    # libraries do this)
    if link_crt == False:
        features = disable_crt_link(features)

    if min_sdk_version:
        features = features + parse_sdk_version(min_sdk_version) + ["-sdk_version_default"]

    stl = stl_info(stl, True)
    linkopts = linkopts + stl.linkopts
    copts = copts + stl.cppflags

    features = features + select({
        "//build/bazel/rules/cc:android_coverage_lib_flag": ["android_coverage_lib"],
        "//conditions:default": [],
    })

    # TODO(b/233660582): deal with the cases where the default lib shouldn't be used
    implementation_deps = implementation_deps + select({
        "//build/bazel/rules/cc:android_coverage_lib_flag": ["//system/extras/toolchain-extras:libprofile-clang-extras"],
        "//conditions:default": [],
    })

    # The static library at the root of the shared library.
    # This may be distinct from the static version of the library if e.g.
    # the static-variant srcs are different than the shared-variant srcs.
    cc_library_static(
        name = shared_root_name,
        hdrs = hdrs,
        srcs = srcs,
        srcs_c = srcs_c,
        srcs_as = srcs_as,
        copts = copts,
        cppflags = cppflags,
        conlyflags = conlyflags,
        asflags = asflags,
        export_includes = export_includes,
        export_absolute_includes = export_absolute_includes,
        export_system_includes = export_system_includes,
        local_includes = local_includes,
        absolute_includes = absolute_includes,
        rtti = rtti,
        stl = "none",
        cpp_std = cpp_std,
        c_std = c_std,
        dynamic_deps = dynamic_deps,
        implementation_deps = implementation_deps + stl.static_deps,
        implementation_dynamic_deps = implementation_dynamic_deps + stl.shared_deps,
        implementation_whole_archive_deps = implementation_whole_archive_deps,
        system_dynamic_deps = system_dynamic_deps,
        deps = deps + whole_archive_deps,
        features = features,
        target_compatible_with = target_compatible_with,
        tags = ["manual"],
    )

    # implementation_deps and deps are to be linked into the shared library via
    # --no-whole-archive. In order to do so, they need to be dependencies of
    # a "root" of the cc_shared_library, but may not be roots themselves.
    # Below we define stub roots (which themselves have no srcs) in order to facilitate
    # this.
    imp_deps_stub = name + "_implementation_deps"
    deps_stub = name + "_deps"
    native.cc_library(
        name = imp_deps_stub,
        deps = (
            implementation_deps +
            implementation_whole_archive_deps +
            stl.static_deps +
            implementation_dynamic_deps +
            system_dynamic_deps +
            stl.shared_deps
        ),
        target_compatible_with = target_compatible_with,
        tags = ["manual"],
    )
    native.cc_library(
        name = deps_stub,
        deps = deps + dynamic_deps,
        target_compatible_with = target_compatible_with,
        tags = ["manual"],
    )

    shared_dynamic_deps = add_lists_defaulting_to_none(
        dynamic_deps,
        system_dynamic_deps,
        implementation_dynamic_deps,
        stl.shared_deps,
    )

    soname = name + suffix + ".so"
    soname_flag = "-Wl,-soname," + soname

    native.cc_shared_library(
        name = unstripped_name,
        user_link_flags = linkopts + [soname_flag],
        # b/184806113: Note this is  a workaround so users don't have to
        # declare all transitive static deps used by this target.  It'd be great
        # if a shared library could declare a transitive exported static dep
        # instead of needing to declare each target transitively.
        static_deps = ["//:__subpackages__"] + [shared_root_name, imp_deps_stub, deps_stub],
        dynamic_deps = shared_dynamic_deps,
        additional_linker_inputs = additional_linker_inputs,
        roots = [shared_root_name, imp_deps_stub, deps_stub] + whole_archive_deps,
        features = features,
        target_compatible_with = target_compatible_with,
        tags = ["manual"],
        **kwargs
    )

    hashed_name = name + "_hashed"
    _bssl_hash_injection(
        name = hashed_name,
        src = unstripped_name,
        inject_bssl_hash = inject_bssl_hash,
        tags = ["manual"],
    )

    versioned_name = name + "_versioned"
    versioned_shared_library(
        name = versioned_name,
        src = hashed_name,
        stamp_build_number = use_version_lib,
        tags = ["manual"],
    )

    stripped_shared_library(
        name = stripped_name,
        src = versioned_name,
        target_compatible_with = target_compatible_with,
        tags = ["manual"],
        **strip
    )

    shared_library_toc(
        name = toc_name,
        src = stripped_name,
        target_compatible_with = target_compatible_with,
        tags = ["manual"],
    )

    _cc_library_shared_proxy(
        name = name,
        shared = stripped_name,
        shared_debuginfo = unstripped_name,
        root = shared_root_name,
        table_of_contents = toc_name,
        output_file = soname,
        target_compatible_with = target_compatible_with,
        has_stubs = has_stubs,
        runtime_deps = runtime_deps,
        tags = tags,
    )

def _swap_shared_linker_input(ctx, shared_info, new_output):
    old_library_to_link = shared_info.linker_input.libraries[0]

    cc_toolchain = find_cpp_toolchain(ctx)
    feature_configuration = cc_common.configure_features(
        ctx = ctx,
        cc_toolchain = cc_toolchain,
    )

    new_library_to_link = cc_common.create_library_to_link(
        actions = ctx.actions,
        dynamic_library = new_output,
        feature_configuration = feature_configuration,
        cc_toolchain = cc_toolchain,
    )

    new_linker_input = cc_common.create_linker_input(
        owner = shared_info.linker_input.owner,
        libraries = depset([new_library_to_link]),
    )

    return CcSharedLibraryInfo(
        dynamic_deps = shared_info.dynamic_deps,
        exports = shared_info.exports,
        link_once_static_libs = shared_info.link_once_static_libs,
        linker_input = new_linker_input,
        preloaded_deps = shared_info.preloaded_deps,
    )

CcStubLibrariesInfo = provider(
    fields = {
        "has_stubs": "If the shared library has stubs",
    },
)

# A provider to propagate shared library output artifacts, primarily useful
# for root level querying in Soong-Bazel mixed builds.
# Ideally, it would be preferable to reuse the existing native
# CcSharedLibraryInfo provider, but that provider requires that shared library
# artifacts are wrapped in a linker input. Artifacts retrievable from this linker
# input are symlinks to the original artifacts, which is problematic when
# other dependencies expect a real file.
CcSharedLibraryOutputInfo = provider(
    fields = {
        "output_file": "A single .so file, produced by this target.",
    },
)

def _cc_library_shared_proxy_impl(ctx):
    root_files = ctx.attr.root[DefaultInfo].files.to_list()
    shared_files = ctx.attr.shared[DefaultInfo].files.to_list()
    shared_debuginfo = ctx.attr.shared_debuginfo[DefaultInfo].files.to_list()
    if len(shared_files) != 1 or len(shared_debuginfo) != 1:
        fail("Expected only one shared library file and one debuginfo file for it")

    shared_lib = shared_files[0]

    # Copy the output instead of symlinking. This is because this output
    # can be directly installed into a system image; this installation treats
    # symlinks differently from real files (symlinks will be preserved relative
    # to the image root).
    ctx.actions.run_shell(
        inputs = depset(direct = [shared_lib]),
        outputs = [ctx.outputs.output_file],
        command = "cp -f %s %s" % (shared_lib.path, ctx.outputs.output_file.path),
        mnemonic = "CopyFile",
        progress_message = "Copying files",
        use_default_shell_env = True,
    )

    files = root_files + [ctx.outputs.output_file, ctx.files.table_of_contents[0]]

    return [
        DefaultInfo(
            files = depset(direct = files),
            runfiles = ctx.runfiles(files = [ctx.outputs.output_file]),
        ),
        _swap_shared_linker_input(ctx, ctx.attr.shared[CcSharedLibraryInfo], ctx.outputs.output_file),
        ctx.attr.table_of_contents[CcTocInfo],
        # The _only_ linker_input is the statically linked root itself. We need to propagate this
        # as cc_shared_library identifies which libraries can be linked dynamically based on the
        # linker_inputs of the roots
        ctx.attr.root[CcInfo],
        CcStubLibrariesInfo(has_stubs = ctx.attr.has_stubs),
        ctx.attr.shared[OutputGroupInfo],
        CcSharedLibraryOutputInfo(output_file = ctx.outputs.output_file),
        CcUnstrippedInfo(unstripped = shared_debuginfo[0]),
    ]

_cc_library_shared_proxy = rule(
    implementation = _cc_library_shared_proxy_impl,
    attrs = {
        "shared": attr.label(mandatory = True, providers = [CcSharedLibraryInfo]),
        "shared_debuginfo": attr.label(mandatory = True),
        "root": attr.label(mandatory = True, providers = [CcInfo]),
        "output_file": attr.output(mandatory = True),
        "table_of_contents": attr.label(
            mandatory = True,
            # TODO(b/217908237): reenable allow_single_file
            # allow_single_file = True,
            providers = [CcTocInfo],
        ),
        "has_stubs": attr.bool(default = False),
        "runtime_deps": attr.label_list(
            providers = [CcInfo],
            doc = "Deps that should be installed along with this target. Read by the apex cc aspect.",
        ),
    },
    fragments = ["cpp"],
    toolchains = ["@bazel_tools//tools/cpp:toolchain_type"],
)

def _bssl_hash_injection_impl(ctx):
    if len(ctx.files.src) != 1:
        fail("Expected only one shared library file")

    hashed_file = ctx.files.src[0]
    if ctx.attr.inject_bssl_hash:
        hashed_file = ctx.actions.declare_file("lib" + ctx.attr.name + ".so")
        args = ctx.actions.args()
        args.add_all(["-in-object", ctx.files.src[0]])
        args.add_all(["-o", hashed_file])

        ctx.actions.run(
            inputs = ctx.files.src,
            outputs = [hashed_file],
            executable = ctx.executable._bssl_inject_hash,
            arguments = [args],
            tools = [ctx.executable._bssl_inject_hash],
            mnemonic = "BsslInjectHash",
        )

    return [
        DefaultInfo(files = depset([hashed_file])),
        ctx.attr.src[CcSharedLibraryInfo],
        ctx.attr.src[OutputGroupInfo],
    ]

_bssl_hash_injection = rule(
    implementation = _bssl_hash_injection_impl,
    attrs = {
        "src": attr.label(
            mandatory = True,
            # TODO(b/217908237): reenable allow_single_file
            # allow_single_file = True,
            providers = [CcSharedLibraryInfo],
        ),
        "inject_bssl_hash": attr.bool(
            default = False,
            doc = "Whether inject BSSL hash",
        ),
        "_bssl_inject_hash": attr.label(
            cfg = "exec",
            doc = "The BSSL hash injection tool.",
            executable = True,
            default = "//prebuilts/build-tools:linux-x86/bin/bssl_inject_hash",
            allow_single_file = True,
        ),
    },
)
