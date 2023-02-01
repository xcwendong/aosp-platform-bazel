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

FDO_PROFILE_ATTR = "fdo_profile"

def _fdo_profile_transition_impl(setting, attr):
    # https://github.com/bazelbuild/bazel/blob/8a53b0e51506d825d276ea7c9480190bd2287009/src/main/java/com/google/devtools/build/lib/rules/cpp/FdoHelper.java#L170
    # Coverage mode is not compatible with FDO optimization in Bazel cc rules
    # If both collect_code_coverage is set, disable fdo optimization
    if setting["//command_line_option:collect_code_coverage"]:
        return {
            "//command_line_option:fdo_profile": None,
        }
    else:
        return {
            "//command_line_option:fdo_profile": getattr(attr, FDO_PROFILE_ATTR),
        }

# This transition reads the fdo_profile attribute of a rule and set the value
# to //command_line_option:fdo_profile"
fdo_profile_transition = transition(
    implementation = _fdo_profile_transition_impl,
    inputs = [
        "//command_line_option:collect_code_coverage",
    ],
    outputs = [
        "//command_line_option:fdo_profile",
    ],
)

def _drop_fdo_profile_transition_impl(_, __):
    return {
        "//command_line_option:fdo_profile": None,
    }

# This transition always resets //command_line_option:fdo_profile to None."
drop_fdo_profile_transition = transition(
    implementation = _drop_fdo_profile_transition_impl,
    inputs = [],
    outputs = [
        "//command_line_option:fdo_profile",
    ],
)
