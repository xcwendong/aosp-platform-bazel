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

AndroidAppCertificateInfo = provider(
    "Info needed for Android app certificates",
    fields = {
        "pem": "Certificate .pem file",
        "pk8": "Certificate .pk8 file",
        "key_name": "Key name",
    },
)

def _android_app_certificate_rule_impl(ctx):
    return [
        AndroidAppCertificateInfo(pem = ctx.file.pem, pk8 = ctx.file.pk8, key_name = ctx.attr.certificate),
    ]

_android_app_certificate = rule(
    implementation = _android_app_certificate_rule_impl,
    attrs = {
        "pem": attr.label(mandatory = True, allow_single_file = [".pem"]),
        "pk8": attr.label(mandatory = True, allow_single_file = [".pk8"]),
        "certificate": attr.string(mandatory = True),
    },
)

def android_app_certificate(
        name,
        certificate,
        **kwargs):
    "Bazel macro to correspond with the Android app certificate Soong module."

    _android_app_certificate(
        name = name,
        pem = certificate + ".x509.pem",
        pk8 = certificate + ".pk8",
        certificate = certificate,
        **kwargs
    )

default_cert_directory = "build/make/target/product/security"
_default_cert_package = "//" + default_cert_directory

# Set up the android_app_certificate dependency pointing to the .pk8 and
# .x509.pem files in the source tree.
#
# Every caller who use this function will have their own android_app_certificate
# target, even if the underlying certs are shared by many.
#
# If cert_name is used, then it will be looked up from the app certificate
# package as determined by the DefaultAppCertificate variable, or the hardcoded
# directory.
#
# Otherwise, if the DefaultAppCertificate variable is used, then an
# android_app_certificate target will be created to point to the path value, and
# the .pk8 and .x509.pem suffixes are added automatically.
#
# Finally (cert_name not used AND DefaultAppCertificate not specified), use the
# testkey.
def android_app_certificate_with_default_cert(name, cert_name = None):
    default_cert = product_vars.get("DefaultAppCertificate")

    if cert_name and default_cert:
        certificate = "".join(["//", paths.dirname(default_cert), ":", cert_name])
    elif cert_name:
        # if a specific certificate name is given, check the default directory
        # for that certificate.
        certificate = _default_cert_package + ":" + cert_name
    elif default_cert:
        # This assumes that there is a BUILD file marking the directory of
        # the default cert as a package.
        certificate = "".join([
            "//",
            paths.dirname(default_cert),
            ":",
            paths.basename(default_cert),
        ])
    else:
        certificate = _default_cert_package + ":testkey"

    android_app_certificate(
        name = name,
        certificate = certificate,
    )
