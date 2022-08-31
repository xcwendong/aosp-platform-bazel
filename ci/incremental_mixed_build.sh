#!/bin/bash -eu

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
#
# Times various build CUJs, e.g.
#   - when a build is rerun without any changes, a quick null build should ensue.
#   - when an Android.bp file is updated, it should be re-anaylized.
#
# The script defines a number of `cujs` and loops through them, in pseudocode:
# for each cuj in cujs {
#   m droid dist
#   make cuj relevant changes
#   time m droid dist
#   revert cuj relevant changes
# }
#
# This verification script is designed to be used for continuous integration
# tests, though may also be used for manual developer verification.
# Note this script assumes PWD is the root of source tree.

readonly mypath=$(realpath "$0")
# console output to be limited
declare quiet=
# CUJ related soong_builds to dry run ninja
declare dry_run=
# CUJ (0-based index in cujs array) to run
declare cuj_to_run=
declare -a cujs=(cuj_noop cuj_touchRootAndroidBp cuj_newAndroidBp cuj_newUnreferencedFile)
declare -a targets=(droid dist)

# Finds the ordinal number of the last know run of this script
function loop_n {
  if [[ ! -d 'out' ]]; then
    echo '0'
  else
    local -r n=$(find out -maxdepth 1 -name 'loop-*.log' | sed -E "s/.*-([0-9]+)-.*\.log$/\1/" | sort -n -r | head -n 1)
    if [[ -z $n ]]; then
      echo '1' # just to signify that the next build is not a clean build
    else
      echo "$n"
    fi
  fi
}

function show_spinner {
  local -r chars="-/|\\"
  local i=0
  while read -r; do
    printf "\b%s" "${chars:i++%${#chars}:1}"
  done
  printf "\bDONE\n"
}

function output {
  if [[ -n $quiet ]]; then
    show_spinner
  else
    cat
  fi
}

function count_explanations {
  grep '^ninja explain:' "$1" | grep -c -v "^ninja explain: edge with output .\+ is a phony output, so is always dirty$"
}

function summarize {
  local -r run=$1
  local -r log_file=$2
  if [[ -n $quiet ]]; then
    # display time information on console
    tail -n 3 "$log_file"
  fi
  local -r explanations=$(count_explanations "$log_file")
  if [[ $explanations -eq 0 ]]; then
    echo "Build #$run ($log_file) was a NULL build"
  else
    echo "Build #$run ($log_file) was a NON-NULL build, ninja explanations count = $explanations"
  fi
}

function build_once {
  local -r run=$1
  local -r cuj=$2
  local -r log_file=$3
  # note the last run is a ninja dry run: this is to facilitate rerun to debug
  mkdir -p out && touch "$log_file"
  echo "Build #$run ($log_file)...............................................STARTED"
  local ninja_args
  if [[ -n $dry_run && $cuj != "noop" ]]; then
    echo "DRY RUN"
    ninja_args='-d explain -n'
  else
    ninja_args='-d explain'
  fi
  (time build/soong/soong_ui.bash \
    --make-mode \
    --mk-metrics \
    --skip-soong-tests \
    NINJA_ARGS="$ninja_args" \
    TARGET_BUILD_VARIANT=userdebug \
    TARGET_PRODUCT=aosp_coral \
    "${targets[@]}" \
    DIST_DIR="$DIST_DIR") 2>&1 | tee --append "$log_file" | output
  local -r exitStatus="${PIPESTATUS[0]}"
  if [[ $exitStatus -ne 0 ]]; then
    echo "FAILED with exit code $exitStatus"
    exit "$exitStatus"
  fi
  summarize "$run" "$log_file"
  echo "Build #$run ($log_file) .................................................DONE"
}

function usage {
  cat <<EOF >&2
Usage: $mypath [-c cuj_to_run] [-n] [-q] [TARGET1 [TARGET2 [ ...]]]
  -c: The specific CUJ to test. Choose one of:
      ${cujs[*]}
  -n: Dry Runs (a "resetting" run preceding a cuj will NOT be a dry run)
  -q: Quiet. Console output will be suppressed.
If you omit targets, "${targets[*]}" will be used.
Set USE_BAZEL_ANALYSIS=1 for mixed builds.
EOF
  exit 1
}

while getopts "c:n:q" o; do
  case "${o}" in
  c) cuj_to_run=${OPTARG} ;;
  n) dry_run=true ;;
  q) quiet=true ;;
  *) usage ;;
  esac
done
shift $((OPTIND - 1))
if [[ $# -gt 0 ]]; then
  IFS=" " read -r -a targets <<<"$@"
fi

if [[ -z ${DIST_DIR+x} ]]; then
  echo "DIST_DIR not set. Using out/dist. This should only be used for manual developer testing."
  DIST_DIR="out/dist"
fi

function cuj_noop {
  : #do nothing
}

function cuj_touchRootAndroidBp {
  local undo=${1:-}
  if [[ -z $undo ]]; then
    touch Android.bp
  fi
}

function cuj_newUnreferencedFile {
  local undo=${1:-}
  mkdir -p unreferenced_directory
  if [[ -n $undo ]]; then
    rm -rf unreferenced_directory
  else
    cat <<EOF >unreferenced_directory/test.c
#include <stdio.h>
int main(){
  printf("Hello World");
  return 0
}
EOF
  fi
}

function cuj_newAndroidBp {
  local undo=${1:-}
  mkdir -p some_directory
  if [[ -n $undo ]]; then
    rm -rf some_directory
  else
    touch some_directory/Android.bp
  fi
}

declare -i this_loop
this_loop=$((1 + "$(loop_n)"))
if [[ -n $cuj_to_run ]]; then
  cujs=("$cuj_to_run")
fi
for ((i = 0; i < ${#cujs[@]}; i++)); do
  cuj=${cujs[i]}
  echo "CUJ step $cuj"
  eval "$cuj"
  build_once 0 "noop" "out/loop-reset.log"
  build_once "$this_loop" "$cuj" "out/loop-$this_loop-$cuj.log"
  eval "$cuj undo"
done
