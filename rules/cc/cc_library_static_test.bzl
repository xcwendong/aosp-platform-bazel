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

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("//build/bazel/rules/cc:cc_library_shared.bzl", "cc_library_shared")
load("//build/bazel/rules/cc:cc_library_static.bzl", "cc_library_static")
load("//build/bazel/rules/test_common:paths.bzl", "get_package_dir_based_path")

def _cc_library_static_propagating_compilation_context_test_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)
    cc_info = target[CcInfo]
    compilation_context = cc_info.compilation_context

    header_paths = [f.path for f in compilation_context.headers.to_list()]
    for hdr in ctx.files.expected_hdrs:
        asserts.true(
            env,
            hdr.path in header_paths,
            "Did not find {hdr} in includes: {hdrs}.".format(hdr = hdr, hdrs = compilation_context.headers),
        )

    for hdr in ctx.files.expected_absent_hdrs:
        asserts.true(
            env,
            hdr not in header_paths,
            "Found {hdr} in includes: {hdrs}, should not be present.".format(hdr = hdr, hdrs = compilation_context.headers),
        )

    for include in ctx.attr.expected_includes:
        absolute_include = get_package_dir_based_path(env, include)
        asserts.true(
            env,
            absolute_include in compilation_context.includes.to_list(),
            "Did not find {include} in includes: {includes}.".format(include = include, includes = compilation_context.includes),
        )

    for include in ctx.attr.expected_absent_includes:
        absolute_include = get_package_dir_based_path(env, include)
        asserts.true(
            env,
            absolute_include not in compilation_context.includes.to_list(),
            "Found {include} in includes: {includes}, was expected to be absent".format(include = include, includes = compilation_context.includes),
        )

    for include in ctx.attr.expected_system_includes:
        absolute_include = get_package_dir_based_path(env, include)
        asserts.true(
            env,
            absolute_include in compilation_context.system_includes.to_list(),
            "Did not find {include} in system includes: {includes}.".format(include = include, includes = compilation_context.system_includes),
        )

    for include in ctx.attr.expected_absent_system_includes:
        absolute_include = get_package_dir_based_path(env, include)
        asserts.true(
            env,
            absolute_include not in compilation_context.system_includes.to_list(),
            "Found {include} in system includes: {includes}, was expected to be absent".format(include = include, includes = compilation_context.system_includes),
        )

    return analysistest.end(env)

_cc_library_static_propagating_compilation_context_test = analysistest.make(
    _cc_library_static_propagating_compilation_context_test_impl,
    attrs = {
        "expected_hdrs": attr.label_list(),
        "expected_absent_hdrs": attr.label_list(),
        "expected_includes": attr.string_list(),
        "expected_absent_includes": attr.string_list(),
        "expected_system_includes": attr.string_list(),
        "expected_absent_system_includes": attr.string_list(),
    },
)

def _cc_library_static_propagates_deps():
    name = "_cc_library_static_propagates_deps"
    dep_name = name + "_dep"
    test_name = name + "_test"

    cc_library_static(
        name = dep_name,
        hdrs = [":hdr"],
        export_includes = ["a/b/c"],
        export_system_includes = ["d/e/f"],
        tags = ["manual"],
    )

    cc_library_static(
        name = name,
        deps = [dep_name],
        tags = ["manual"],
    )

    _cc_library_static_propagating_compilation_context_test(
        name = test_name,
        target_under_test = name,
        expected_hdrs = [":hdr"],
        expected_includes = ["a/b/c"],
        expected_system_includes = ["d/e/f"],
    )

    return test_name

def _cc_library_static_propagates_whole_archive_deps():
    name = "_cc_library_static_propagates_whole_archive_deps"
    dep_name = name + "_dep"
    test_name = name + "_test"

    cc_library_static(
        name = dep_name,
        hdrs = [":hdr"],
        export_includes = ["a/b/c"],
        export_system_includes = ["d/e/f"],
        tags = ["manual"],
    )

    cc_library_static(
        name = name,
        whole_archive_deps = [dep_name],
        tags = ["manual"],
    )

    _cc_library_static_propagating_compilation_context_test(
        name = test_name,
        target_under_test = name,
        expected_hdrs = [":hdr"],
        expected_includes = ["a/b/c"],
        expected_system_includes = ["d/e/f"],
    )

    return test_name

def _cc_library_static_propagates_dynamic_deps():
    name = "_cc_library_static_propagates_dynamic_deps"
    dep_name = name + "_dep"
    test_name = name + "_test"

    cc_library_shared(
        name = dep_name,
        hdrs = [":hdr"],
        export_includes = ["a/b/c"],
        export_system_includes = ["d/e/f"],
        tags = ["manual"],
    )

    cc_library_static(
        name = name,
        dynamic_deps = [dep_name],
        tags = ["manual"],
    )

    _cc_library_static_propagating_compilation_context_test(
        name = test_name,
        target_under_test = name,
        expected_hdrs = [":hdr"],
        expected_includes = ["a/b/c"],
        expected_system_includes = ["d/e/f"],
    )

    return test_name

def _cc_library_static_does_not_propagate_implementation_deps():
    name = "_cc_library_static_does_not_propagate_implementation_deps"
    dep_name = name + "_dep"
    test_name = name + "_test"

    cc_library_static(
        name = dep_name,
        hdrs = [":hdr"],
        export_includes = ["a/b/c"],
        export_system_includes = ["d/e/f"],
        tags = ["manual"],
    )

    cc_library_static(
        name = name,
        implementation_deps = [dep_name],
        tags = ["manual"],
    )

    _cc_library_static_propagating_compilation_context_test(
        name = test_name,
        target_under_test = name,
        expected_absent_hdrs = [":hdr"],
        expected_absent_includes = ["a/b/c"],
        expected_absent_system_includes = ["d/e/f"],
    )

    return test_name

def _cc_library_static_does_not_propagate_implementation_whole_archive_deps():
    name = "_cc_library_static_does_not_propagate_implementation_whole_archive_deps"
    dep_name = name + "_dep"
    test_name = name + "_test"

    cc_library_static(
        name = dep_name,
        hdrs = [":hdr"],
        export_includes = ["a/b/c"],
        export_system_includes = ["d/e/f"],
        tags = ["manual"],
    )

    cc_library_static(
        name = name,
        implementation_whole_archive_deps = [dep_name],
        tags = ["manual"],
    )

    _cc_library_static_propagating_compilation_context_test(
        name = test_name,
        target_under_test = name,
        expected_absent_hdrs = [":hdr"],
        expected_absent_includes = ["a/b/c"],
        expected_absent_system_includes = ["d/e/f"],
    )

    return test_name

def _cc_library_static_does_not_propagate_implementation_dynamic_deps():
    name = "_cc_library_static_does_not_propagate_implementation_dynamic_deps"
    dep_name = name + "_dep"
    test_name = name + "_test"

    cc_library_shared(
        name = dep_name,
        hdrs = [":hdr"],
        export_includes = ["a/b/c"],
        export_system_includes = ["d/e/f"],
        tags = ["manual"],
    )

    cc_library_static(
        name = name,
        implementation_dynamic_deps = [dep_name],
        tags = ["manual"],
    )

    _cc_library_static_propagating_compilation_context_test(
        name = test_name,
        target_under_test = name,
        expected_absent_hdrs = [":hdr"],
        expected_absent_includes = ["a/b/c"],
        expected_absent_system_includes = ["d/e/f"],
    )

    return test_name

def cc_library_static_test_suite(name):
    native.genrule(name = "hdr", cmd = "null", outs = ["f.h"], tags = ["manual"])

    native.test_suite(
        name = name,
        tests = [
            _cc_library_static_propagates_deps(),
            _cc_library_static_propagates_whole_archive_deps(),
            _cc_library_static_propagates_dynamic_deps(),
            _cc_library_static_does_not_propagate_implementation_deps(),
            _cc_library_static_does_not_propagate_implementation_whole_archive_deps(),
            _cc_library_static_does_not_propagate_implementation_dynamic_deps(),
        ],
    )
