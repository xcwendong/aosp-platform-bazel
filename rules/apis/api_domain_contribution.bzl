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

"""Bazel rules for generating the metadata of API domain contributions to an API surface"""

load(":cc_api_contribution.bzl", "CcApiContributionInfo")

def _api_domain_contribution_impl(ctx):
    """Implementation of the api_domain_contribution rule
    This rule outputs a .json file. The contents include the cc/java/... libraries contributed by the API domain to an API surface"""
    cc_api_contribution_infos = [cc_library[CcApiContributionInfo] for cc_library in ctx.attr.cc_libraries]

    # TODO(spandandas): Add other contributions (e.g. java_api_contribution, etc.)
    api_domain_contribution = struct(
        name = ctx.attr.surface_name,
        version = ctx.attr.version,
        api_domain = ctx.attr.api_domain,
        cc_libraries = cc_api_contribution_infos,
    )

    contrib_metadata_filestem = "-".join([
        ctx.attr.surface_name,
        str(ctx.attr.version),
        ctx.attr.api_domain,
    ])
    out = ctx.actions.declare_file(contrib_metadata_filestem + ".json")
    ctx.actions.write(out, json.encode(api_domain_contribution))
    return [DefaultInfo(files = depset([out]))]

api_domain_contribution = rule(
    implementation = _api_domain_contribution_impl,
    attrs = {
        "surface_name": attr.string(mandatory = True, doc = "Name of the API surface"),
        "version": attr.int(mandatory = True, doc = "Version of the API surface."),
        "api_domain": attr.string(mandatory = True, doc = "Name of the contributing API domain. The (surface_name,version,api_domain) triple should be unique in a Bazel workspace"),
        "cc_libraries": attr.label_list(providers = [CcApiContributionInfo]),
    },
)
