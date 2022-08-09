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
load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")

ApexCcInfo = provider(
    "Info needed to use CC targets in APEXes",
    fields = {
        "transitive_shared_libs": "File references to transitive .so libs produced by the CC targets and should be included in the APEX.",
        "provides_native_libs": "Labels of native shared libs that this apex provides.",
        "requires_native_libs": "Labels of native shared libs that this apex requires.",
    },
)

# Return True if this target provides stubs that is equal to, or below, the
# APEX's min_sdk_level.
#
# These stable ABI libraries are intentionally omitted from APEXes as they are
# provided from another APEX or the platform.  By omitting them from APEXes, we
# ensure that there are no multiple copies of such libraries on a device.
def has_cc_stubs(target, ctx):
    if ctx.rule.kind != "_cc_library_shared_proxy":
        # only _cc_library_shared_proxy contains merged CcStubLibrariesInfo providers
        # (a provider aggregating CcStubInfo and CcSharedLibraryInfo)
        return False

    if len(target[CcStubLibrariesInfo].infos) == 0:
        # Not all shared library targets have stubs
        return False

    # Minimum SDK version supported by the APEX that transitively depends on
    # this target.
    min_sdk_version = ctx.attr.min_sdk_version
    apex_name = ctx.attr._apex_name[BuildSettingInfo].value

    available_versions = []

    # Check that the shared library has stubs built for (at least) the
    # min_sdk_version of the APEX
    for stub_info in target[CcStubLibrariesInfo].infos:
        stub_version = stub_info["CcStubInfo"].version
        available_versions.append(stub_version)
        if stub_version <= min_sdk_version:
            return True

    fail("cannot find a stub lib version for min_sdk_level %s (%s apex)\navailable versions: %s (%s)" %
         (min_sdk_version, apex_name, available_versions, target.label))

# Check if this target is specified as a direct dependency of the APEX,
# as opposed to a transitive dependency, as the transitivity impacts
# the files that go into an APEX.
def is_apex_direct_dep(target, ctx):
    apex_direct_deps = ctx.attr._apex_direct_deps[BuildSettingInfo].value
    return str(target.label) in apex_direct_deps

def _apex_cc_aspect_impl(target, ctx):
    # Whether this dep is a direct dep of an APEX or makes a difference in dependency
    # traversal, and aggregation of libs that are required from the platform/other APEXes,
    # and libs that this APEX will provide to others.
    is_direct_dep = is_apex_direct_dep(target, ctx)

    provides = []

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
            return [
                ApexCcInfo(
                    transitive_shared_libs = depset(),
                    requires_native_libs = depset(direct = [target.label]),
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
        # This will be set to the min_sdk_version of the apex that runs this aspect.
        # A values list must be provided, but we want to allow all sdk versions so just generate
        # a bunch of ints here.
        "min_sdk_version": attr.string(values = ["current"] + [str(i) for i in range(50)]),
    },
    attr_aspects = ["dynamic_deps", "deps", "shared", "src", "runtime_deps"],
    # TODO: Have this aspect also propagate along attributes of native_shared_libs?
)
