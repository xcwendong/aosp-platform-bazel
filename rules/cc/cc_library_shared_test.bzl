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

load("//build/bazel/rules/cc:cc_library_shared.bzl", "cc_library_shared")
load("//build/bazel/rules/cc:cc_library_static.bzl", "cc_library_static")
load("//build/bazel/rules/test_common:paths.bzl", "get_package_dir_based_path")
load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")

def _cc_library_shared_suffix_test_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)
    info = target[DefaultInfo]
    suffix = ctx.attr.suffix

    # NB: There may be more than 1 output file (if e.g. including a TOC)
    outputs = [so.path for so in info.files.to_list() if so.path.endswith(".so")]
    asserts.true(
        env,
        len(outputs) == 1,
        "Expected only 1 output file; got %s" % outputs,
    )
    out = outputs[0]
    suffix_ = suffix + ".so"
    asserts.true(
        env,
        out.endswith(suffix_),
        "Expected output filename to end in `%s`; it was instead %s" % (suffix_, out),
    )

    return analysistest.end(env)

cc_library_shared_suffix_test = analysistest.make(
    _cc_library_shared_suffix_test_impl,
    attrs = {"suffix": attr.string()},
)

def _cc_library_shared_suffix():
    name = "cc_library_shared_suffix"
    test_name = name + "_test"
    suffix = "-suf"

    cc_library_shared(
        name,
        srcs = ["foo.cc"],
        tags = ["manual"],
        suffix = suffix,
    )
    cc_library_shared_suffix_test(
        name = test_name,
        target_under_test = name,
        suffix = suffix,
    )
    return test_name

def _cc_library_shared_empty_suffix():
    name = "cc_library_shared_empty_suffix"
    test_name = name + "_test"

    cc_library_shared(
        name,
        srcs = ["foo.cc"],
        tags = ["manual"],
    )
    cc_library_shared_suffix_test(
        name = test_name,
        target_under_test = name,
    )
    return test_name

def _cc_library_shared_propagating_compilation_context_test_impl(ctx):
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

_cc_library_shared_propagating_compilation_context_test = analysistest.make(
    _cc_library_shared_propagating_compilation_context_test_impl,
    attrs = {
        "expected_hdrs": attr.label_list(),
        "expected_absent_hdrs": attr.label_list(),
        "expected_includes": attr.string_list(),
        "expected_absent_includes": attr.string_list(),
        "expected_system_includes": attr.string_list(),
        "expected_absent_system_includes": attr.string_list(),
    },
)

def _cc_library_shared_propagates_deps():
    name = "_cc_library_shared_propagates_deps"
    dep_name = name + "_dep"
    test_name = name + "_test"

    cc_library_shared(
        name = dep_name,
        hdrs = [":cc_library_shared_hdr"],
        export_includes = ["a/b/c"],
        export_system_includes = ["d/e/f"],
        tags = ["manual"],
    )

    cc_library_shared(
        name = name,
        deps = [dep_name],
        tags = ["manual"],
    )

    _cc_library_shared_propagating_compilation_context_test(
        name = test_name,
        target_under_test = name,
        expected_hdrs = [":cc_library_shared_hdr"],
        expected_includes = ["a/b/c"],
        expected_system_includes = ["d/e/f"],
    )

    return test_name

def _cc_library_shared_propagates_whole_archive_deps():
    name = "_cc_library_shared_propagates_whole_archive_deps"
    dep_name = name + "_dep"
    test_name = name + "_test"

    cc_library_shared(
        name = dep_name,
        hdrs = [":cc_library_shared_hdr"],
        export_includes = ["a/b/c"],
        export_system_includes = ["d/e/f"],
        tags = ["manual"],
    )

    cc_library_shared(
        name = name,
        whole_archive_deps = [dep_name],
        tags = ["manual"],
    )

    _cc_library_shared_propagating_compilation_context_test(
        name = test_name,
        target_under_test = name,
        expected_hdrs = [":cc_library_shared_hdr"],
        expected_includes = ["a/b/c"],
        expected_system_includes = ["d/e/f"],
    )

    return test_name

def _cc_library_shared_propagates_dynamic_deps():
    name = "_cc_library_shared_propagates_dynamic_deps"
    dep_name = name + "_dep"
    test_name = name + "_test"

    cc_library_shared(
        name = dep_name,
        hdrs = [":cc_library_shared_hdr"],
        export_includes = ["a/b/c"],
        export_system_includes = ["d/e/f"],
        tags = ["manual"],
    )

    cc_library_shared(
        name = name,
        dynamic_deps = [dep_name],
        tags = ["manual"],
    )

    _cc_library_shared_propagating_compilation_context_test(
        name = test_name,
        target_under_test = name,
        expected_hdrs = [":cc_library_shared_hdr"],
        expected_includes = ["a/b/c"],
        expected_system_includes = ["d/e/f"],
    )

    return test_name

def _cc_library_shared_does_not_propagate_implementation_deps():
    name = "_cc_library_shared_does_not_propagate_implementation_deps"
    dep_name = name + "_dep"
    test_name = name + "_test"

    cc_library_static(
        name = dep_name,
        hdrs = [":cc_library_shared_hdr"],
        export_includes = ["a/b/c"],
        export_system_includes = ["d/e/f"],
        tags = ["manual"],
    )

    cc_library_shared(
        name = name,
        implementation_deps = [dep_name],
        tags = ["manual"],
    )

    _cc_library_shared_propagating_compilation_context_test(
        name = test_name,
        target_under_test = name,
        expected_absent_hdrs = [":cc_library_shared_hdr"],
        expected_absent_includes = ["a/b/c"],
        expected_absent_system_includes = ["d/e/f"],
    )

    return test_name

def _cc_library_shared_does_not_propagate_implementation_whole_archive_deps():
    name = "_cc_library_shared_does_not_propagate_implementation_whole_archive_deps"
    dep_name = name + "_dep"
    test_name = name + "_test"

    cc_library_static(
        name = dep_name,
        hdrs = [":cc_library_shared_hdr"],
        export_includes = ["a/b/c"],
        export_system_includes = ["d/e/f"],
        tags = ["manual"],
    )

    cc_library_shared(
        name = name,
        implementation_whole_archive_deps = [dep_name],
        tags = ["manual"],
    )

    _cc_library_shared_propagating_compilation_context_test(
        name = test_name,
        target_under_test = name,
        expected_absent_hdrs = [":cc_library_shared_hdr"],
        expected_absent_includes = ["a/b/c"],
        expected_absent_system_includes = ["d/e/f"],
    )

    return test_name

def _cc_library_shared_does_not_propagate_implementation_dynamic_deps():
    name = "_cc_library_shared_does_not_propagate_implementation_dynamic_deps"
    dep_name = name + "_dep"
    test_name = name + "_test"

    cc_library_shared(
        name = dep_name,
        hdrs = [":cc_library_shared_hdr"],
        export_includes = ["a/b/c"],
        export_system_includes = ["d/e/f"],
        tags = ["manual"],
    )

    cc_library_shared(
        name = name,
        implementation_dynamic_deps = [dep_name],
        tags = ["manual"],
    )

    _cc_library_shared_propagating_compilation_context_test(
        name = test_name,
        target_under_test = name,
        expected_absent_hdrs = [":cc_library_shared_hdr"],
        expected_absent_includes = ["a/b/c"],
        expected_absent_system_includes = ["d/e/f"],
    )

    return test_name

def cc_library_shared_test_suite(name):
    native.genrule(name = "cc_library_shared_hdr", cmd = "null", outs = ["cc_shared_f.h"], tags = ["manual"])

    native.test_suite(
        name = name,
        tests = [
            _cc_library_shared_suffix(),
            _cc_library_shared_empty_suffix(),
            _cc_library_shared_propagates_deps(),
            _cc_library_shared_propagates_whole_archive_deps(),
            _cc_library_shared_propagates_dynamic_deps(),
            _cc_library_shared_does_not_propagate_implementation_deps(),
            _cc_library_shared_does_not_propagate_implementation_whole_archive_deps(),
            _cc_library_shared_does_not_propagate_implementation_dynamic_deps(),
        ],
    )
