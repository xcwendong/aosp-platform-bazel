"""
Copyright (C) 2023 The Android Open Source Project

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
load("//build/bazel/rules/cc:cc_prebuilt_library_shared.bzl", "cc_prebuilt_library_shared")

def _cc_prebuilt_library_shared_test_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)
    expected_lib = ctx.attr.expected_lib

    cc_info = target[CcInfo]
    linker_inputs = cc_info.linking_context.linker_inputs.to_list()
    libs_to_link = []
    for lib in linker_inputs:
        libs_to_link += lib.libraries

    asserts.true(
        env,
        expected_lib in [lib.dynamic_library.basename for lib in libs_to_link],
        "\nExpected the target to include the shared library %s; but instead got:\n\t%s\n" % (expected_lib, libs_to_link),
    )

    return analysistest.end(env)

_cc_prebuilt_library_shared_test = analysistest.make(
    _cc_prebuilt_library_shared_test_impl,
    attrs = dict(
        expected_lib = attr.string(mandatory = True),
    ),
)

def _cc_prebuilt_library_shared_simple():
    name = "_cc_prebuilt_library_shared_simple"
    test_name = name + "_test"
    lib = "libfoo.so"

    cc_prebuilt_library_shared(
        name = name,
        shared_library = lib,
        tags = ["manual"],
    )

    _cc_prebuilt_library_shared_test(
        name = test_name,
        target_under_test = name,
        expected_lib = lib,
    )

    return test_name

def cc_prebuilt_library_shared_test_suite(name):
    native.test_suite(
        name = name,
        tests = [
            _cc_prebuilt_library_shared_simple(),
        ],
    )
