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
readonly TOP="$(realpath "$(dirname "$0")/../../../..")"

usage() {
    cat <<EOF
usage: canonical_perf.sh [-a] [LOG_DIR]
  -a:      analysis only, i.e. runs "m nothing" equivalent
  LOG_DIR: directory should be outside of tree, including not in out/,
           because the whole tree will be cleaned during testing.
EOF
    exit 1
}

while getopts "a" opt; do
    case "$opt" in
        a) analysis_only=1 ;;
        ?) usage ;;
    esac
done
shift $((OPTIND-1))

readonly log_dir=${1:-"$TOP/../canonical-$(date +%b%d)"}
if [[ -e "$log_dir" ]]; then
  echo "$log_dir already exists, please specify a different LOG_DIR"
  usage
fi

# Pretty print the results
function pretty() {
  python3 "$(dirname "$0")/pretty.py" "$1"
}

function clean_tree() {
  m clean
  rm -rf out
}

mkdir -p "$log_dir"

source "$TOP/build/envsetup.sh"

# TODO: Switch to oriole when it works
if [[ -e vendor/google/build ]]; then
  export TARGET_PRODUCT=cf_x86_64_phone
else
  export TARGET_PRODUCT=aosp_cf_x86_64_phone
fi

export TARGET_BUILD_VARIANT=eng

function build() {
  date
  set -x
  "$TOP/build/bazel/scripts/incremental_build/incremental_build.py" \
    --ignore-repo-diff \
    --log-dir="$log_dir" \
    "$@"
  set +x
}

function run() {
  local -r bazel_mode="${1:-}"
  clean_tree
  date
  file="$log_dir/output${bazel_mode:+"$bazel_mode"}.txt"
  echo "logging to $file"

  # Clear the cache by doing a build. There are probably better ways of clearing the
  # cache, but this does reduce the variance of the first full build.
  if [[ $analysis_only ]]; then
    m nothing >"$file"
  else
    m droid >"$file"
  fi

  clean_tree

  if [[ $analysis_only ]]; then
    build ${bazel_mode:+"$bazel_mode"} -c 0 'modify Android.bp' -- nothing
  else
  # Clean full build, then a no-change build
    build ${bazel_mode:+"$bazel_mode"} -c 0 0 -- droid

    build ${bazel_mode:+"$bazel_mode"} -c 'create bionic/unreferenced.txt' 'modify Android.bp' -- droid
    build ${bazel_mode:+"$bazel_mode"} -c 'modify bionic/.*/stdio.cpp' -- libc
    build ${bazel_mode:+"$bazel_mode"} -c 'modify .*/adb/daemon/main.cpp' -- adbd
    build ${bazel_mode:+"$bazel_mode"} -c 'modify frameworks/.*/View.java' -- framework
  fi

  pretty "$log_dir/summary.csv"
}

BUILD_BROKEN_DISABLE_BAZEL=1 run
run --bazel-mode
run --bazel-mode-staging
