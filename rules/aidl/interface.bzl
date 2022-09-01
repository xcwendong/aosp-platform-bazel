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

load("//build/bazel/rules/aidl:library.bzl", "aidl_library")
load("//build/bazel/rules/java:aidl_library.bzl", "java_aidl_library")
load("//build/bazel/rules/cc:cc_aidl_library.bzl", "cc_aidl_library")

#TODO(b/229251008) set _allowed_backends = ["java", "cpp", "rust", "ndk"]
_allowed_backends = ["java", "ndk"]

def _check_versions(versions):
    versions = sorted([int(i) for i in versions])  # ensure that all versions are ints
    for i, v in enumerate(versions):
        if i > 0 and v == versions[i - 1]:
            fail("duplicate version found:", v)
        if v <= 0:
            fail("all versions should be > 0, but found version:", v)
    return [str(i) for i in versions]

def _create_latest_version_aliases(name, last_version_name, backends, **kwargs):
    latest_name = name + "-latest"
    native.alias(
        name = name,
        actual = ":" + last_version_name,
        **kwargs
    )
    native.alias(
        name = latest_name,
        actual = ":" + last_version_name,
        **kwargs
    )
    for b in backends:
        language_binding_name = last_version_name + "-" + b
        native.alias(
            name = name + "-" + b,
            actual = ":" + language_binding_name,
            **kwargs
        )
        native.alias(
            name = latest_name + "-" + b,
            actual = ":" + language_binding_name,
            **kwargs
        )

def aidl_interface(
        name,
        deps = None,
        include_dir = None,
        srcs = None,
        flags = None,
        backends = _allowed_backends,
        stability = None,
        # TODO: Remove versions after aidl_interface module type deprecates
        # versions prop in favor of versions_with_info prop
        versions = None,
        versions_with_info = None,
        **kwargs):
    """aidl_interface creates a versioned aidl_libraries and language-specific *_aidl_libraries

    This macro loops over the list of required versions and searches for all
    *.aidl source files located under the path `aidl_api/<version label/`.
    For each version, an `aidl_library` is created with the corresponding sources.
    For each `aidl_library`, a language-binding library *_aidl_library is created
    based on the values passed to the `backends` argument.

    Arguments:
        name: string, base name of generated targets: <module-name>-V<version number>-<language-type>
        versions: List[str], list of version labels with associated source directories
        deps: List[AidlGenInfo], a list of other aidl_libraries that all versions of this interface depend on
        include_dir: str, a local directory to pass to the AIDL compiler to satisfy imports
        srcs: List[file], a list of files to include in the development (unversioned) version of the aidl_interface
        flags: List[string], a list of flags to pass to the AIDL compiler
        backends: List[string], a list of the languages to generate bindings for
    """
    for b in backends:
        if b not in _allowed_backends:
            fail("Cannot use backend `{}` in aidl_interface. Allowed backends: {}".format(b, _allowed_backends))

    if (versions == None and srcs == None and versions_with_info == None):
        fail("must specify either versions or versions_with_info")

    if srcs != None:
        #TODO(b/229251008) support "current" development version srcs
        fail("srcs attribute not currently supported. See b/229251008")
    if include_dir != None:
        #TODO(b/229251008) support "current" development version srcs
        fail("include_dir attribute not currently supported. See b/229251008")

    aidl_flags = ["--structured"]
    if flags != None:
        aidl_flags.extend(flags)

    # https://cs.android.com/android/platform/superproject/+/master:system/tools/aidl/build/aidl_interface.go;l=329;drc=e88d9a9b14eafb064a234d555a5cd96de97ca9e2
    # only vintf is allowed currently
    if stability != None and stability in ["vintf"]:
        aidl_flags.append("--stability=" + stability)

    if versions_with_info != None:
        versions = _check_versions([
            version_with_info["version"]
            for version_with_info in versions_with_info
        ])
        for version_with_info in versions_with_info:
            create_aidl_binding_for_backends(
                name = name,
                version = version_with_info["version"],
                deps = version_with_info["deps"],
                aidl_flags = aidl_flags,
                backends = backends,
                **kwargs
            )
        if len(versions_with_info) > 0:
            _create_latest_version_aliases(
                name,
                name + "-V" + versions[-1],
                backends,
                **kwargs
            )
    else:
        versions = _check_versions(versions)
        for version in versions:
            create_aidl_binding_for_backends(
                name = name,
                version = version,
                deps = deps,
                aidl_flags = aidl_flags,
                backends = backends,
                **kwargs
            )
        if len(versions) > 0:
            _create_latest_version_aliases(
                name,
                name + "-V" + versions[-1],
                backends,
                **kwargs
            )

def create_aidl_binding_for_backends(name, version, deps = None, aidl_flags = [], backends = [], **kwargs):
    """
    Create aidl_library target and corrending <backend>_aidl_library target for a given version

    Arguments:
        name:           string, base name of the aidl interface
        version:        string, version of the aidl interface
        deps:           List[AidlGenInfo], a list of other aidl_libraries that the version depends on
                        the label of the targets have format <aidl-interface>-V<version_number>
        aidl_flags:     List[string], a list of flags to pass to the AIDL compiler
        backends: List[string], a list of the languages to generate bindings for
    """
    versioned_name = name + "-V" + version
    aidl_src_dir = "aidl_api/{}/{}".format(name, version)

    aidl_library(
        name = versioned_name,
        deps = deps,
        strip_import_prefix = aidl_src_dir,
        srcs = native.glob([aidl_src_dir + "/**/*.aidl"]),
        flags = aidl_flags,
        **kwargs
    )

    if "java" in backends:
        java_aidl_library(
            name = versioned_name + "-java",
            deps = [":" + versioned_name],
            **kwargs
        )
    if "ndk" in backends:
        ndk_deps = []
        if deps != None:
            # For each aidl_library target label versioned_name, there's an
            # associated ndk binding target with label versioned_name-ndk
            ndk_deps = ["{}-ndk".format(dep) for dep in deps]
        cc_aidl_library(
            name = versioned_name + "-ndk",
            deps = [":" + versioned_name],
            # Pass generated headers of deps explicitly to implementation_deps
            # for cc library to compile
            implementation_deps = ndk_deps,
            # http://cs/aosp-master/system/tools/aidl/build/aidl_interface_backends.go;l=117;rcl=2acaf840721ac1de9bec847cbdf167e61cd765d5
            dynamic_deps = ["//frameworks/native/libs/binder/ndk:libbinder_ndk"],
            lang = "ndk",
            **kwargs
        )
