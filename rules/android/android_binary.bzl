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

load("@rules_android//rules:common.bzl", "common")
load("@rules_android//rules:migration_tag_DONOTUSE.bzl", "add_migration_tag")
load(
    "//build/bazel/rules/android/android_binary_aosp_internal:rule.bzl",
    "android_binary_aosp_internal_macro",
)
load("android_app_certificate.bzl", "android_app_certificate_with_default_cert")
load("android_app_keystore.bzl", "android_app_keystore")

def _android_binary_helper(**attrs):
    """Bazel android_binary rule.

        https://docs.bazel.build/versions/master/be/android.html#android_binary

        Args:
          **attrs: Rule attributes
    """
    android_binary_aosp_internal_name = ":" + attrs["name"] + common.PACKAGED_RESOURCES_SUFFIX
    android_binary_aosp_internal_macro(
        **dict(
            attrs,
            name = android_binary_aosp_internal_name[1:],
            visibility = ["//visibility:private"],
        )
    )

    attrs.pop("$enable_manifest_merging", None)

    native.android_binary(
        application_resources = android_binary_aosp_internal_name,
        **add_migration_tag(attrs)
    )

def android_binary(
        name,
        certificate = None,
        certificate_name = None,
        **kwargs):
    """Bazel macro to find and create a keystore to use for debug_signing_keys
       with @rules_android android_binary.

    This module emulates the Soong behavior which allows a developer to specify
    a specific module name for the android_app_certificate or the name of a
    .pem/.pk8 certificate/key pair in a directory specified by the
    DefaultAppCertificate product variable. In either case, we convert the specified
    .pem/.pk8 certificate/key pair to a JKS .keystore file before passing it to the
    android_binary rule.

    Arguments:
        certificate: Bazel target
        certificate_name: string, name of private key file in default certificate directory
        **kwargs: map, additional args to pass to android_binary
    """

    if certificate and certificate_name:
        fail("Cannot use both certificate_name and certificate attributes together. Use only one of them.")

    debug_signing_keys = kwargs.pop("debug_signing_keys", [])

    if certificate or certificate_name:
        if certificate_name:
            app_cert_name = name + "_app_certificate"
            android_app_certificate_with_default_cert(app_cert_name, certificate_name)
            certificate = ":" + app_cert_name

        app_keystore_name = name + "_keystore"
        android_app_keystore(
            name = app_keystore_name,
            certificate = certificate,
        )

        debug_signing_keys.append(app_keystore_name)

    _android_binary_helper(
        name = name,
        debug_signing_keys = debug_signing_keys,
        **kwargs
    )
