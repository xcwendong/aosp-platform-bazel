#!/bin/bash
#
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
# Gather and print top-line performance metrics for the android build
#

readonly log_dir=$1
if [[ ! $log_dir ]] ; then
  echo usage: canonical_perf.sh LOG_DIR
  echo Must be run from root of tree.
  echo LOG_DIR directory should be outside of tree, including not in out/,
  echo because the whole tree will be cleaned during testing.
  exit 1
fi

# Pretty print the results
function pretty() {
    python3  "$(dirname "$0")/pretty.py" "$1"
}

function clean_tree() {
  m clean
  rm -rf out
}

rm -rf $log_dir
mkdir -p $log_dir

source build/envsetup.sh

# TODO: Switch to oriole when it works
if [[ -e vendor/google/build ]] ;
then
  export TARGET_PRODUCT=cf_x86_64_phone
else
  export TARGET_PRODUCT=aosp_cf_x86_64_phone
fi

export TARGET_BUILD_VARIANT=eng

function run()
{
  local -r bazel_mode="${1:-}"

  # Clear the cache by doing a build. There are probably better ways of clearing the
  # cache, but this does reduce the variance of the first full build.
  clean_tree
  date
  m

  # Droid Builds
  # ------------
  # 0 = Clean full build
  # 0 0 = No-op droid build
  # Touch root Android.bp
  # Adding an unreferenced file to the source tree and build
  clean_tree
  date
  # shellcheck disable=SC2086
  ./build/bazel/ci/incremental_build.py $bazel_mode --log-dir="$log_dir" --repo-diff-exit \
      -c 0 0 0 "bionic/unreferenced.txt" "root Android.bp" -- droid

  # Touch stdio.cpp
  date
  # shellcheck disable=SC2086
  ./build/bazel/ci/incremental_build.py $bazel_mode --log-dir="$log_dir" --repo-diff-exit \
      -c "stdio.cpp" -- libc

  # Touch adbd
  date
  # shellcheck disable=SC2086
  ./build/bazel/ci/incremental_build.py $bazel_mode --log-dir="$log_dir" --repo-diff-exit \
      -c "adbd main.cpp"  -- adbd

  # Touch View.java
  date
  # shellcheck disable=SC2086
  ./build/bazel/ci/incremental_build.py $bazel_mode --log-dir="$log_dir" --repo-diff-exit \
      -c "View.java" -- framework

  pretty "$log_dir/summary.csv"
}

run
run --bazel-mode
#run --bazel-mode-dev
