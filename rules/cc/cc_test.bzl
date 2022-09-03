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

"""cc_test macro for building native tests with Bazel."""

load(":cc_binary.bzl", "cc_binary")

# TODO(b/244559183): Keep this in sync with cc/test.go#linkerFlags
_gtest_copts = select({
    "//build/bazel/platforms/os:linux_glibc": ["-DGTEST_OS_LINUX"],
    "//build/bazel/platforms/os:darwin": ["-DGTEST_OS_MAC"],
    "//build/bazel/platforms/os:windows": ["-DGTEST_OS_WINDOWS"],
    "//conditions:default": ["-DGTEST_OS_LINUX_ANDROID"],
}) + select({
    "//build/bazel/platforms/os:android": ["-O0", "-g"],
    "//conditions:default": [],
}) + [
    "-DGTEST_HAS_STD_STRING",
    "-Wno-unused-result",  # TODO(b/244433518): Figure out why this is necessary in the bazel compile action.
]

_gtest_deps = [
    "//external/googletest/googletest:libgtest_main",
    "//external/googletest/googletest:libgtest",
]

def cc_test(
        name,
        copts = [],
        deps = [],
        dynamic_deps = [],
        gtest = True,
        isolated = True,  # TODO(b/244432609): currently no-op.
        **kwargs):
    # NOTE: Keep this in sync with cc/test.go#linkerDeps
    if gtest:
        # TODO(b/244433197): handle ctx.useSdk() && ctx.Device() case to link against the ndk variants of the gtest libs.
        # TODO(b/244432609): handle isolated = True to link against libgtest_isolated_main and liblog (dynamically)
        deps = deps + _gtest_deps
        copts = copts + _gtest_copts

    # A cc_test is essentially the same as a cc_binary. Let's reuse the
    # implementation for now and factor the common bits out as necessary.
    cc_binary(
        name = name,
        copts = copts,
        deps = deps,
        dynamic_deps = dynamic_deps,
        generate_cc_test = True,
        **kwargs
    )
