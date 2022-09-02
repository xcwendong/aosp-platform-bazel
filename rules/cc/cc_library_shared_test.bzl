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

def cc_library_shared_test_suite(name):
    native.test_suite(
        name = name,
        tests = [
            _cc_library_shared_suffix(),
            _cc_library_shared_empty_suffix(),
        ],
    )
