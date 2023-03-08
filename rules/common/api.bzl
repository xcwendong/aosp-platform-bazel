# Copyright (C) 2023 The Android Open Source Project
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

load("@soong_injection//product_config:product_variables.bzl", "product_vars")
load("@soong_injection//api_levels:api_levels.bzl", "api_levels_released_versions")

PREVIEW_API_LEVEL_BASE = 9000
FUTURE_API_LEVEL_INT = 10000  # API Level associated with an arbitrary future release

def _api_levels_with_previews():
    ret = dict(api_levels_released_versions)
    active_codenames = product_vars.get("Platform_version_active_codenames", [])
    for i, codename in enumerate(active_codenames):
        ret[codename] = PREVIEW_API_LEVEL_BASE + i
    return ret

def _api_levels_with_final_codenames():
    ret = dict(api_levels_released_versions)
    if product_vars.get("Platform_sdk_final"):
        platform_sdk_version = product_vars.get("Platform_sdk_version")
        if platform_sdk_version != None:
            ret["current"] = platform_sdk_version
    return ret

api_levels_with_previews = _api_levels_with_previews()

# parse_api_level_from_version is a Starlark implementation of ApiLevelFromUser
# at https://cs.android.com/android/platform/superproject/+/master:build/soong/android/api_levels.go;l=221-250;drc=5095a6c4b484f34d5c4f55a855d6174e00fb7f5e
def parse_api_level_from_version(version):
    """converts the given string `version` to an api level

    Args:
        version: must be non-empty. Inputs that are not "current", known
        previews, or convertible to an integer will return an error.

    Returns: The api level. This can be an int or unreleased version full name (string).
        Finalized codenames will be interpreted as their final API levels, not
        the preview of the associated releases. Future codenames return the
        version codename.
    """
    api_levels = api_levels_with_previews
    if version == "":
        fail("API level string must be non-empty")

    if version == "current":
        return FUTURE_API_LEVEL_INT

    if version in api_levels:
        return api_levels[version]

    elif version.isdigit():
        return int(version)
    else:
        fail("version could not be parsed as integer and is not a recognized codename")

# Starlark implementation of DefaultAppTargetSDK from build/soong/android/config.go
# https://cs.android.com/android/platform/superproject/+/master:build/soong/android/config.go;l=875-889;drc=b0dc477ef740ec959548fe5517bd92ac4ea0325c
# check what you want returned for codename == "" case before using
def default_app_target_sdk():
    """default_app_target_sdk returns the API level that platform apps are targeting.
       This converts a codename to the exact ApiLevel it represents.
    """
    if product_vars.get("Platform_sdk_final"):
        return product_vars.get("Platform_sdk_version")

    codename = product_vars.get("Platform_sdk_codename")
    if codename == "" or codename == None:
        # soong returns NoneApiLevel here value: "(no version)", number: -1, isPreview: true
        # APEX's targetSdkVersion sets this to FUTURE_API_LEVEL
        return FUTURE_API_LEVEL_INT

    if codename == "REL":
        fail("Platform_sdk_codename should not be REL when Platform_sdk_final is false")

    return parse_api_level_from_version(codename)
