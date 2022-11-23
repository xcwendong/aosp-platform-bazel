#!/bin/bash -e
# Copyright (C) 2022 The Android Open Source Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Script used as --workspace_status_command.
# Must execute at the root of workspace.
# https://docs.bazel.build/versions/main/command-line-reference.html#flag--workspace_status_command

if [[ ! -f "WORKSPACE" ]]; then
    echo "ERROR: gen_build_number.sh must be executed at the root of Bazel workspace." >&2
    exit 1
fi

# TODO(b/260003429) Refactor to deduplicate this function from other scripts
# build/soong/scripts/microfactory.bash, build/soong/soong_ui.bash,
# build/make/envsetup.sh, build/bazel/bin/bazel
function gettop
{
    local TOPFILE=build/bazel/bin/bazel
    if [ -n "$TOP" -a -f "$TOP/$TOPFILE" ] ; then
        # The following circumlocution ensures we remove symlinks from TOP.
        (cd "$TOP"; PWD= /bin/pwd)
    else
        if [ -f $TOPFILE ] ; then
            # The following circumlocution (repeated below as well) ensures
            # that we record the true directory name and not one that is
            # faked up with symlink names.
            PWD= /bin/pwd
        else
            local HERE=$PWD
            local T=
            while [ \( ! \( -f $TOPFILE \) \) -a \( "$PWD" != "/" \) ]; do
                \cd ..
                T=`PWD= /bin/pwd -P`
            done
            \cd "$HERE"
            if [ -f "$T/$TOPFILE" ]; then
                echo "$T"
            fi
        fi
    fi
}

TOP="$(gettop)"

# TODO(b/260003429) Refactor to deduplicate this function from other scripts
# build/soong/scripts/microfactory.bash, build/soong/soong_ui.bash,
# build/make/envsetup.sh, build/bazel/bin/bazel
function getoutdir
{
    local out_dir="${OUT_DIR-}"
    if [ -z "${out_dir}" ]; then
        if [ "${OUT_DIR_COMMON_BASE-}" ]; then
            out_dir="${OUT_DIR_COMMON_BASE}/$(basename ${TOP})"
        else
            out_dir="out"
        fi
    fi
    if [[ "${out_dir}" != /* ]]; then
        out_dir="${TOP}/${out_dir}"
    fi
    echo "${out_dir}"
}

# TODO(b/228463719): figure out how to get the path properly.
BUILD_NUMBER_FILE=$(getoutdir)/soong/build_number.txt
if [[ -f ${BUILD_NUMBER_FILE} ]]; then
    BUILD_NUMBER=$(cat ${BUILD_NUMBER_FILE})
else
    BUILD_NUMBER=eng.${USER:0:6}.$(date '+%Y%m%d.%H%M%S')
fi

echo "BUILD_NUMBER ${BUILD_NUMBER}"