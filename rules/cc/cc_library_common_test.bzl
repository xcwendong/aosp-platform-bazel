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

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load(":cc_library_common.bzl", "is_external_directory")

def _is_external_directory_test(ctx):
    env = unittest.begin(ctx)

    actual = is_external_directory(ctx.attr.path)

    asserts.equals(env, ctx.attr.expected_value, actual, "expected {path}, to be {external}".format(
        path = ctx.attr.path,
        external = "external" if ctx.attr.expected_value else "non-external",
    ))

    return unittest.end(env)

is_external_directory_test = unittest.make(
    _is_external_directory_test,
    attrs = {
        "path": attr.string(),
        "expected_value": attr.bool(),
    },
)

def _is_external_directory_tests():
    test_cases = {
        "non_external": struct(
            path = "path/to/package",
            expected_value = False,
        ),
        "external": struct(
            path = "external/path/to/package",
            expected_value = True,
        ),
        "hardware": struct(
            path = "hardware/path/to/package",
            expected_value = True,
        ),
        "only_hardware": struct(
            path = "hardware",
            expected_value = True,
        ),
        "hardware_google": struct(
            path = "hardware/google/path/to/package",
            expected_value = False,
        ),
        "hardware_interfaces": struct(
            path = "hardware/interfaces/path/to/package",
            expected_value = False,
        ),
        "hardware_ril": struct(
            path = "hardware/ril/path/to/package",
            expected_value = False,
        ),
        "hardware_libhardware_dir": struct(
            path = "hardware/libhardware/path/to/package",
            expected_value = False,
        ),
        "hardware_libhardware_partial": struct(
            path = "hardware/libhardware_legacy/path/to/package",
            expected_value = False,
        ),
        "vendor": struct(
            path = "vendor/path/to/package",
            expected_value = True,
        ),
        "only_vendor": struct(
            path = "vendor",
            expected_value = True,
        ),
        "vendor_google": struct(
            path = "vendor/google/path/to/package",
            expected_value = False,
        ),
        "vendor_google_with_prefix": struct(
            path = "vendor/pre_google/path/to/package",
            expected_value = False,
        ),
        "vendor_google_with_postfix": struct(
            path = "vendor/google_post/path/to/package",
            expected_value = False,
        ),
    }

    for name, test_case in test_cases.items():
        is_external_directory_test(
            name = name,
            path = test_case.path,
            expected_value = test_case.expected_value,
        )
    return test_cases.keys()

def cc_library_common_test_suites(name):
    native.test_suite(
        name = name,
        tests = _is_external_directory_tests(),
    )
