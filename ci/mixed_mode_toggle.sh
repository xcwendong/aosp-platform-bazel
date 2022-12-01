#!/bin/bash -eux

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
#
# Verifies mixed builds does not run if neither --bazel-mode-dev nor --bazel-mode
# is set.
# This verification script is designed to be used for continuous integration
# tests, though may also be used for manual developer verification.

if [[ -z ${OUT_DIR+x} ]]; then
  OUT_DIR="out"
fi

if [[ -z ${DIST_DIR+x} ]]; then
  echo "DIST_DIR not set. Using ${OUT_DIR}/dist. This should only be used for manual developer testing."
  DIST_DIR="${OUT_DIR}/dist"
fi

# Generate the ninja file with default setting. We expect Bazel to be enabled by
# default.
build/soong/soong_ui.bash --make-mode \
  --mk-metrics \
  BAZEL_STARTUP_ARGS="--max_idle_secs=5" \
  BAZEL_BUILD_ARGS="--color=no --curses=no --show_progress_rate_limit=5" \
  TARGET_PRODUCT=aosp_arm64 \
  TARGET_BUILD_VARIANT=userdebug \
  nothing \
  dist DIST_DIR=$DIST_DIR

# Default setting should contain bazel-out, as *at least* tzdata is allowlisted for
# default prod mode.
if [[ $(grep -L "bazel-out" ${OUT_DIR}/soong/build.ninja) ]]; then
  echo "Expected default build to reference bazel-out"
  exit 1
fi

# Regenerate the ninja file with BUILD_BROKEN override. This should have mixed builds
# disabled.
build/soong/soong_ui.bash --make-mode \
  --mk-metrics \
  DISABLE_ARTIFACT_PATH_REQUIREMENTS=true \
  BUILD_BROKEN_DISABLE_BAZEL=true \
  BAZEL_STARTUP_ARGS="--max_idle_secs=5" \
  BAZEL_BUILD_ARGS="--color=no --curses=no --show_progress_rate_limit=5" \
  TARGET_PRODUCT=aosp_arm64 \
  TARGET_BUILD_VARIANT=userdebug \
  nothing \
  dist DIST_DIR=$DIST_DIR

if [[ ! $(grep -L "bazel-out" ${OUT_DIR}/soong/build.ninja) ]]; then
  echo "Expected BUILD_BROKEN override to not reference bazel-out"
  exit 1
fi

# Rerun default setting. This verifies that removing BUILD_BROKEN_DISABLE_BAZEL
# causes analysis to be rerun.
build/soong/soong_ui.bash --make-mode \
  --mk-metrics \
  BAZEL_STARTUP_ARGS="--max_idle_secs=5" \
  BAZEL_BUILD_ARGS="--color=no --curses=no --show_progress_rate_limit=5" \
  TARGET_PRODUCT=aosp_arm64 \
  TARGET_BUILD_VARIANT=userdebug \
  nothing \
  dist DIST_DIR=$DIST_DIR

if [[ $(grep -L "bazel-out" ${OUT_DIR}/soong/build.ninja) ]]; then
  echo "Expected default build rerun to reference bazel-out"
  exit 1
fi

# Regen ninja file with mixed builds dev mode.
build/soong/soong_ui.bash --make-mode \
  --mk-metrics \
  --bazel-mode-dev \
  BAZEL_STARTUP_ARGS="--max_idle_secs=5" \
  BAZEL_BUILD_ARGS="--color=no --curses=no --show_progress_rate_limit=5" \
  TARGET_PRODUCT=aosp_arm64 \
  TARGET_BUILD_VARIANT=userdebug \
  nothing \
  dist DIST_DIR=$DIST_DIR

if [[ $(grep -L "bazel-out" ${OUT_DIR}/soong/build.ninja) ]]; then
  echo "Expected dev mode build to reference bazel-out"
  exit 1
fi
