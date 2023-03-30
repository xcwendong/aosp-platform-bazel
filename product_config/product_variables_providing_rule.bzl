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

ProductVariablesInfo = provider(
    "ProductVariablesInfo provides the android product config variables.",
    fields = {
        "CompressedApex": "Boolean indicating if apexes are compressed or not.",
        "Unbundled_apps": "List of apps to build as unbundled.",
    },
)

def _product_variables_providing_rule_impl(ctx):
    vars = json.decode(ctx.attr.product_vars)
    return [
        platform_common.TemplateVariableInfo(ctx.attr.attribute_vars),
        ProductVariablesInfo(
            CompressedApex = vars.get("CompressedApex", False),
            Unbundled_apps = vars.get("Unbundled_apps", []),
        ),
    ]

# Provides product variables for templated string replacement.
product_variables_providing_rule = rule(
    implementation = _product_variables_providing_rule_impl,
    attrs = {
        "attribute_vars": attr.string_dict(doc = "Variables that can be expanded using make-style syntax in attributes"),
        "product_vars": attr.string(doc = "Regular android product variables, a copy of the soong.variables file. Unfortunately this needs to be a json-encoded string because bazel attributes can only be simple types."),
    },
)
