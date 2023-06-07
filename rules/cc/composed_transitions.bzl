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
load(":cc_constants.bzl", "transition_constants")
load(":cfi_transitions.bzl", "apply_cfi_deps", "apply_drop_cfi")
load(
    ":fdo_profile_transitions.bzl",
    "CLI_CODECOV_KEY",
    "CLI_FDO_KEY",
    "FDO_PROFILE_ATTR_KEY",
    "apply_drop_fdo_profile",
    "apply_fdo_profile",
)
load(":lto_transitions.bzl", "apply_drop_lto", "apply_lto_deps")

# LTO, sanitizers, and FDO require an incoming transition on cc_library_shared
# FDO is applied, while LTO and sanitizers are dropped.
def _lto_and_fdo_profile_incoming_transition_impl(settings, attr):
    new_fdo_settings = apply_fdo_profile(
        settings[CLI_CODECOV_KEY],
        getattr(attr, FDO_PROFILE_ATTR_KEY),
    )

    new_cli_features = apply_drop_lto(
        settings[transition_constants.cli_features_key],
    )
    new_cli_features = apply_drop_cfi(new_cli_features)
    new_cli_setting = {
        transition_constants.cli_features_key: new_cli_features,
    }

    return new_fdo_settings | new_cli_setting

lto_and_fdo_profile_incoming_transition = transition(
    implementation = _lto_and_fdo_profile_incoming_transition_impl,
    inputs = [
        CLI_CODECOV_KEY,
        transition_constants.cli_features_key,
    ],
    outputs = [
        CLI_FDO_KEY,
        transition_constants.cli_features_key,
    ],
)

# This transition applies LTO and sanitizer propagation down static dependencies
def _lto_and_sanitizer_deps_transition_impl(settings, attr):
    features = getattr(attr, transition_constants.features_attr_key)
    old_cli_features = settings[transition_constants.cli_features_key]
    new_cli_features = apply_lto_deps(features, old_cli_features)
    new_cli_features = apply_cfi_deps(
        features,
        new_cli_features,
        attr.package_name,
        settings[transition_constants.cfi_include_paths_key],
        settings[transition_constants.cfi_exclude_paths_key],
        settings[transition_constants.enable_cfi_key],
        settings[transition_constants.cli_platforms_key],
    )

    return {
        transition_constants.cli_features_key: new_cli_features,
    }

lto_and_sanitizer_deps_transition = transition(
    implementation = _lto_and_sanitizer_deps_transition_impl,
    inputs = [
        transition_constants.cli_features_key,
        transition_constants.cfi_include_paths_key,
        transition_constants.cfi_exclude_paths_key,
        transition_constants.enable_cfi_key,
        transition_constants.cli_platforms_key,
    ],
    outputs = [
        transition_constants.cli_features_key,
    ],
)

def _apply_drop_lto_and_sanitizers(old_cli_features):
    new_cli_features = apply_drop_lto(old_cli_features)
    new_cli_features = apply_drop_cfi(new_cli_features)
    return {
        transition_constants.cli_features_key: new_cli_features,
    }

# This transition drops LTO and sanitizer enablement from cc_binary
def _drop_lto_and_sanitizer_transition_impl(settings, _):
    return _apply_drop_lto_and_sanitizers(
        settings[transition_constants.cli_features_key],
    )

drop_lto_and_sanitizer_transition = transition(
    implementation = _drop_lto_and_sanitizer_transition_impl,
    inputs = [transition_constants.cli_features_key],
    outputs = [transition_constants.cli_features_key],
)

# Drop lto, sanitizer, and fdo transitions in order to avoid duplicate
# dependency error.
# Currently used for cc stub libraries.
def _drop_lto_sanitizer_and_fdo_profile_transition_impl(settings, _):
    new_cli_features = _apply_drop_lto_and_sanitizers(
        settings[transition_constants.cli_features_key],
    )

    new_fdo_setting = apply_drop_fdo_profile()

    return new_cli_features | new_fdo_setting

drop_lto_sanitizer_and_fdo_profile_incoming_transition = transition(
    implementation = _drop_lto_sanitizer_and_fdo_profile_transition_impl,
    inputs = [
        transition_constants.cli_features_key,
        CLI_FDO_KEY,
    ],
    outputs = [
        transition_constants.cli_features_key,
        CLI_FDO_KEY,
    ],
)

def _drop_sanitizer_transition_impl(settings, _):
    return {
        transition_constants.cli_features_key: apply_drop_cfi(
            settings[transition_constants.cli_features_key],
        ),
    }

drop_sanitizer_transition = transition(
    implementation = _drop_sanitizer_transition_impl,
    inputs = [transition_constants.cli_features_key],
    outputs = [transition_constants.cli_features_key],
)
