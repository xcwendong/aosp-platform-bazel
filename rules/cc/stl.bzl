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

# Helpers for stl property resolution.
# These mappings taken from build/soong/cc/stl.go

load("//build/bazel/product_variables:constants.bzl", "constants")

_libcpp_stl_names = {
    "libc++": True,
    "libc++_static": True,
    "": True,
    "system": True,
}

# https://cs.android.com/android/platform/superproject/+/master:build/soong/cc/stl.go;l=157;drc=55d98d2ba142d6c35894b1092397e2b5a70bc2e8
_common_static_deps = select({
    constants.ArchVariantToConstraints["android"]: ["//external/libcxxabi:libc++demangle"],
    "//conditions:default": [],
})

# https://cs.android.com/android/platform/superproject/+/master:build/soong/cc/stl.go;l=162;drc=cb0ac95bde896fa2aa59193a37ceb580758c322c
# this should vary based on vndk version
# skip libm and libc because then we would have duplicates due to system_shared_library
_libunwind = "//prebuilts/clang/host/linux-x86:libunwind"

_static_binary_deps = select({
    constants.ArchVariantToConstraints["android"]: [_libunwind],
    constants.ArchVariantToConstraints["linux_bionic"]: [_libunwind],
    "//conditions:default": [],
})

def stl_deps(stl_name, is_shared, is_binary = False):
    if stl_name == "none":
        return struct(static = [], shared = [])
    if stl_name not in _libcpp_stl_names:
        fail("Unhandled stl %s" % stl_name)
    if stl_name in ("", "system"):
        if is_shared:
            stl_name = "libc++"
        else:
            stl_name = "libc++_static"

    shared, static = [], []
    if stl_name == "libc++":
        static, shared = _shared_stl_deps(stl_name)
    elif stl_name == "libc++_static":
        static = _static_stl_deps(stl_name)
    if is_binary:
        static += _static_binary_deps
    return struct(
        static = static,
        shared = shared,
    )

def _static_stl_deps(stl_name):
    # TODO(b/201079053): Handle useSdk, windows, preferably with selects.
    return ["//external/libcxx:libc++_static"] + _common_static_deps

def _shared_stl_deps(stl_name):
    return (_common_static_deps, ["//external/libcxx:libc++"])
