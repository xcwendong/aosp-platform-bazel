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

def aidl_interface_test_suite(name):
    native.test_suite(
        name = name,
        tests = [
            "//build/bazel/rules/aidl/testing:generated_targets_have_correct_srcs_test",
            "//build/bazel/rules/aidl/testing:interface_macro_produces_all_targets_test",
        ],
    )
