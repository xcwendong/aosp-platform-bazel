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
    "parse_sdk_version",
    "system_dynamic_deps_defaults",
    "system_static_deps_defaults",
)
load(":cc_library_static.bzl", "cc_library_static")
load(":stl.bzl", "stl_deps")
load(":stripped_cc_common.bzl", "stripped_binary")
load(":versioned_cc_common.bzl", "versioned_binary")

def cc_binary(
        name,
        suffix = "",
        dynamic_deps = [],
        srcs = [],
        srcs_c = [],
        srcs_as = [],
        copts = [],
        cppflags = [],
        conlyflags = [],
        asflags = [],
        deps = [],
        whole_archive_deps = [],
        system_deps = None,
        runtime_deps = [],
        export_includes = [],
        export_system_includes = [],
        local_includes = [],
        absolute_includes = [],
        linkshared = True,
        linkopts = [],
        rtti = False,
        use_libcrt = True,
        stl = "",
        cpp_std = "",
        additional_linker_inputs = None,
        strip = {},
        features = [],
        target_compatible_with = [],
        sdk_version = "",
        min_sdk_version = "",
        use_version_lib = False,
        tags = [],
        generate_cc_test = False,
        **kwargs):
    "Bazel macro to correspond with the cc_binary Soong module."

    root_name = name + "__internal_root"
    unstripped_name = name + "_unstripped"

    toolchain_features = []
    toolchain_features += features

    if linkshared:
        toolchain_features.extend(["dynamic_executable", "dynamic_linker"])
    else:
        toolchain_features.extend(["-dynamic_executable", "-dynamic_linker", "static_executable", "static_flag"])

    if not use_libcrt:
        toolchain_features += ["-use_libcrt"]

    if min_sdk_version:
        toolchain_features += parse_sdk_version(min_sdk_version) + ["-sdk_version_default"]

    system_dynamic_deps = []
    system_static_deps = []
    if system_deps == None:
        if linkshared:
            system_deps = system_dynamic_deps_defaults
        else:
            system_deps = system_static_deps_defaults

    if linkshared:
        system_dynamic_deps = system_deps
    else:
        system_static_deps = system_deps

    stl = stl_deps(stl, linkshared, is_binary = True)

    # The static library at the root of the cc_binary.
    cc_library_static(
        name = root_name,
        absolute_includes = absolute_includes,
        # alwayslink = True because the compiled objects from cc_library.srcs is expected
        # to always be linked into the binary itself later (otherwise, why compile them at
        # the cc_binary level?).
        #
        # Concretely, this makes this static library to be wrapped in the --whole_archive
        # block when linking the cc_binary later.
        alwayslink = True,
        asflags = asflags,
        conlyflags = conlyflags,
        copts = copts,
        cpp_std = cpp_std,
        cppflags = cppflags,
        deps = deps + stl.static + system_static_deps,
        whole_archive_deps = whole_archive_deps,
        dynamic_deps = dynamic_deps + stl.shared,
        features = toolchain_features,
        local_includes = local_includes,
        rtti = rtti,
        srcs = srcs,
        srcs_as = srcs_as,
        srcs_c = srcs_c,
        stl = "none",
        system_dynamic_deps = system_dynamic_deps,
        target_compatible_with = target_compatible_with,
        tags = ["manual"],
    )

    binary_dynamic_deps = add_lists_defaulting_to_none(
        dynamic_deps,
        system_dynamic_deps,
        stl.shared,
    )

    toolchain_features += select({
        "//build/bazel/rules/cc:android_coverage_lib_flag": ["android_coverage_lib"],
        "//conditions:default": [],
    })

    # TODO(b/233660582): deal with the cases where the default lib shouldn't be used
    extra_implementation_deps = select({
        "//build/bazel/rules/cc:android_coverage_lib_flag": ["//system/extras/toolchain-extras:libprofile-clang-extras"],
        "//conditions:default": [],
    })

    if generate_cc_test:
        native.cc_test(
            name = name,
            deps = [root_name] + deps + system_static_deps + stl.static + extra_implementation_deps,
            dynamic_deps = binary_dynamic_deps,
            features = toolchain_features,
            linkopts = linkopts,
            additional_linker_inputs = additional_linker_inputs,
            target_compatible_with = target_compatible_with,
            **kwargs
        )
    else:
        native.cc_binary(
            name = unstripped_name,
            deps = [root_name] + deps + system_static_deps + stl.static + extra_implementation_deps,
            dynamic_deps = binary_dynamic_deps,
            features = toolchain_features,
            linkopts = linkopts,
            additional_linker_inputs = additional_linker_inputs,
            target_compatible_with = target_compatible_with,
            tags = ["manual"],
            **kwargs
        )

        versioned_name = name + "_versioned"
        versioned_binary(
            name = versioned_name,
            src = unstripped_name,
            stamp_build_number = use_version_lib,
            tags = ["manual"],
        )

        stripped_binary(
            name = name,
            suffix = suffix,
            src = versioned_name,
            runtime_deps = runtime_deps,
            target_compatible_with = target_compatible_with,
            tags = tags,
            unstripped = unstripped_name,
            **strip
        )
