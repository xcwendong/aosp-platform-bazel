"""Copyright (C) 2022 The Android Open Source Project

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

load("//build/bazel/rules/aidl:interface.bzl", "aidl_interface")
load("@bazel_skylib//lib:new_sets.bzl", "sets")
load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("@bazel_skylib//lib:paths.bzl", "paths")

def _ndk_backend_test_impl(ctx):
    env = analysistest.begin(ctx)
    actions = analysistest.target_actions(env)
    asserts.true(
        env,
        len(actions) == 1,
        "expected to have one action per aidl_library target",
    )
    cc_aidl_code_gen_target = analysistest.target_under_test(env)

    # output_path: <bazel-bin>/<package-dir>/<cc_aidl_library-labelname>_aidl_code_gen
    # Since cc_aidl_library-label is unique among cpp and ndk backends,
    # the output_path is guaranteed to be unique
    output_path = paths.join(
        ctx.genfiles_dir.path,
        ctx.label.package,
        cc_aidl_code_gen_target.label.name,
    )
    expected_outputs = [
        # headers for ndk backend are nested in aidl directory to prevent
        # collision in c++ namespaces with cpp backend
        paths.join(output_path, "aidl/b/BpFoo.h"),
        paths.join(output_path, "aidl/b/BnFoo.h"),
        paths.join(output_path, "aidl/b/Foo.h"),
        paths.join(output_path, "b/Foo.cpp"),
    ]

    # Check output files in DefaultInfo provider
    asserts.set_equals(
        env,
        sets.make(expected_outputs),
        sets.make([
            output.path
            for output in cc_aidl_code_gen_target[DefaultInfo].files.to_list()
        ]),
    )

    # Check the output path is correctly added to includes in CcInfo.compilation_context
    asserts.true(
        env,
        output_path in cc_aidl_code_gen_target[CcInfo].compilation_context.includes.to_list(),
        "output path is added to CcInfo.compilation_context.includes",
    )

    return analysistest.end(env)

ndk_backend_test = analysistest.make(
    _ndk_backend_test_impl,
)

def _ndk_backend_test():
    name = "foo"
    aidl_library_target = name + "-ndk"
    aidl_code_gen_target = aidl_library_target + "_aidl_code_gen"
    test_name = aidl_code_gen_target + "_test"

    aidl_interface(
        name = "foo",
        ndk_config = {
            "enabled": True,
        },
        srcs = ["a/b/Foo.aidl"],
        strip_import_prefix = "a",
        tags = ["manual"],
    )

    ndk_backend_test(
        name = test_name,
        target_under_test = aidl_code_gen_target,
    )

    return test_name

def _ndk_config_test_impl(ctx):
    env = analysistest.begin(ctx)
    actions = analysistest.target_actions(env)
    asserts.true(
        env,
        len(actions) == 1,
        "expected to have one action per aidl_library target",
    )
    asserts.true(
        env,
        "--min_sdk_version=30",
        "expected to have min_sdk_version flag",
    )
    return analysistest.end(env)

ndk_config_test = analysistest.make(
    _ndk_config_test_impl,
)

def _ndk_config_test():
    name = "ndk-config"
    aidl_library_target = name + "-ndk"
    aidl_code_gen_target = aidl_library_target + "_aidl_code_gen"
    test_name = aidl_code_gen_target + "_test"

    aidl_interface(
        name = name,
        ndk_config = {
            "enabled": True,
            "min_sdk_version": "30",
        },
        srcs = ["Foo.aidl"],
        tags = ["manual"],
    )

    ndk_config_test(
        name = test_name,
        target_under_test = aidl_code_gen_target,
    )

    return test_name

def aidl_interface_test_suite(name):
    native.test_suite(
        name = name,
        tests = [
            "//build/bazel/rules/aidl/testing:generated_targets_have_correct_srcs_test",
            "//build/bazel/rules/aidl/testing:interface_macro_produces_all_targets_test",
            _ndk_backend_test(),
            _ndk_config_test(),
        ],
    )
