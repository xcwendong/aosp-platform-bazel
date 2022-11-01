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

load("//build/bazel/product_variables:constants.bzl", "constants")
load("@soong_injection//api_levels:api_levels.bzl", "api_levels")
load("@soong_injection//product_config:product_variables.bzl", "product_vars")

_bionic_targets = ["//bionic/libc", "//bionic/libdl", "//bionic/libm"]
_static_bionic_targets = ["//bionic/libc:libc_bp2build_cc_library_static", "//bionic/libdl:libdl_bp2build_cc_library_static", "//bionic/libm:libm_bp2build_cc_library_static"]

# When building a APEX, stub libraries of libc, libdl, libm should be used in linking.
_bionic_stub_targets = [
    "//bionic/libc:libc_stub_libs_current",
    "//bionic/libdl:libdl_stub_libs_current",
    "//bionic/libm:libm_stub_libs_current",
]

# The default system_dynamic_deps value for cc libraries. This value should be
# used if no value for system_dynamic_deps is specified.
system_dynamic_deps_defaults = select({
    "//build/bazel/rules/apex:android-in_apex": _bionic_stub_targets,
    "//build/bazel/rules/apex:android-non_apex": _bionic_targets,
    "//build/bazel/rules/apex:linux_bionic-in_apex": _bionic_stub_targets,
    "//build/bazel/rules/apex:linux_bionic-non_apex": _bionic_targets,
    "//conditions:default": [],
})

system_static_deps_defaults = select({
    "//build/bazel/rules/apex:android-in_apex": _bionic_stub_targets,
    "//build/bazel/rules/apex:android-non_apex": _static_bionic_targets,
    "//build/bazel/rules/apex:linux_bionic-in_apex": _bionic_stub_targets,
    "//build/bazel/rules/apex:linux_bionic-non_apex": _static_bionic_targets,
    "//conditions:default": [],
})

future_version = "10000"

def _create_sdk_version_features_map():
    version_feature_map = {}
    for api in api_levels.values():
        version_feature_map["//build/bazel/rules/apex:min_sdk_version_" + str(api)] = ["sdk_version_" + str(api)]
    version_feature_map["//conditions:default"] = ["sdk_version_" + future_version]

    return version_feature_map

sdk_version_features = select(_create_sdk_version_features_map())

def add_lists_defaulting_to_none(*args):
    """Adds multiple lists, but is well behaved with a `None` default."""
    combined = None
    for arg in args:
        if arg != None:
            if combined == None:
                combined = []
            combined += arg

    return combined

# By default, crtbegin/crtend linking is enabled for shared libraries and cc_binary.
def disable_crt_link(features):
    return features + ["-link_crt"]

# get_includes_paths expects a rule context, a list of directories, and
# whether the directories are package-relative and returns a list of exec
# root-relative paths. This handles the need to search for files both in the
# source tree and generated files.
def get_includes_paths(ctx, dirs, package_relative = True):
    execution_relative_dirs = []
    for rel_dir in dirs:
        if rel_dir == ".":
            rel_dir = ""
        execution_rel_dir = rel_dir
        if package_relative:
            execution_rel_dir = ctx.label.package
            if len(rel_dir) > 0:
                execution_rel_dir = execution_rel_dir + "/" + rel_dir

        # To allow this repo to be used as an external one.
        repo_prefix_dir = execution_rel_dir
        if ctx.label.workspace_root != "":
            repo_prefix_dir = ctx.label.workspace_root + "/" + execution_rel_dir
        execution_relative_dirs.append(repo_prefix_dir)

        # to support generated files, we also need to export includes relatives to the bin directory
        if not execution_rel_dir.startswith("/"):
            execution_relative_dirs.append(ctx.bin_dir.path + "/" + execution_rel_dir)
    return execution_relative_dirs

def create_ccinfo_for_includes(
        ctx,
        hdrs = [],
        includes = [],
        absolute_includes = [],
        system_includes = [],
        deps = []):
    # Create a compilation context using the string includes of this target.
    compilation_context = cc_common.create_compilation_context(
        headers = depset(hdrs),
        includes = depset(
            get_includes_paths(ctx, includes) +
            get_includes_paths(ctx, absolute_includes, package_relative = False),
        ),
        system_includes = depset(get_includes_paths(ctx, system_includes)),
    )

    # Combine this target's compilation context with those of the deps; use only
    # the compilation context of the combined CcInfo.
    cc_infos = [dep[CcInfo] for dep in deps]
    cc_infos += [CcInfo(compilation_context = compilation_context)]
    combined_info = cc_common.merge_cc_infos(cc_infos = cc_infos)

    return CcInfo(compilation_context = combined_info.compilation_context)

def is_external_directory(package_name):
    if package_name.startswith("external"):
        return True
    if package_name.startswith("hardware"):
        paths = package_name.split("/")
        if len(paths) < 2:
            return True
        secondary_path = paths[1]
        if secondary_path in ["google", "interfaces", "ril"]:
            return False
        return not secondary_path.startswith("libhardware")
    if package_name.startswith("vendor"):
        paths = package_name.split("/")
        if len(paths) < 2:
            return True
        secondary_path = paths[1]
        return "google" not in secondary_path
    return False

# TODO: Move this to a common rule dir, instead of a cc rule dir. Nothing here
# should be cc specific, except that the current callers are (only) cc rules.
def parse_sdk_version(version):
    if version == "apex_inherit":
        # use the version determined by the transition value.
        return sdk_version_features

    return ["sdk_version_" + parse_apex_sdk_version(version)]

def parse_apex_sdk_version(version):
    if version == "" or version == "current":
        return future_version
    elif version.isdigit() and int(version) in api_levels.values():
        return version
    elif version in api_levels.keys():
        return str(api_levels[version])
    elif version.isdigit() and int(version) == product_vars["Platform_sdk_version"]:
        # For internal branch states, support parsing a finalized version number
        # that's also still in
        # product_vars["Platform_version_active_codenames"], but not api_levels.
        #
        # This happens a few months each year on internal branches where the
        # internal master branch has a finalized API, but is not released yet,
        # therefore the Platform_sdk_version is usually latest AOSP dessert
        # version + 1. The generated api_levels map sets these to 9000 + i,
        # where i is the index of the current/future version, so version is not
        # in the api_levels.values() list, but it is a valid sdk version.
        #
        # See also b/234321488#comment2
        return version
    else:
        fail("Unknown sdk version: %s, could not be parsed as " % version +
             "an integer and/or is not a recognized codename. Valid api levels are:" +
             str(api_levels))

_HEADER_EXTENSIONS = ["h", "hh", "hpp", "hxx", "h++", "inl", "inc", "ipp", "h.generic"]

def get_non_header_srcs(srcs):
    """get_non_header_srcs returns a list of srcs that do not have header extensions and aren't in the exclude srcs list

    Args:
        srcs (list[File]): list of file to filter
    Returns:
        list[File]: files that have non-header extension and are not excluded
    """
    srcs = []
    hdrs = []
    for s in srcs:
        if s.extension not in _HEADER_EXTENSIONS:
            srcs.append(s)
        else:
            hdrs.append(s)
    return srcs, hdrs
