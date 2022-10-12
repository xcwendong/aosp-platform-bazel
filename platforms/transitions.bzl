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

# Configuration transitions for interacting with platforms and toolchains.

def _default_android_transition_impl(settings, attr):
    # There's always only one target platform specified, despite the --platforms
    # flag name being plural.
    target_platform = settings["//command_line_option:platforms"][0]

    # Ensure that this target is always built for the android target platform.
    #
    # For example, there is currently no support for building an APEX for the
    # host (e.g. linux_x86_64) or other platforms like darwin or windows.
    #
    # This is further enforced by the toolchains for these types (apex,
    # partition) being compatible with only //build/bazel/platforms/os:android
    # for their target platform.  If we don't do this, an apex can be
    # accidentally requested for a non-android target platform, resulting in
    # toolchain resolution failures.
    if not str(target_platform).startswith("@//build/bazel/platforms:android_"):
        target_platform = Label("//build/bazel/platforms:android_target")  # default platform

    return {
        "//command_line_option:platforms": [target_platform],
    }

# A transition to always enforce an android target platform. Useful for targets
# that only has toolchains for building against android (and nothing else), like
# APEXes.
default_android_transition = transition(
    implementation = _default_android_transition_impl,
    inputs = ["//command_line_option:platforms"],
    outputs = ["//command_line_option:platforms"],
)
