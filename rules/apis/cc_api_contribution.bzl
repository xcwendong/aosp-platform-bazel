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

"""Bazel rules for exporting API contributions of CC libraries"""

load("@bazel_skylib//lib:paths.bzl", "paths")
load("//build/bazel/rules/cc:cc_constants.bzl", "constants")

"""A Bazel provider that encapsulates the headers presented to an API surface"""
CcApiHeaderInfo = provider(
    fields = {
        "name": "Name identifying the header files",
        "root": "Directory containing the header files, relative to workspace root. This will become the -I parameter in consuming API domains. This defaults to the current Bazel package",
        "headers": "The header (.h) files presented by the library to an API surface",
        "system": "bool, This will determine whether the include path will be -I or -isystem",
        "arch": "Target arch of devices that use these header files to compile. The default is empty, which means that it is arch-agnostic",
    },
)

def _cc_api_header_impl(ctx):
    """Implementation for the cc_api_headers rule.
    This rule does not have any build actions, but returns a `CcApiHeaderInfo` provider object"""
    headers_filepath = [header.path for header in ctx.files.hdrs]
    root = paths.dirname(ctx.build_file_path)
    if ctx.attr.include_dir:
        root = paths.join(root, ctx.attr.include_dir)
    return [
        CcApiHeaderInfo(
            name = ctx.label.name,
            root = root,
            headers = headers_filepath,
            system = ctx.attr.system,
            arch = ctx.attr.arch,
        ),
    ]

"""A bazel rule that encapsulates the header contributions of a CC library to an API surface
This rule does not contain the API symbolfile (.map.txt). The API symbolfile is part of the cc_api_contribution rule
This layering is necessary since the symbols present in a single .map.txt file can be defined in different include directories
e.g.
├── Android.bp
├── BUILD
├── include <-- cc_api_headers
├── include_other <-- cc_api_headers
├── libfoo.map.txt
"""
cc_api_headers = rule(
    implementation = _cc_api_header_impl,
    attrs = {
        "include_dir": attr.string(
            mandatory = False,
            doc = "Directory containing the header files, relative to the Bazel package. This relative path will be joined with the Bazel package path to become the -I parameter in the consuming API domain",
        ),
        "hdrs": attr.label_list(
            mandatory = True,
            allow_files = constants.hdr_dot_exts,
            doc = "List of .h files presented to the API surface. Glob patterns are allowed",
        ),
        "system": attr.bool(
            default = False,
            doc = "Boolean to indicate whether these are system headers",
        ),
        "arch": attr.string(
            mandatory = False,
            values = ["arm", "arm64", "x86", "x86_64"],
            doc = "Arch of the target device. The default is empty, which means that the headers are arch-agnostic",
        ),
    },
)

"""A Bazel provider that encapsulates the contributions of a CC library to an API surface"""
CcApiContributionInfo = provider(
    fields = {
        "name": "Name of the cc library",
        "api": "Path of map.txt describing the stable APIs of the library. Path is relative to workspace root",
        "headers": "metadata of the header files of the cc library",
    },
)

def _cc_api_contribution_impl(ctx):
    """Implemenation for the cc_api_contribution rule
    This rule does not have any build actions, but returns a `CcApiContributionInfo` provider object"""
    api_filepath = ctx.file.api.path
    headers = [header[CcApiHeaderInfo] for header in ctx.attr.hdrs]
    name = ctx.attr.library_name or ctx.label.name
    return [
        CcApiContributionInfo(
            name = name,
            api = api_filepath,
            headers = headers,
        ),
    ]

cc_api_contribution = rule(
    implementation = _cc_api_contribution_impl,
    attrs = {
        "library_name": attr.string(
            mandatory = False,
            doc = "Name of the library. This can be different from `name` to prevent name collision with the implementation of the library in the same Bazel package. Defaults to label.name",
        ),
        "api": attr.label(
            mandatory = True,
            allow_single_file = [".map.txt"],
            doc = ".map.txt file of the library",
        ),
        "hdrs": attr.label_list(
            mandatory = False,
            providers = [CcApiHeaderInfo],
            doc = "Header contributions of the cc library. This should return a `CcApiHeaderInfo` provider",
        ),
    },
)
