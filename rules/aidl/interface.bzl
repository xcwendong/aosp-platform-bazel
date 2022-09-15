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
load("//build/bazel/rules/cc:cc_aidl_code_gen.bzl", "cc_aidl_code_gen")
load("//build/bazel/rules/cc:cc_library_shared.bzl", "cc_library_shared")
load("//build/bazel/rules/cc:cc_library_static.bzl", "cc_library_static")

#TODO(b/229251008) set _allowed_backends = ["java", "cpp", "rust", "ndk"]
_allowed_backends = ["java", "ndk", "cpp"]

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
        name = latest_name,
        actual = ":" + last_version_name,
        **kwargs
    )
    for b in backends:
        language_binding_name = last_version_name + "-" + b
        native.alias(
            name = latest_name + "-" + b,
            actual = ":" + language_binding_name,
            **kwargs
        )

def aidl_interface(
        name,
        deps = None,
        strip_import_prefix = "",
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

    # When versions_with_info is set, versions is no-op.
    # TODO(b/244349745): Modify bp2build to skip convert versions if versions_with_info is set
    if (versions == None and versions_with_info == None and srcs == None):
        fail("must specify at least versions, versions_with_info, or srcs")

    aidl_flags = ["--structured"]
    if flags != None:
        aidl_flags.extend(flags)

    # https://cs.android.com/android/platform/superproject/+/master:system/tools/aidl/build/aidl_interface.go;l=329;drc=e88d9a9b14eafb064a234d555a5cd96de97ca9e2
    # only vintf is allowed currently
    if stability != None and stability in ["vintf"]:
        aidl_flags.append("--stability=" + stability)

        # TODO(b/245738285): Add support for vintf stability in java backend
        if "java" in backends:
            backends.remove("java")

    if srcs != None and len(srcs) > 0:
        create_aidl_binding_for_backends(
            name = name,
            srcs = srcs,
            strip_import_prefix = strip_import_prefix,
            deps = deps,
            backends = backends,
            aidl_flags = aidl_flags,
            **kwargs
        )

    # versions will be deprecated after all migrated to versions_with_info
    if versions_with_info != None and len(versions_with_info) > 0:
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
    elif versions != None and len(versions) > 0:
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

def create_aidl_binding_for_backends(name, version = None, srcs = None, strip_import_prefix = "", deps = None, aidl_flags = [], backends = [], **kwargs):
    """
    Create aidl_library target and corrending <backend>_aidl_library target for a given version

    Arguments:
        name:                   string, base name of the aidl interface
        version:                string, version of the aidl interface
        srcs:                   List[Label] list of unversioned AIDL srcs
        strip_import_prefix     string, the prefix to strip the paths of the .aidl files in srcs
        deps:                   List[AidlGenInfo], a list of other aidl_libraries that the version depends on
                                the label of the targets have format <aidl-interface>-V<version_number>
        aidl_flags:             List[string], a list of flags to pass to the AIDL compiler
        backends:               List[string], a list of the languages to generate bindings for
    """
    if version != None and srcs != None:
        fail("Can not set both version and srcs. Srcs is for unversioned AIDL")

    aidl_library_name = name

    if version:
        aidl_library_name = name + "-V" + version
        strip_import_prefix = "aidl_api/{}/{}".format(name, version)
        srcs = native.glob([strip_import_prefix + "/**/*.aidl"])

    aidl_library(
        name = aidl_library_name,
        deps = deps,
        strip_import_prefix = strip_import_prefix,
        srcs = srcs,
        flags = aidl_flags,
        **kwargs
    )

    for backend in backends:
        if backend == "java":
            java_aidl_library(
                name = aidl_library_name + "-java",
                deps = [":" + aidl_library_name],
                **kwargs
            )
        elif backend == "cpp" or backend == "ndk":
            dynamic_deps = []

            # https://cs.android.com/android/platform/superproject/+/master:system/tools/aidl/build/aidl_interface_backends.go;l=564;drc=0517d97079d4b08f909e7f35edfa33b88fcc0d0e
            if deps != None:
                # For each aidl_library target label versioned_name, there's an
                # associated cc_library_shared target with label versioned_name-<cpp|ndk>
                dynamic_deps.extend(["{}-{}".format(dep, backend) for dep in deps])

            # https://cs.android.com/android/platform/superproject/+/master:system/tools/aidl/build/aidl_interface_backends.go;l=111;drc=ef9f1352a1a8fec7bb134b1c713e13fc3ccee651
            if backend == "cpp":
                dynamic_deps.extend([
                    "//frameworks/native/libs/binder:libbinder",
                    "//system/core/libutils:libutils",
                ])
            elif backend == "ndk":
                dynamic_deps.append("//frameworks/native/libs/binder/ndk:libbinder_ndk")

            _cc_aidl_libraries(
                name = "{}-{}".format(aidl_library_name, backend),
                aidl_library = ":" + aidl_library_name,
                dynamic_deps = dynamic_deps,
                lang = backend,
                **kwargs
            )

# _cc_aidl_libraries is slightly different from cc_aidl_library macro provided
# from //bazel/bulid/rules/cc:cc_aidl_libray.bzl.
#
# Instead of creating one cc_library_static target, _cc_aidl_libraries creates
# both static and shared variants of cc library so that the upstream modules
# can reference the aidl interface with ndk or cpp backend as either static
# or shared lib
def _cc_aidl_libraries(
        name,
        aidl_library = None,
        implementation_deps = [],
        dynamic_deps = [],
        lang = None,
        **kwargs):
    """
    Generate AIDL stub code for cpp or ndk backend and wrap it in cc libraries (both shared and static variant)

    Args:
        name:                (String) name of the cc_library_static target
        aidl_library:        (AidlGenInfo) aidl_library that this cc_aidl_library depends on
        implementation_deps: (list[CcInfo]) internal cpp/ndk dependencies of the created cc_library_static target
        dynamic_deps:        (list[CcInfo])  dynamic dependencies of the created cc_library_static and cc_library_shared targets
        lang:                (String) lang to be passed into --lang flag of aidl generator
        **kwargs:            extra arguments that will be passesd to cc_aidl_code_gen and cc library rules.
    """

    if lang == None:
        fail("lang must be set")
    if lang != "cpp" and lang != "ndk":
        fail("lang {} is unsupported. Allowed lang: ndk, cpp.")

    aidl_code_gen = name + "_aidl_code_gen"

    cc_aidl_code_gen(
        name = aidl_code_gen,
        deps = [aidl_library],
        lang = lang,
        **kwargs
    )

    cc_library_shared(
        name = name,
        srcs = [":" + aidl_code_gen],
        implementation_deps = implementation_deps,
        deps = [aidl_code_gen],
        dynamic_deps = dynamic_deps,
        **kwargs
    )
    cc_library_static(
        name = name + "_bp2build_cc_library_static",
        srcs = [":" + aidl_code_gen],
        implementation_deps = implementation_deps,
        deps = [aidl_code_gen],
        dynamic_deps = dynamic_deps,
        **kwargs
    )
