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

load("//build/bazel/product_variables:constants.bzl", "constants")
load("@bazel_skylib//lib:new_sets.bzl", "sets")
load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load(":stl.bzl", "stl_deps")

_ANDROID_STATIC_DEPS = ["//external/libcxxabi:libc++demangle"]
_STATIC_DEP = ["//external/libcxx:libc++_static"]
_ANDROID_BINARY_STATIC_DEP = ["//prebuilts/clang/host/linux-x86:libunwind"]
_SHARED_DEP = ["//external/libcxx:libc++"]

_StlInfo = provider(fields = ["static", "shared"])

def _stl_impl(ctx):
    return [
        _StlInfo(
            static = ctx.attr.static,
            shared = ctx.attr.shared,
        ),
    ]

_stl = rule(
    implementation = _stl_impl,
    attrs = {
        "shared": attr.string_list(),
        "static": attr.string_list(),
    },
)

def _stl_deps(name, is_shared = True, is_binary = True):
    target_name = name if name else "empty"
    target_name += "_shared" if is_shared else "_static"
    target_name += "_bin" if is_binary else "_lib"
    deps = stl_deps(name, is_shared, is_binary)

    _stl(
        name = target_name,
        shared = deps.shared,
        static = deps.static,
        tags = ["manual"],
    )

    return target_name

def _stl_deps_test_impl(ctx):
    env = analysistest.begin(ctx)

    stl_info = analysistest.target_under_test(env)[_StlInfo]

    expected_static = sets.make(ctx.attr.static)
    actual_static = sets.make(stl_info.static)
    asserts.set_equals(
        env,
        expected = expected_static,
        actual = actual_static,
    )

    expected_shared = sets.make(ctx.attr.shared)
    actual_shared = sets.make(stl_info.shared)
    asserts.set_equals(
        env,
        expected = expected_shared,
        actual = actual_shared,
    )

    return analysistest.end(env)

_stl_deps_android_test = analysistest.make(
    impl = _stl_deps_test_impl,
    attrs = {
        "static": attr.string_list(),
        "shared": attr.string_list(),
    },
    config_settings = {
        "//command_line_option:platforms": "@//build/bazel/platforms:android_x86",
    },
)

_stl_deps_non_android_test = analysistest.make(
    impl = _stl_deps_test_impl,
    attrs = {
        "static": attr.string_list(),
        "shared": attr.string_list(),
    },
    config_settings = {
        "//command_line_option:platforms": "@//build/bazel/platforms:linux_x86",
    },
)

def _test_stl_for_shared_library_unspecified_defaults_shared():
    target_name = _stl_deps("", is_shared = True, is_binary = False)
    android_test_name = target_name + "_android_test"
    non_android_test_name = target_name + "_non_android_test"

    _stl_deps_android_test(
        name = android_test_name,
        static = _ANDROID_STATIC_DEPS,
        shared = _SHARED_DEP,
        target_under_test = target_name,
    )

    _stl_deps_non_android_test(
        name = non_android_test_name,
        shared = _SHARED_DEP,
        target_under_test = target_name,
    )

    return [android_test_name, non_android_test_name]

def _test_stl_for_shared_library_system_uses_shared():
    target_name = _stl_deps("system", is_shared = True, is_binary = False)
    android_test_name = target_name + "_android_test"
    non_android_test_name = target_name + "_non_android_test"

    _stl_deps_android_test(
        name = android_test_name,
        static = _ANDROID_STATIC_DEPS,
        shared = _SHARED_DEP,
        target_under_test = target_name,
    )

    _stl_deps_non_android_test(
        name = non_android_test_name,
        shared = _SHARED_DEP,
        target_under_test = target_name,
    )

    return [android_test_name, non_android_test_name]

def _test_stl_for_shared_library_libcpp_uses_shared():
    target_name = _stl_deps("libc++", is_shared = True, is_binary = False)
    android_test_name = target_name + "_android_test"
    non_android_test_name = target_name + "_non_android_test"

    _stl_deps_android_test(
        name = android_test_name,
        static = _ANDROID_STATIC_DEPS,
        shared = _SHARED_DEP,
        target_under_test = target_name,
    )

    _stl_deps_non_android_test(
        name = non_android_test_name,
        shared = _SHARED_DEP,
        target_under_test = target_name,
    )

    return [android_test_name, non_android_test_name]

def _test_stl_for_shared_library_libcpp_static_uses_static():
    target_name = _stl_deps("libc++_static", is_shared = True, is_binary = False)
    android_test_name = target_name + "_android_test"
    non_android_test_name = target_name + "_non_android_test"

    _stl_deps_android_test(
        name = android_test_name,
        static = _ANDROID_STATIC_DEPS + _STATIC_DEP,
        target_under_test = target_name,
    )

    _stl_deps_non_android_test(
        name = non_android_test_name,
        static = _STATIC_DEP,
        target_under_test = target_name,
    )

    return [android_test_name, non_android_test_name]

def _test_stl_for_static_library_unspecified_defaults_static():
    target_name = _stl_deps("", is_shared = False, is_binary = False)
    android_test_name = target_name + "_android_test"
    non_android_test_name = target_name + "_non_android_test"

    _stl_deps_android_test(
        name = android_test_name,
        static = _ANDROID_STATIC_DEPS + _STATIC_DEP,
        target_under_test = target_name,
    )

    _stl_deps_non_android_test(
        name = non_android_test_name,
        static = _STATIC_DEP,
        target_under_test = target_name,
    )

    return [android_test_name, non_android_test_name]

def _test_stl_for_static_library_system_uses_static():
    target_name = _stl_deps("system", is_shared = False, is_binary = False)
    android_test_name = target_name + "_android_test"
    non_android_test_name = target_name + "_non_android_test"

    _stl_deps_android_test(
        name = android_test_name,
        static = _ANDROID_STATIC_DEPS + _STATIC_DEP,
        target_under_test = target_name,
    )

    _stl_deps_non_android_test(
        name = non_android_test_name,
        static = _STATIC_DEP,
        target_under_test = target_name,
    )

    return [android_test_name, non_android_test_name]

def _test_stl_for_static_library_libcpp_uses_shared():
    target_name = _stl_deps("libc++", is_shared = False, is_binary = False)
    android_test_name = target_name + "_android_test"
    non_android_test_name = target_name + "_non_android_test"

    _stl_deps_android_test(
        name = android_test_name,
        static = _ANDROID_STATIC_DEPS,
        shared = _SHARED_DEP,
        target_under_test = target_name,
    )

    _stl_deps_non_android_test(
        name = non_android_test_name,
        shared = _SHARED_DEP,
        target_under_test = target_name,
    )

    return [android_test_name, non_android_test_name]

def _test_stl_for_static_library_libcpp_static_uses_static():
    target_name = _stl_deps("libc++_static", is_shared = False, is_binary = False)
    android_test_name = target_name + "_android_test"
    non_android_test_name = target_name + "_non_android_test"

    _stl_deps_android_test(
        name = android_test_name,
        static = _ANDROID_STATIC_DEPS + _STATIC_DEP,
        target_under_test = target_name,
    )

    _stl_deps_non_android_test(
        name = non_android_test_name,
        static = _STATIC_DEP,
        target_under_test = target_name,
    )

    return [android_test_name, non_android_test_name]

def _test_stl_for_shared_binary_unspecified_defaults_shared():
    target_name = _stl_deps("", is_shared = True, is_binary = True)
    android_test_name = target_name + "_android_test"
    non_android_test_name = target_name + "_non_android_test"

    _stl_deps_android_test(
        name = android_test_name,
        static = _ANDROID_STATIC_DEPS + _ANDROID_BINARY_STATIC_DEP,
        shared = _SHARED_DEP,
        target_under_test = target_name,
    )

    _stl_deps_non_android_test(
        name = non_android_test_name,
        shared = _SHARED_DEP,
        target_under_test = target_name,
    )

    return [android_test_name, non_android_test_name]

def _test_stl_for_shared_binary_system_uses_shared():
    target_name = _stl_deps("system", is_shared = True, is_binary = True)
    android_test_name = target_name + "_android_test"
    non_android_test_name = target_name + "_non_android_test"

    _stl_deps_android_test(
        name = android_test_name,
        static = _ANDROID_STATIC_DEPS + _ANDROID_BINARY_STATIC_DEP,
        shared = _SHARED_DEP,
        target_under_test = target_name,
    )

    _stl_deps_non_android_test(
        name = non_android_test_name,
        shared = _SHARED_DEP,
        target_under_test = target_name,
    )

    return [android_test_name, non_android_test_name]

def _test_stl_for_shared_binary_libcpp_uses_shared():
    target_name = _stl_deps("libc++", is_shared = True, is_binary = True)
    android_test_name = target_name + "_android_test"
    non_android_test_name = target_name + "_non_android_test"

    _stl_deps_android_test(
        name = android_test_name,
        static = _ANDROID_STATIC_DEPS + _ANDROID_BINARY_STATIC_DEP,
        shared = _SHARED_DEP,
        target_under_test = target_name,
    )

    _stl_deps_non_android_test(
        name = non_android_test_name,
        shared = _SHARED_DEP,
        target_under_test = target_name,
    )

    return [android_test_name, non_android_test_name]

def _test_stl_for_shared_binary_libcpp_static_uses_static():
    target_name = _stl_deps("libc++_static", is_shared = True, is_binary = True)
    android_test_name = target_name + "_android_test"
    non_android_test_name = target_name + "_non_android_test"

    _stl_deps_android_test(
        name = android_test_name,
        static = _ANDROID_STATIC_DEPS + _STATIC_DEP + _ANDROID_BINARY_STATIC_DEP,
        target_under_test = target_name,
    )

    _stl_deps_non_android_test(
        name = non_android_test_name,
        static = _STATIC_DEP,
        target_under_test = target_name,
    )

    return [android_test_name, non_android_test_name]

def _test_stl_for_static_binary_unspecified_defaults_static():
    target_name = _stl_deps("", is_shared = False, is_binary = True)
    android_test_name = target_name + "_android_test"
    non_android_test_name = target_name + "_non_android_test"

    _stl_deps_android_test(
        name = android_test_name,
        static = _ANDROID_STATIC_DEPS + _STATIC_DEP + _ANDROID_BINARY_STATIC_DEP,
        target_under_test = target_name,
    )

    _stl_deps_non_android_test(
        name = non_android_test_name,
        static = _STATIC_DEP,
        target_under_test = target_name,
    )

    return [android_test_name, non_android_test_name]

def _test_stl_for_static_binary_system_uses_static():
    target_name = _stl_deps("system", is_shared = False, is_binary = True)
    android_test_name = target_name + "_android_test"
    non_android_test_name = target_name + "_non_android_test"

    _stl_deps_android_test(
        name = android_test_name,
        static = _ANDROID_STATIC_DEPS + _STATIC_DEP + _ANDROID_BINARY_STATIC_DEP,
        target_under_test = target_name,
    )

    _stl_deps_non_android_test(
        name = non_android_test_name,
        static = _STATIC_DEP,
        target_under_test = target_name,
    )

    return [android_test_name, non_android_test_name]

def _test_stl_for_static_binary_libcpp_uses_shared():
    target_name = _stl_deps("libc++", is_shared = False, is_binary = True)
    android_test_name = target_name + "_android_test"
    non_android_test_name = target_name + "_non_android_test"

    _stl_deps_android_test(
        name = android_test_name,
        static = _ANDROID_STATIC_DEPS + _ANDROID_BINARY_STATIC_DEP,
        shared = _SHARED_DEP,
        target_under_test = target_name,
    )

    _stl_deps_non_android_test(
        name = non_android_test_name,
        shared = _SHARED_DEP,
        target_under_test = target_name,
    )

    return [android_test_name, non_android_test_name]

def _test_stl_for_static_binary_libcpp_static_uses_static():
    target_name = _stl_deps("libc++_static", is_shared = False, is_binary = True)
    android_test_name = target_name + "_android_test"
    non_android_test_name = target_name + "_non_android_test"

    _stl_deps_android_test(
        name = android_test_name,
        static = _ANDROID_STATIC_DEPS + _STATIC_DEP + _ANDROID_BINARY_STATIC_DEP,
        target_under_test = target_name,
    )

    _stl_deps_non_android_test(
        name = non_android_test_name,
        static = _STATIC_DEP,
        target_under_test = target_name,
    )

    return [android_test_name, non_android_test_name]

def stl_test_suite(name):
    native.test_suite(
        name = name,
        tests = _test_stl_for_shared_library_unspecified_defaults_shared() +
                _test_stl_for_shared_library_system_uses_shared() +
                _test_stl_for_shared_library_libcpp_uses_shared() +
                _test_stl_for_shared_library_libcpp_static_uses_static() +
                _test_stl_for_static_library_unspecified_defaults_static() +
                _test_stl_for_static_library_system_uses_static() +
                _test_stl_for_static_library_libcpp_uses_shared() +
                _test_stl_for_static_library_libcpp_static_uses_static() +
                _test_stl_for_shared_binary_unspecified_defaults_shared() +
                _test_stl_for_shared_binary_system_uses_shared() +
                _test_stl_for_shared_binary_libcpp_uses_shared() +
                _test_stl_for_shared_binary_libcpp_static_uses_static() +
                _test_stl_for_static_binary_unspecified_defaults_static() +
                _test_stl_for_static_binary_system_uses_static() +
                _test_stl_for_static_binary_libcpp_uses_shared() +
                _test_stl_for_static_binary_libcpp_static_uses_static(),
    )
