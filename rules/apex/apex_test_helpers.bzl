# Copyright (C) 2022 The Android Open Source Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

load("//build/bazel/rules/android:android_app_certificate.bzl", "android_app_certificate")
load(":apex_key.bzl", "apex_key")
load(":apex.bzl", "ApexInfo", "apex")

# Set up test-local dependencies required for every apex.
def setup_apex_required_deps():
    file_contexts_name = "test_file_contexts"
    manifest_name = "test_manifest"
    key_name = "test_key"
    certificate_name = "test_certificate"

    # Use the same shared common deps for all test apexes.
    if not native.existing_rule(file_contexts_name):
        native.genrule(
            name = file_contexts_name,
            outs = [file_contexts_name + ".out"],
            cmd = "echo unused && exit 1",
            tags = ["manual"],
        )

    if not native.existing_rule(manifest_name):
        native.genrule(
            name = manifest_name,
            outs = [manifest_name + ".json"],
            cmd = "echo unused && exit 1",
            tags = ["manual"],
        )

    # Required for ApexKeyInfo provider
    if not native.existing_rule(key_name):
        apex_key(
            name = key_name,
            private_key = key_name + ".pem",
            public_key = key_name + ".avbpubkey",
            tags = ["manual"],
        )

    # Required for AndroidAppCertificate provider
    if not native.existing_rule(certificate_name):
        android_app_certificate(
            name = certificate_name,
            certificate = certificate_name + ".cert",
            tags = ["manual"],
        )

    return struct(
        file_contexts_name = file_contexts_name,
        manifest_name = manifest_name,
        key_name = key_name,
        certificate_name = certificate_name,
    )

def test_apex(
        name,
        file_contexts = None,
        key = None,
        manifest = None,
        certificate = None,
        **kwargs):
    names = setup_apex_required_deps()
    apex(
        name = name,
        file_contexts = file_contexts or names.file_contexts_name,
        key = key or names.key_name,
        manifest = manifest or names.manifest_name,
        certificate = certificate or names.certificate_name,
        tags = ["manual"],
        **kwargs
    )
