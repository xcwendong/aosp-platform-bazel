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
load("//build/bazel/rules/cc:cc_prebuilt_library_static.bzl", "cc_prebuilt_library_static")

def _cc_prebuilt_library_static_alwayslink_test_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)
    expected_lib = ctx.attr.expected_lib
    cc_info = target[CcInfo]
    linker_inputs = cc_info.linking_context.linker_inputs.to_list()
    libs_to_link = []
    for l in linker_inputs:
        libs_to_link += l.libraries

    has_alwayslink = False
    libs = {}
    for lib_to_link in libs_to_link:
        lib = lib_to_link.static_library.basename
        libs[lib_to_link.static_library] = lib_to_link.alwayslink
        if lib == expected_lib:
            has_alwayslink = lib_to_link.alwayslink
        if has_alwayslink:
            break
    asserts.true(env, has_alwayslink, "\nExpected to find the static library `%s` unconditionally in the linker_input, with alwayslink set:\n\t%s" % (expected_lib, str(libs)))

    return analysistest.end(env)

_cc_prebuilt_library_static_alwayslink_test = analysistest.make(
    _cc_prebuilt_library_static_alwayslink_test_impl,
    attrs = {"expected_lib": attr.string()},
)

def _cc_prebuilt_library_static_given_alwayslink_lib():
    name = "_cc_prebuilt_library_static_given_alwayslink_lib"
    test_name = name + "_test"
    lib = "libfoo.a"

    cc_prebuilt_library_static(
        name = name,
        static_library = lib,
        alwayslink = True,
        tags = ["manual"],
    )

    _cc_prebuilt_library_static_alwayslink_test(
        name = test_name,
        target_under_test = name,
        expected_lib = lib,
    )

    return test_name

def cc_prebuilt_library_static_test_suite(name):
    native.test_suite(
        name = name,
        tests = [
            _cc_prebuilt_library_static_given_alwayslink_lib(),
        ],
    )
