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
        implementation_deps = [],
        implementation_dynamic_deps = [],
        tags = [],
        min_sdk_version = None,
        **kwargs):
    """
    Generate AIDL stub code for C++ and wrap it in a cc_library_static target

    Args:
        name:                        (String) name of the cc_library_static target
        deps:                        (list[AidlGenInfo]) list of all aidl_libraries that this cc_aidl_library depends on
        implementation_deps:         (list[CcInfo]) list of cc_library_static needed to compile the created cc_library_static target
        implementation_dynamic_deps: (list[CcInfo]) list of cc_library_shared needed to compile the created cc_library_static target
        **kwargs:                    extra arguments that will be passesd to cc_aidl_code_gen and cc_library_static.
    """

    aidl_code_gen = name + "_aidl_code_gen"

    cc_aidl_code_gen(
        name = aidl_code_gen,
        deps = deps,
        lang = "cpp",
        tags = tags + ["manual"],
        **kwargs
    )

    cc_library_static(
        name = name,
        srcs = [":" + aidl_code_gen],
        implementation_deps = implementation_deps,
        implementation_dynamic_deps = implementation_dynamic_deps,
        deps = [aidl_code_gen],
        tags = tags,
        min_sdk_version = min_sdk_version,
        **kwargs
    )
