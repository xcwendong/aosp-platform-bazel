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

load(":merged_txts_test.bzl", "merged_txts_test_suite")
load(":sdk_library_test.bzl", "java_sdk_library_test_suite")
load(":java_system_modules_test.bzl", "java_system_modules_test_suite")
load(":bootclasspath_test.bzl", "bootclasspath_test_suite")

java_sdk_library_test_suite(name = "java_sdk_library_tests")

merged_txts_test_suite(name = "merged_txts_tests")

java_system_modules_test_suite(name = "java_system_modules_tests")

bootclasspath_test_suite(name = "bootclasspath_tests")
