# Copyright (C) 2023 The Android Open Source Project
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
load("@bazel_skylib//lib:paths.bzl", "paths")

ProductVariablesInfo = provider(
    "ProductVariablesInfo provides the android product config variables.",
    fields = {
        "CompressedApex": "Boolean indicating if apexes are compressed or not.",
        "DefaultAppCertificate": "The default certificate to sign APKs and APEXes with. The $(dirname) of this certificate will also be used to find additional certificates when modules only give their names.",
        "TidyChecks": "List of clang tidy checks to enable.",
        "Unbundled_apps": "List of apps to build as unbundled.",
    },
)

ProductVariablesDepsInfo = provider(
    "ProductVariablesDepsInfo provides fields that are not regular product config variables, but rather the concrete files that other product config vars reference.",
    fields = {
        "DefaultAppCertificateFiles": "All the .pk8 and .pem files in the DefaultAppCertificate directory.",
    },
)

def _product_variables_providing_rule_impl(ctx):
    vars = json.decode(ctx.attr.product_vars)

    tidy_checks = vars.get("TidyChecks", "")
    tidy_checks = tidy_checks.split(",") if tidy_checks else []

    return [
        platform_common.TemplateVariableInfo(ctx.attr.attribute_vars),
        ProductVariablesInfo(
            CompressedApex = vars.get("CompressedApex", False),
            DefaultAppCertificate = vars.get("DefaultAppCertificate", None),
            TidyChecks = tidy_checks,
            Unbundled_apps = vars.get("Unbundled_apps", []),
        ),
        ProductVariablesDepsInfo(
            DefaultAppCertificateFiles = ctx.files.default_app_certificate_filegroup,
        ),
    ]

# Provides product variables for templated string replacement.
_product_variables_providing_rule = rule(
    implementation = _product_variables_providing_rule_impl,
    attrs = {
        "attribute_vars": attr.string_dict(doc = "Variables that can be expanded using make-style syntax in attributes"),
        "product_vars": attr.string(doc = "Regular android product variables, a copy of the soong.variables file. Unfortunately this needs to be a json-encoded string because bazel attributes can only be simple types."),
        "default_app_certificate_filegroup": attr.label(doc = "The filegroup that contains all the .pem and .pk8 files in $(dirname product_vars.DefaultAppCertificate)"),
    },
)

def product_variables_providing_rule(
        name,
        attribute_vars,
        product_vars):
    default_app_certificate_filegroup = None
    default_app_certificate = product_vars.get("DefaultAppCertificate", None)
    if default_app_certificate:
        default_app_certificate_filegroup = "@//" + paths.dirname(default_app_certificate) + ":android_certificate_directory"
    _product_variables_providing_rule(
        name = name,
        attribute_vars = attribute_vars,
        product_vars = json.encode(product_vars),
        default_app_certificate_filegroup = default_app_certificate_filegroup,
    )
