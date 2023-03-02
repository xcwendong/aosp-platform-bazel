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
usage: $0 [-l LOG_DIR] [-t TARGETS] CUJS
  -l    LOG_DIR should be outside of tree, including not in out/,
        because the whole tree will be cleaned during testing.
  -t    TARGETS to run e.g. droid
  CUJS  to run, e.g. "modify Android.bp"
example:
 $0 -t nothing "no change"
 $0 -t droid -t libc "no change" "modify Android.bp"
EOF
  exit 1
}

declare -a targets
while getopts "l:t:" opt; do
  case "$opt" in
  l) log_dir=$OPTARG ;;
  t) targets+=("$OPTARG") ;;
  ?) usage ;;
  esac
done
shift $((OPTIND - 1))

readonly -a cujs=("$@")

log_dir=${log_dir:-"$TOP/../canonical-$(date +%b%d)"}
if [[ -e "$log_dir" ]]; then
  read -r -n 1 -p "$log_dir already exists, add more build results there? Y/N: " response
  echo ""
  if [[ ! "$response" =~ ^[yY]$ ]]; then
    usage
  fi
fi
mkdir -p "$log_dir"

# Pretty print the results
function pretty() {
  python3 "$(dirname "$0")/pretty.py" "$1"
}

function clean_tree() {
  rm -rf out
}

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
  if ! "$TOP/build/bazel/scripts/incremental_build/incremental_build.py" \
    --ignore-repo-diff \
    --log-dir="$log_dir" \
    --build-type soong_only mixed_prod \
    "$@"; then
    echo "See logs for errors"
    exit 1
  fi
  set +x
}

if [[ ${#cujs[@]} -ne "0" ]]; then
  echo "you might want to add \"clean\" as the first CUJ to mitigate caching issues"
else
  if [[ ${#targets[@]} -ne "0" ]]; then
    echo "you must specify cujs as well"
    usage
  fi
  # Clear the cache by doing a build. There are probably better ways of clearing the
  # cache, but this does reduce the variance of the first full build.
  file="$log_dir/output.txt"
  echo "logging to $file"
  clean_tree
  source "$TOP/build/envsetup.sh"
  m droid >"$file"
fi

clean_tree

if [[ ${#cujs[@]} -ne "0" ]]; then
  build -c "${cujs[@]}" -- "${targets[*]}"
else
  build -c 'clean' 'no change' 'create bionic/unreferenced.txt' 'modify Android.bp' -- droid
  build -c 'clean' 'modify bionic/.*/stdio.cpp' -- libc
  build -c 'clean' 'modify .*/adb/daemon/main.cpp' -- adbd
fi

pretty "$log_dir/summary.csv"
