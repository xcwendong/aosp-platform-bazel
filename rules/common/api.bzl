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

load("@soong_injection//product_config:product_variables.bzl", "product_vars")
load("@soong_injection//api_levels:api_levels.bzl", "api_levels_released_versions")

PREVIEW_API_LEVEL_BASE = 9000

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
