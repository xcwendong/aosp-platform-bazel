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

load("//build/bazel/rules/cc:cc_library_shared.bzl", "CcStubLibrariesInfo")
load("//build/bazel/rules/cc:cc_stub_library.bzl", "CcStubLibrarySharedInfo")
load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")

ApexCcInfo = provider(
    "Info needed to use CC targets in APEXes",
    fields = {
        "transitive_shared_libs": "File references to transitive .so libs produced by the CC targets and should be included in the APEX.",
        "provides_native_libs": "Labels of native shared libs that this apex provides.",
        "requires_native_libs": "Labels of native shared libs that this apex requires.",
    },
)

# Return True if this target provides stubs.
#
# There is no need to check versions of stubs any more, see aosp/1609533.
#
# These stable ABI libraries are intentionally omitted from APEXes as they are
# provided from another APEX or the platform.  By omitting them from APEXes, we
# ensure that there are no multiple copies of such libraries on a device.
def has_cc_stubs(target, ctx):
    if CcStubLibrarySharedInfo in target:
        # This is a stub lib (direct or transitive).
        return True

    if CcStubLibrariesInfo in target and target[CcStubLibrariesInfo].has_stubs:
        # Direct deps of the apex. The apex would depend on the source lib, not stub lib,
        # so check for CcStubLibrariesInfo.has_stubs.
        return True

    return False

# Check if this target is specified as a direct dependency of the APEX,
# as opposed to a transitive dependency, as the transitivity impacts
# the files that go into an APEX.
def is_apex_direct_dep(target, ctx):
    apex_direct_deps = ctx.attr._apex_direct_deps[BuildSettingInfo].value
    return str(target.label) in apex_direct_deps

def _validate_min_sdk_version(ctx):
    # ctx.features refer to the features of the (e.g. cc_library) target being visited
    for f in ctx.features:
        # min_sdk_version in cc targets are represented as features
        if f.startswith("sdk_version_"):
            # e.g. sdk_version_29 or sdk_version_10000
            version = f.split("_")[-1]
            min_sdk_version = ctx.attr._min_sdk_version[BuildSettingInfo].value
            if min_sdk_version < version:
                fail("The apex %s's min_sdk_version %s cannot be lower than the dep's min_sdk_version %s" %
                     (ctx.attr._apex_name[BuildSettingInfo].value, min_sdk_version, version))
            return

def _apex_cc_aspect_impl(target, ctx):
    # Ensure that dependencies are compatible with this apex's min_sdk_level
    _validate_min_sdk_version(ctx)

    # Whether this dep is a direct dep of an APEX or makes a difference in dependency
    # traversal, and aggregation of libs that are required from the platform/other APEXes,
    # and libs that this APEX will provide to others.
    is_direct_dep = is_apex_direct_dep(target, ctx)

    provides = []
    requires = []

    # The APEX manifest records the stub-providing libs (ABI-stable) in its
    # direct and transitive deps.
    #
    # If a stub-providing lib is in the direct deps of an apex, then the apex
    # provides the symbols.
    #
    # If a stub-providing lib is in the transitive deps of an apex, then the
    # apex requires the symbols from the platform or other apexes.
    if has_cc_stubs(target, ctx):
        if is_direct_dep:
            # Mark this target as "stub-providing" exports of this APEX,
            # which the system and other APEXes can depend on, and propagate
            # this list.
            provides += [target.label]
        else:
            # If this is not a direct dep, and stubs are available, don't
            # propagate the libraries. Mark this target as required from the
            # system either via the system partition, or another APEX, and
            # propagate this list.
            source_library = target[CcStubLibrarySharedInfo].source_library

            # If a stub library is in the "provides" of the apex, it doesn't need to be in the "requires"
            if not is_apex_direct_dep(source_library, ctx):
                requires += [target[CcStubLibrarySharedInfo].source_library.label]
            return [
                ApexCcInfo(
                    transitive_shared_libs = depset(),
                    requires_native_libs = depset(direct = requires),
                    provides_native_libs = depset(direct = provides),
                ),
            ]

    shared_object_files = []

    # Transitive deps containing shared libraries to be propagated the apex.
    transitive_deps = []
    rules_propagate_src = [
        "_bssl_hash_injection",
        "stripped_shared_library",
        "versioned_shared_library",
        "stripped_binary",
        "versioned_binary",
    ]

    # Exclude the stripped and unstripped so files
    if ctx.rule.kind == "_cc_library_shared_proxy":
        for output_file in target[DefaultInfo].files.to_list():
            if output_file.extension == "so":
                shared_object_files.append(output_file)
        if hasattr(ctx.rule.attr, "shared"):
            transitive_deps.append(ctx.rule.attr.shared)
    elif ctx.rule.kind in ["cc_shared_library", "cc_binary"]:
        # Propagate along the dynamic_deps and deps edges for binaries and shared libs
        if hasattr(ctx.rule.attr, "dynamic_deps"):
            for dep in ctx.rule.attr.dynamic_deps:
                transitive_deps.append(dep)
        if hasattr(ctx.rule.attr, "deps"):
            for dep in ctx.rule.attr.deps:
                transitive_deps.append(dep)
    elif ctx.rule.kind in rules_propagate_src and hasattr(ctx.rule.attr, "src"):
        # Propagate along the src edge
        transitive_deps.append(ctx.rule.attr.src)

    if ctx.rule.kind in ["stripped_binary", "_cc_library_shared_proxy", "_cc_library_combiner"] and hasattr(ctx.rule.attr, "runtime_deps"):
        for dep in ctx.rule.attr.runtime_deps:
            for output_file in dep[DefaultInfo].files.to_list():
                if output_file.extension == "so":
                    shared_object_files.append(output_file)
            transitive_deps.append(dep)

    return [
        ApexCcInfo(
            transitive_shared_libs = depset(
                shared_object_files,
                transitive = [info[ApexCcInfo].transitive_shared_libs for info in transitive_deps],
            ),
            requires_native_libs = depset(
                [],
                transitive = [info[ApexCcInfo].requires_native_libs for info in transitive_deps],
            ),
            provides_native_libs = depset(
                provides,
                transitive = [info[ApexCcInfo].provides_native_libs for info in transitive_deps],
            ),
        ),
    ]

# This aspect is intended to be applied on a apex.native_shared_libs attribute
apex_cc_aspect = aspect(
    implementation = _apex_cc_aspect_impl,
    attrs = {
        "_apex_name": attr.label(default = "//build/bazel/rules/apex:apex_name"),
        "_apex_direct_deps": attr.label(default = "//build/bazel/rules/apex:apex_direct_deps"),
        "_min_sdk_version": attr.label(default = "//build/bazel/rules/apex:min_sdk_version"),
    },
    attr_aspects = ["dynamic_deps", "deps", "shared", "src", "runtime_deps"],
    # TODO: Have this aspect also propagate along attributes of native_shared_libs?
)
