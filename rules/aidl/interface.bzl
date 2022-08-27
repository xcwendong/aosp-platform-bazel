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

#TODO(b/229251008) set _allowed_backends = ["java", "cpp", "rust", "ndk"]
_allowed_backends = ["java"]

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
        versions = None,
        deps = None,
        include_dir = None,
        srcs = None,
        flags = None,
        backends = _allowed_backends,
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

    if versions == None and srcs == None:
        fail("must specify either versions or srcs")

    if srcs != None:
        #TODO(b/229251008) support "current" development version srcs
        fail("srcs attribute not currently supported. See b/229251008")
    if include_dir != None:
        #TODO(b/229251008) support "current" development version srcs
        fail("include_dir attribute not currently supported. See b/229251008")

    versions = _check_versions(versions)
    for v in versions:
        versioned_name = name + "-V" + v
        aidl_src_dir = "aidl_api/{}/{}".format(name, v)

        aidl_library(
            name = versioned_name,
            deps = deps,
            strip_import_prefix = aidl_src_dir,
            srcs = native.glob([aidl_src_dir + "/**/*.aidl"]),
            flags = flags,
            **kwargs
        )

        if "java" in backends:
            java_aidl_library(
                name = versioned_name + "-java",
                deps = [":" + versioned_name],
                **kwargs
            )

    if len(versions) > 0:
        _create_latest_version_aliases(name, name + "-V" + versions[-1], backends, **kwargs)
