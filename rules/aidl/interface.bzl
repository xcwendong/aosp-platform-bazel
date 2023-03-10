# Copyright (C) 2022 The Android Open Source Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

load("//build/bazel/rules/aidl:library.bzl", "aidl_library")
load("//build/bazel/rules/cc:cc_aidl_code_gen.bzl", "cc_aidl_code_gen")
load("//build/bazel/rules/cc:cc_library_shared.bzl", "cc_library_shared")
load("//build/bazel/rules/cc:cc_library_static.bzl", "cc_library_static")
load("//build/bazel/rules/java:aidl_library.bzl", "java_aidl_library")

JAVA = "java"
CPP = "cpp"
NDK = "ndk"
#TODO(b/246803961) Add support for rust backend

def _check_versions(versions):
    sorted_versions = sorted([int(i) for i in versions])  # ensure that all versions are ints

    for i, v in enumerate(sorted_versions):
        if i > 0:
            if v == sorted_versions[i - 1]:
                fail("duplicate version found:", v)
            if v < sorted_versions[i - 1]:
                fail("versions should be sorted")
        if v <= 0:
            fail("all versions should be > 0, but found version:", v)
    return [str(i) for i in sorted_versions]

def _check_versions_with_info(versions_with_info):
    for version_with_info in versions_with_info:
        for dep in version_with_info.get("deps", []):
            parts = dep.split("-V")
            if len(parts) < 2 or not parts[-1].isdigit():
                fail("deps in versions_with_info must specify its version, but", dep)

def _create_latest_version_aliases(name, last_version_name, backend_configs, **kwargs):
    latest_name = name + "-latest"
    native.alias(
        name = latest_name,
        actual = ":" + last_version_name,
        **kwargs
    )
    for lang in backend_configs.keys():
        language_binding_name = last_version_name + "-" + lang
        native.alias(
            name = latest_name + "-" + lang,
            actual = ":" + language_binding_name,
            **kwargs
        )

def _versioned_name(name, version):
    if version == "":
        return name

    return name + "-V" + version

# https://cs.android.com/android/platform/superproject/+/master:system/tools/aidl/build/aidl_interface.go;l=782-799;drc=5390d9a42f5e4f99ccb3a84068f554d948cb62b9
def _next_version(versions, unstable):
    if unstable:
        return ""

    if versions == None or len(versions) == 0:
        return "1"

    return str(int(versions[-1]) + 1)

def _is_config_enabled(config):
    if config == None:
        return False

    for key in config:
        if key not in ["enabled", "min_sdk_version", "tags"]:
            fail("unknown property in aidl configuration: " + str(key))

    return config.get("enabled", False) == True

def aidl_interface(
        name,
        deps = None,
        strip_import_prefix = "",
        srcs = None,
        flags = None,
        java_config = None,
        cpp_config = None,
        ndk_config = None,
        stability = None,
        # TODO: Remove versions after aidl_interface module type deprecates
        # versions prop in favor of versions_with_info prop
        versions = None,
        versions_with_info = None,
        unstable = False,
        tags = [],
        # TODO(b/261208761): Support frozen attr
        frozen = False,
        **kwargs):
    """aidl_interface creates a versioned aidl_libraries and language-specific *_aidl_libraries

    This macro loops over the list of required versions and searches for all
    *.aidl source files located under the path `aidl_api/<version label/`.
    For each version, an `aidl_library` is created with the corresponding sources.
    For each `aidl_library`, a language-binding library *_aidl_library is created
    based on the values passed to the `backends` argument.

    Arguments:
        name:                   string, base name of generated targets: <module-name>-V<version number>-<language-type>
        versions:               List[str], list of version labels with associated source directories
        deps:                   List[AidlGenInfo], a list of other aidl_libraries that all versions of this interface depend on
        strip_import_prefix:    str, a local directory to pass to the AIDL compiler to satisfy imports
        srcs:                   List[file], a list of files to include in the development (unversioned) version of the aidl_interface
        flags:                  List[string], a list of flags to pass to the AIDL compiler
        java_config:            Dict{"enabled": bool}, config for java backend
        cpp_config:             Dict{"enabled": bool, "min_sdk_version": string}, config for cpp backend
        ndk_config:             Dict{"enabled": bool, "min_sdk_version": string}, config for ndk backend
        stability:              string, stability promise of the interface. Currently, only supports "vintf"
        backends:               List[string], a list of the languages to generate bindings for
    """

    # When versions_with_info is set, versions is no-op.
    # TODO(b/244349745): Modify bp2build to skip convert versions if versions_with_info is set
    if (versions == None and versions_with_info == None and srcs == None):
        fail("must specify at least versions, versions_with_info, or srcs")

    if versions == None and versions_with_info == None:
        if frozen == True:
            fail("frozen cannot be set without versions or versions_with_info attr being set")
    elif unstable == True:
        # https://cs.android.com/android/platform/superproject/+/master:system/tools/aidl/build/aidl_interface.go;l=872;drc=5390d9a42f5e4f99ccb3a84068f554d948cb62b9
        fail("cannot have versions for unstable interface")

    aidl_flags = ["--structured"]
    if flags != None:
        aidl_flags.extend(flags)

    enabled_backend_configs = {}
    if _is_config_enabled(java_config):
        enabled_backend_configs[JAVA] = java_config
    if _is_config_enabled(cpp_config):
        enabled_backend_configs[CPP] = cpp_config
    if _is_config_enabled(ndk_config):
        enabled_backend_configs[NDK] = ndk_config

    if stability != None:
        if unstable == True:
            fail("stability must be unset when unstable is true")
        if stability == "vintf":
            aidl_flags.append("--stability=" + stability)

            # TODO(b/245738285): Add support for vintf stability in java backend
            if JAVA in enabled_backend_configs:
                enabled_backend_configs.pop(JAVA)
        else:
            # https://cs.android.com/android/platform/superproject/+/master:system/tools/aidl/build/aidl_interface.go;l=329;drc=e88d9a9b14eafb064a234d555a5cd96de97ca9e2
            # only vintf is allowed currently
            fail("stability must be unset or \"vintf\"")

    # next_version will be the last specified version + 1.
    # https://cs.android.com/android/platform/superproject/+/master:system/tools/aidl/build/aidl_interface.go;l=791?q=system%2Ftools%2Faidl%2Fbuild%2Faidl_interface.go
    next_version = None

    # versions will be deprecated after all migrated to versions_with_info
    if versions_with_info != None and len(versions_with_info) > 0:
        versions = _check_versions([
            version_with_info["version"]
            for version_with_info in versions_with_info
        ])
        _check_versions_with_info(versions_with_info)
        next_version = _next_version(versions, False)
        for version_with_info in versions_with_info:
            create_aidl_binding_for_backends(
                name = name,
                version = version_with_info["version"],
                deps = version_with_info.get("deps"),
                aidl_flags = aidl_flags,
                backend_configs = enabled_backend_configs,
                tags = tags,
                **kwargs
            )
        if len(versions_with_info) > 0:
            _create_latest_version_aliases(
                name,
                _versioned_name(name, versions[-1]),
                enabled_backend_configs,
                tags = tags,
                **kwargs
            )
    elif versions != None and len(versions) > 0:
        versions = _check_versions(versions)
        next_version = _next_version(versions, False)
        for version in versions:
            create_aidl_binding_for_backends(
                name = name,
                version = version,
                deps = deps,
                aidl_flags = aidl_flags,
                backend_configs = enabled_backend_configs,
                tags = tags,
                **kwargs
            )
        if len(versions) > 0:
            _create_latest_version_aliases(
                name,
                _versioned_name(name, versions[-1]),
                enabled_backend_configs,
                tags = tags,
                **kwargs
            )
    else:
        next_version = _next_version(None, unstable)

    # https://cs.android.com/android/platform/superproject/+/master:system/tools/aidl/build/aidl_interface.go;l=941;drc=5390d9a42f5e4f99ccb3a84068f554d948cb62b9
    # Create aidl binding for next_version with srcs
    if srcs and len(srcs) > 0:
        create_aidl_binding_for_backends(
            name = name,
            version = next_version,
            srcs = srcs,
            strip_import_prefix = strip_import_prefix,
            deps = deps,
            aidl_flags = aidl_flags,
            backend_configs = enabled_backend_configs,
            tags = tags,
            **kwargs
        )

def create_aidl_binding_for_backends(
        name,
        version = None,
        srcs = None,
        strip_import_prefix = "",
        deps = None,
        aidl_flags = [],
        backend_configs = {},
        tags = [],
        **kwargs):
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
    aidl_library_name = _versioned_name(name, version)

    # srcs is None when create_aidl_binding_for_backends is called with a
    # frozen version specified via versions or versions_with_info.
    # next_version being equal to "" means this is an unstable version and
    # we should use srcs instead
    if srcs == None:
        if version == "":
            fail("need srcs for unversioned interface")

        strip_import_prefix = "aidl_api/{}/{}".format(name, version)
        srcs = native.glob([strip_import_prefix + "/**/*.aidl"])
        aidl_flags = aidl_flags + ["--version=" + version]

    aidl_library(
        name = aidl_library_name,
        deps = deps,
        strip_import_prefix = strip_import_prefix,
        srcs = srcs,
        flags = aidl_flags,
        # The language-specific backends will set more appropriate apex_available values.
        tags = tags + ["apex_available=//apex_available:anyapex"],
        **kwargs
    )

    for lang, config in backend_configs.items():
        # https://cs.android.com/android/platform/superproject/+/master:system/tools/aidl/build/aidl_gen_rule.go;l=207;drc=a858ae7039b876a30002a1130f24196915a859a4
        min_sdk_version = "current"
        if "min_sdk_version" in config:
            min_sdk_version = config["min_sdk_version"]

        if lang == JAVA:
            java_aidl_library(
                name = aidl_library_name + "-java",
                deps = [":" + aidl_library_name],
                tags = tags + config.get("tags", []),
                # TODO(b/249276008): Pass min_sdk_version to java_aidl_library
                **kwargs
            )
        elif lang == CPP or lang == NDK:
            dynamic_deps = []

            # https://cs.android.com/android/platform/superproject/+/master:system/tools/aidl/build/aidl_interface_backends.go;l=564;drc=0517d97079d4b08f909e7f35edfa33b88fcc0d0e
            if deps != None:
                # For each aidl_library target label versioned_name, there's an
                # associated cc_library_shared target with label versioned_name-<cpp|ndk>
                dynamic_deps.extend(["{}-{}".format(dep, lang) for dep in deps])

            # https://cs.android.com/android/platform/superproject/+/master:system/tools/aidl/build/aidl_interface_backends.go;l=111;drc=ef9f1352a1a8fec7bb134b1c713e13fc3ccee651
            if lang == CPP:
                dynamic_deps.extend([
                    "//frameworks/native/libs/binder:libbinder",
                    "//system/core/libutils:libutils",
                ])
            elif lang == NDK:
                dynamic_deps = dynamic_deps + select({
                    "//build/bazel/rules/apex:android-in_apex": ["//frameworks/native/libs/binder/ndk:libbinder_ndk_stub_libs_current"],
                    "//conditions:default": ["//frameworks/native/libs/binder/ndk:libbinder_ndk"],
                })

            _cc_aidl_libraries(
                name = "{}-{}".format(aidl_library_name, lang),
                aidl_library = ":" + aidl_library_name,
                dynamic_deps = dynamic_deps,
                lang = lang,
                min_sdk_version = min_sdk_version,
                tags = tags + config.get("tags", []),
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
        min_sdk_version = "",
        tags = [],
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
        min_sdk_version = min_sdk_version,
        tags = tags,
        **kwargs
    )

    if hasattr(kwargs, "tidy_checks_as_errors"):
        fail("tidy_checks_as_errors cannot be overriden for aidl_interface cc_libraries")
    tidy_checks_as_errors = [
        "*",
        "-clang-analyzer-deadcode.DeadStores",  # b/253079031
        "-clang-analyzer-cplusplus.NewDeleteLeaks",  # b/253079031
        "-clang-analyzer-optin.performance.Padding",  # b/253079031
    ]

    shared_arguments_with_kwargs = dict(
        kwargs,
        srcs = [":" + aidl_code_gen],
        implementation_deps = implementation_deps,
        deps = [aidl_code_gen],
        dynamic_deps = dynamic_deps,
        min_sdk_version = min_sdk_version,
        tidy = True,
        tidy_checks_as_errors = tidy_checks_as_errors,
        tidy_gen_header_filter = True,
        tags = tags,
    )

    cc_library_shared(
        name = name,
        **shared_arguments_with_kwargs
    )
    cc_library_static(
        name = name + "_bp2build_cc_library_static",
        **shared_arguments_with_kwargs
    )
