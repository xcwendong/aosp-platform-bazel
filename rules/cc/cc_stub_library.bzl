# Copyright (C) 2022 The Android Open Source Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

load("//build/bazel/platforms:platform_utils.bzl", "platforms")
load(":cc_library_common.bzl", "disable_crt_link")
load(":cc_library_static.bzl", "cc_library_static")
load(":cc_library_shared.bzl", "CcStubLibrariesInfo")

# This file contains the implementation for the cc_stub_library rule.
#
# TODO(b/207812332):
# - ndk_api_coverage_parser: https://cs.android.com/android/platform/superproject/+/master:build/soong/cc/coverage.go;l=248-262;drc=master

CcStubInfo = provider(
    fields = {
        "stub_map": "The .map file containing library symbols for the specific API version.",
        "version": "The API version of this library.",
        "abi_symbol_list": "A plain-text list of all symbols of this library for the specific API version.",
    },
)

def _cc_stub_gen_impl(ctx):
    # The name of this target.
    name = ctx.attr.name

    # All declared outputs of ndkstubgen.
    out_stub_c = ctx.actions.declare_file("/".join([name, "stub.c"]))
    out_stub_map = ctx.actions.declare_file("/".join([name, "stub.map"]))
    out_abi_symbol_list = ctx.actions.declare_file("/".join([name, "abi_symbol_list.txt"]))

    outputs = [out_stub_c, out_stub_map, out_abi_symbol_list]

    ndkstubgen_args = ctx.actions.args()
    ndkstubgen_args.add_all(["--arch", platforms.get_target_arch(ctx.attr._platform_utils)])
    ndkstubgen_args.add_all(["--api", ctx.attr.version])
    ndkstubgen_args.add_all(["--api-map", ctx.file._api_levels_file])

    # TODO(b/207812332): This always parses and builds the stub library as a dependency of an APEX. Parameterize this
    # for non-APEX use cases.
    ndkstubgen_args.add_all(["--systemapi", "--apex", ctx.file.symbol_file])
    ndkstubgen_args.add_all(outputs)
    ctx.actions.run(
        executable = ctx.executable._ndkstubgen,
        inputs = [
            ctx.file.symbol_file,
            ctx.file._api_levels_file,
        ],
        outputs = outputs,
        arguments = [ndkstubgen_args],
    )

    return [
        # DefaultInfo.files contains the .stub.c file only so that this target
        # can be used directly in the srcs of a cc_library.
        DefaultInfo(files = depset([out_stub_c])),
        CcStubInfo(
            stub_map = out_stub_map,
            abi_symbol_list = out_abi_symbol_list,
            version = ctx.attr.version,
        ),
    ]

cc_stub_gen = rule(
    implementation = _cc_stub_gen_impl,
    attrs = {
        # Public attributes
        "symbol_file": attr.label(mandatory = True, allow_single_file = [".map.txt"]),
        "version": attr.string(mandatory = True, default = "current"),
        # Private attributes
        "_api_levels_file": attr.label(default = "@soong_injection//api_levels:api_levels.json", allow_single_file = True),
        "_ndkstubgen": attr.label(default = "//build/soong/cc/ndkstubgen", executable = True, cfg = "exec"),
        "_platform_utils": attr.label(default = Label("//build/bazel/platforms:platform_utils")),
    },
)

CcStubLibrarySharedInfo = provider(
    fields = {
        "source_library": "The source library label of the cc_stub_library_shared",
    },
)

# cc_stub_library_shared creates a cc_library_shared target, but using stub C source files generated
# from a library's .map.txt files and ndkstubgen. The top level target returns the same
# providers as a cc_library_shared, with the addition of a CcStubInfo
# containing metadata files and versions of the stub library.
def cc_stub_library_shared(name, stubs_symbol_file, version, export_includes, soname, source_library, deps, target_compatible_with, features, tags):
    # Call ndkstubgen to generate the stub.c source file from a .map.txt file. These
    # are accessible in the CcStubInfo provider of this target.
    cc_stub_gen(
        name = name + "_files",
        symbol_file = stubs_symbol_file,
        version = version,
        target_compatible_with = target_compatible_with,
        tags = ["manual"],
    )

    # The static library at the root of the stub shared library.
    cc_library_static(
        name = name + "_root",
        srcs_c = [name + "_files"],  # compile the stub.c file
        copts = ["-fno-builtin"],  # ignore conflicts with builtin function signatures
        features = disable_crt_link(features) +
                   [
                       # Enable the stub library compile flags
                       "stub_library",
                       # Disable all include-related features to avoid including any headers
                       # that may cause conflicting type errors with the symbols in the
                       # generated stubs source code.
                       #  e.g.
                       #  double acos(double); // in header
                       #  void acos() {} // in the generated source code
                       # See https://cs.android.com/android/platform/superproject/+/master:build/soong/cc/library.go;l=942-946;drc=d8a72d7dc91b2122b7b10b47b80cf2f7c65f9049
                       "-toolchain_include_directories",
                       "-includes",
                       "-include_paths",
                   ],
        target_compatible_with = target_compatible_with,
        stl = "none",
        system_dynamic_deps = [],
        tags = ["manual"],
        export_includes = export_includes,
        # deps is used to export includes that specified using "header_libs" in Android.bp, e.g. "libc_headers".
        deps = deps,
    )

    # Create a .so for the stub library. This library is self contained, has
    # no deps, and doesn't link against crt.
    if len(soname) == 0:
        fail("For stub libraries 'soname' is mandatory and must be same as the soname of its source library.")
    soname_flag = "-Wl,-soname," + soname
    native.cc_shared_library(
        name = name + "_so",
        user_link_flags = [soname_flag],
        roots = [name + "_root"],
        features = disable_crt_link(features),
        target_compatible_with = target_compatible_with,
        tags = ["manual"],
    )

    # Create a target with CcSharedLibraryInfo and CcStubInfo providers.
    _cc_stub_library_shared(
        name = name,
        stub_target = name + "_files",
        library_target = name + "_so",
        root_target = name + "_root",
        source_library = source_library,
        tags = tags,
    )

def _cc_stub_library_shared_impl(ctx):
    return [
        ctx.attr.library_target[DefaultInfo],
        ctx.attr.library_target[CcSharedLibraryInfo],
        ctx.attr.stub_target[CcStubInfo],
        ctx.attr.root_target[CcInfo],
        CcStubLibrariesInfo(has_stubs = True),
        OutputGroupInfo(rule_impl_debug_files = depset()),
        CcStubLibrarySharedInfo(source_library = ctx.attr.source_library),
    ]

_cc_stub_library_shared = rule(
    implementation = _cc_stub_library_shared_impl,
    doc = "Top level rule to merge CcStubInfo and CcSharedLibraryInfo into a single target",
    attrs = {
        "stub_target": attr.label(mandatory = True),
        "library_target": attr.label(mandatory = True),
        "root_target": attr.label(mandatory = True),
        "source_library": attr.label(mandatory = True),
    },
)

def cc_stub_suite(name, source_library, versions, symbol_file, export_includes = [], soname = "", deps = [], data = [], target_compatible_with = [], features = [], tags = ["manual"]):
    for version in versions:
        cc_stub_library_shared(
            # Use - as the seperator of name and version. "current" might be the version of some libraries.
            name = name + "-" + version,
            version = version,
            stubs_symbol_file = symbol_file,
            export_includes = export_includes,
            soname = soname,
            source_library = source_library,
            deps = deps,
            target_compatible_with = target_compatible_with,
            features = features,
            tags = tags,
        )

    native.alias(
        # Use _ as the seperator of name and version in alias. So there is no
        # duplicated name if "current" is one of the versions of a library.
        name = name + "_current",
        actual = name + "-" + versions[-1],
    )
