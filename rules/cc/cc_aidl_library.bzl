# Copyright (C) 2022 The Android Open Source Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

load("//build/bazel/rules/cc:cc_aidl_code_gen.bzl", "cc_aidl_code_gen")
load("//build/bazel/rules/cc:cc_library_static.bzl", "cc_library_static")

def cc_aidl_library(
        name,
        deps = [],
        implementation_dynamic_deps = [],
        **kwargs):
    """
    Generate AIDL stub code for C++ and wrap it in a cc_library_static target

    Args:
        name:                        (String) name of the cc_library_static target
        deps:                        (list[AidlGenInfo]) list of all aidl_libraries that this cc_aidl_library depends on
        implementation_dynamic_deps: (list[CcInfo]) list of cc_library_shared needed to compile the created cc_library_static target
        **kwargs:                    extra arguments that will be passesd to cc_aidl_code_gen and cc_library_static.
    """

    aidl_code_gen = name + "_aidl_code_gen"

    cc_aidl_code_gen(
        name = aidl_code_gen,
        deps = deps,
        lang = "cpp",
        **kwargs
    )

    cc_library_static(
        name = name,
        srcs = [":" + aidl_code_gen],
        # The generated headers from aidl_code_gen include the headers in
        # :libbinder_headers. All cc library/binary targets that depends on
        # cc_aidl_library needs to to explicitly include
        # //frameworks/native/libs/binder:libbinder which re-exports
        # //frameworks/native/libs/binder:libbinder_headers
        implementation_deps = [
            "//frameworks/native/libs/binder:libbinder_headers",
        ],
        implementation_dynamic_deps = implementation_dynamic_deps,
        deps = [aidl_code_gen],
        **kwargs
    )
