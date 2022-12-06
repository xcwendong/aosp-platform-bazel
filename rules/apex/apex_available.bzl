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

load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load("//build/bazel/rules/apex:cc.bzl", "CC_ATTR_ASPECTS")
load("//build/bazel/rules:prebuilt_file.bzl", "PrebuiltFileInfo")
load("//build/bazel/rules/cc:cc_stub_library.bzl", "CcStubLibrarySharedInfo")

# Allowlist of APEX names that are validated with apex_available.
#
# Certain apexes are not checked because their dependencies aren't converting
# apex_available to tags properly in the bp2build converters yet. See associated
# bugs for more information.
_unchecked_apexes = [
    # TODO(b/216741746, b/239093645): support aidl and hidl apex_available props.
    "com.android.neuralnetworks",
    "com.android.media.swcodec",
]

def _validate_apex_available(target, ctx):
    # testonly apexes aren't checked.
    if ctx.attr.testonly:
        return

    # Macro-internal manual targets aren't checked.
    if "manual" in ctx.rule.attr.tags and "apex_available_checked_manual_for_testing" not in ctx.rule.attr.tags:
        return

    # prebuilt_file targets don't specify apex_available, and aren't checked.
    if PrebuiltFileInfo in target:
        return

    # stubs are APIs, and don't specify apex_available, and aren't checked.
    if CcStubLibrarySharedInfo in target:
        return

    # Extract the apex_available= tags from the full list of tags.
    apex_available_tags = [
        t.removeprefix("apex_available=")
        for t in ctx.rule.attr.tags
        if t.startswith("apex_available=")
    ]

    if "//apex_available:anyapex" in apex_available_tags:
        return

    apex_name = ctx.attr._apex_name[BuildSettingInfo].value
    base_apex_name = ctx.attr._base_apex_name[BuildSettingInfo].value

    if apex_name in _unchecked_apexes:
        # Skipped unchecked APEXes.
        return
    elif base_apex_name not in apex_available_tags and apex_name not in apex_available_tags:
        msg = ("the {label} {rule_kind} is a dependency of {apex_name} apex, " +
               "but does not include the apex in its apex_available tags: {tags}").format(
            label = ctx.label,
            rule_kind = ctx.rule.kind,
            apex_name = apex_name,
            tags = apex_available_tags,
        )
        fail(msg)

    # All good!

def _apex_available_aspect_impl(target, ctx):
    _validate_apex_available(target, ctx)

    return []  # aspects need to return something.

apex_available_aspect = aspect(
    implementation = _apex_available_aspect_impl,
    attrs = {
        "_apex_name": attr.label(default = "//build/bazel/rules/apex:apex_name"),
        "_base_apex_name": attr.label(default = "//build/bazel/rules/apex:base_apex_name"),
        "testonly": attr.bool(default = False),  # propagated from the apex
    },
    # This can lead to false negatives, where new non-cc deps are
    # added and the checks aren't applied on them.
    #
    # The good thing is that we control exactly which files get included in an
    # APEX, so this could technically be * (all edges), and then we filter for
    # payload-contributing targets in the apex_available_aspect, perhaps by
    # inspecting for special Providers, like ApexCcInfo.
    attr_aspects = CC_ATTR_ASPECTS,
)
