#!/bin/bash -eu
#
# Copyright (C) 2023 The Android Open Source Project
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

#
# Gather and print top-line performance metrics for the android build
#
readonly TOP="$(realpath "$(dirname "$0")/../../../..")"

"$TOP/build/soong/soong_ui.bash" \
  --build-mode \
  --all-modules \
  --dir="$(pwd)" \
  --skip-soong-tests \
  bp2build

ANDROID_BUILD_TOP=$TOP "$TOP/build/bazel/bin/bazel" \
  run --config=bp2build --verbose_failures \
  //build/bazel/scripts/incremental_build:pretty -- "$@"
