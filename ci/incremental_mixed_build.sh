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


# The script defines a number of `cujs` and loops through them; in pseudo-code:
#
# for each cuj in cujs {
#   m droid dist
#   make cuj relevant changes
#   time m droid dist
#   revert cuj relevant changes
# }
#
# Note: this script assumes PWD is the root of source tree.

readonly mypath=$(realpath "$0")
# console output to be limited
declare quiet=
# CUJ related soong_builds to dry run ninja
declare dry_run=
# CUJ (0-based index in cujs array) to run
declare cuj_to_run=
declare -a cujs
declare -a targets=(droid dist)

# Finds the ordinal number of the last know run of this script
function run_n {
  if [[ ! -d "out" ]]; then
    echo '0'
  else
    local -r n=$(find out -maxdepth 1 -name 'run-*.log' | sed -E "s/.*-([0-9]+)-.*\.log$/\1/" | sort -n -r | head -n 1)
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
  local -r log_file=$1
  if [[ -n $quiet ]]; then
    # display time information on console
    tail -n 3 "$log_file"
  fi
  local -r explanations=$(count_explanations "$log_file")
  if [[ $explanations -eq 0 ]]; then
    echo "Build ${targets[*]} ($log_file) was a NULL build"
  else
    # Note: ninja explanations doesn't necessarily match the number of actions performed;
    # it will be AT LEAST the number of actions.
    # Number of actions can be deduced from `.ninja_log`. However, for debugging and
    # tweaking performance, ninja explanations are far more useful.
    echo "Build ${targets[*]} ($log_file) was a NON-NULL build, ninja explanations count = $explanations"
  fi
}

function build_once {
  local -r cuj=$1
  local -r log_file=$2
  mkdir -p out && touch "$log_file"
  echo "Build ${targets[*]} ($log_file)...............................................STARTED"
  local ninja_args
  if [[ -n $dry_run && $cuj != "reset" ]]; then
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
    "${targets[@]}") 2>&1 | tee --append "$log_file" | output
  local -r exitStatus="${PIPESTATUS[0]}"
  if [[ $exitStatus -ne 0 ]]; then
    echo "FAILED with exit code $exitStatus"
    exit "$exitStatus"
  fi
  summarize "$log_file"
  echo "Build ${targets[*]} ($log_file) .................................................DONE"
}

function cuj_noop {
    echo "do nothing"
}

function cuj_touchRootAndroidBp {
  local undo=${1:-}
  if [[ -z $undo ]]; then
    touch Android.bp
  else
    echo "do nothing"
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
  if [[ -n $undo ]]; then
    rm -rf some_directory
  else
    mkdir -p some_directory
    touch some_directory/Android.bp
  fi
}

# Note: cuj_xxx functions must precede this line to be discovered here
readarray -t cujs< <(declare -F | awk '$NF ~ /cuj_/ {print $NF}')

function usage {
  cat <<EOF >&2
Usage: $mypath [-c cuj_to_run] [-n] [-q] [TARGET1 [TARGET2 [ ...]]]
  -c: The index number for the CUJ to test. Choose one of:
EOF
for ((i = 0; i < ${#cujs[@]}; i++)); do
  echo "      $i: ${cujs[$i]}"
done
  cat <<EOF >&2
  -n: Dry ninja runs (except "resetting" runs that precede CUJs)
  -q: Quiet. Console output will be suppressed.
If you omit targets, "${targets[*]}" will be used.
Set USE_BAZEL_ANALYSIS=1 for mixed builds.
EOF
  exit 1
}

while getopts "c:nq" o; do
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
if [[ -n $cuj_to_run ]]; then
  if [[ ! $cuj_to_run =~ ^[0-9]+$ || $cuj_to_run -ge "${#cujs[@]}" ]]; then
    echo "No such CUJ \"$cuj_to_run\", choose between 0 and $((${#cujs[@]} - 1))"
    usage
  fi
  cujs=("${cujs[$cuj_to_run]}")
fi
declare -i this_run
this_run=$((1 + "$(run_n)"))
for ((i = 0; i < ${#cujs[@]}; i++)); do
  build_once "reset" "out/run-$this_run-reset.log"
  cuj=${cujs[i]}
  echo "perform $cuj"
  eval "$cuj"
  build_once "$cuj" "out/run-$this_run-$cuj.log"
  echo "undo $cuj"
  eval "$cuj undo"
done
