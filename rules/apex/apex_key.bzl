# Copyright (C) 2021 The Android Open Source Project
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
load("@soong_injection//product_config:product_variables.bzl", "product_vars")
load("//build/bazel/rules/android:android_app_certificate.bzl", "default_cert_directory")

ApexKeyInfo = provider(
    "Info needed to sign APEX bundles",
    fields = {
        "private_key": "File containing the private key",
        "public_key": "File containing the public_key",
    },
)

def _apex_key_rule_impl(ctx):
    public_key = ctx.file.public_key
    private_key = ctx.file.private_key

    public_keyname = paths.split_extension(public_key.basename)[0]
    private_keyname = paths.split_extension(private_key.basename)[0]
    if public_keyname != private_keyname:
        fail("public_key %s (keyname:%s) and private_key %s (keyname:%s) do not have same keyname" % (
            ctx.attr.public_key.label,
            public_keyname,
            ctx.attr.private_key.label,
            private_keyname,
        ))

    return [
        ApexKeyInfo(public_key = ctx.file.public_key, private_key = ctx.file.private_key),
    ]

_apex_key = rule(
    implementation = _apex_key_rule_impl,
    attrs = {
        "private_key": attr.label(mandatory = True, allow_single_file = True),
        "public_key": attr.label(mandatory = True, allow_single_file = True),
    },
)

# Keep consistent with the ApexKeyDir product config lookup:
# https://cs.android.com/android/platform/superproject/+/master:build/soong/android/config.go;l=831-841;drc=652335ea7c2f8f281a1b93a1e1558960b6ad1b6f
def _get_key_label(label, name, default_cert):
    if label and name:
        fail("Cannot use both {public,private}_key_name and {public,private}_key attributes together. " +
             "Use only one of them.")

    if label:
        return label

    if not default_cert or paths.dirname(default_cert) == default_cert_directory:
        # Use the package_name of the macro callsite of this function.
        return "//" + native.package_name() + ":" + name

    return "//" + paths.dirname(default_cert) + ":" + name

def apex_key(
        name,
        public_key = None,
        private_key = None,
        public_key_name = None,
        private_key_name = None,

        # Product var dependency injection, for testing only.
        # DefaultAppCertificate is lifted into a parameter to make it testable in
        # analysis tests.
        _DefaultAppCertificate = product_vars.get("DefaultAppCertificate"),  # path/to/some/cert
        **kwargs):
    # Ensure that only tests can set _DefaultAppCertificate.
    if native.package_name() != "build/bazel/rules/apex" and \
       _DefaultAppCertificate != product_vars.get("DefaultAppCertificate"):
        fail("Only Bazel's own tests can set apex_key._DefaultAppCertificate.")

    # The keys are labels that point to either a file, or a target that provides
    # a single file (e.g. a filegroup or rule that provides the key itself only).
    _apex_key(
        name = name,
        public_key = _get_key_label(public_key, public_key_name, _DefaultAppCertificate),
        private_key = _get_key_label(private_key, private_key_name, _DefaultAppCertificate),
        **kwargs
    )
