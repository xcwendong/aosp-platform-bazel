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

rm -rf "$log_dir"
mkdir -p "$log_dir"

source build/envsetup.sh

# TODO: Switch to oriole when it works
if [[ -e vendor/google/build ]] ;
then
  export TARGET_PRODUCT=cf_x86_64_phone
else
  export TARGET_PRODUCT=aosp_cf_x86_64_phone
fi

export TARGET_BUILD_VARIANT=eng

function build()
{
  date
  set -x
  ./build/bazel/scripts/incremental_build/incremental_build.py "$@"
  set +x
}

function run()
{
  local -r bazel_mode="${1:-}"

  # Clear the cache by doing a build. There are probably better ways of clearing the
  # cache, but this does reduce the variance of the first full build.
  clean_tree
  date
  file="$log_dir/output${bazel_mode:+"$bazel_mode"}.txt"
  echo "logging to $file"
  m nothing > "$file"

  # Droid Builds
  # ------------
  # 0 = Clean full build
  # 0 0 = No-op droid build
  # Touch root Android.bp
  # Adding an unreferenced file to the source tree and build
  clean_tree

  build --ignore-repo-diff --log-dir="$log_dir" ${bazel_mode:+"$bazel_mode"} \
    -c 0 0 0 " bionic/unreferenced.txt" " Android.bp" -- nothing

  build --ignore-repo-diff --log-dir="$log_dir" ${bazel_mode:+"$bazel_mode"} \
    -c stdio.cpp -- nothing

  build --ignore-repo-diff --log-dir="$log_dir" ${bazel_mode:+"$bazel_mode"} \
    -c 'adb/daemon/main.cpp$' -- nothing

  build --ignore-repo-diff --log-dir="$log_dir" ${bazel_mode:+"$bazel_mode"} \
    -c View.java -- nothing

  pretty "$log_dir/summary.csv"
}

run
run --bazel-mode
