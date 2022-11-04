#!/usr/bin/env python3
#
# Copyright (C) 2021 The Android Open Source Project
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

import json
import os
import shutil
import subprocess
import sys
import tempfile

def main(argv):
    '''Build a staging directory, and then call a custom command.

    The first argument to this script must be the path to a file containing a json
    dictionary mapping paths in the staging directory to paths to files that should
    be copied there. The rest of the arguments will be run as a separate command.
    At least one other argument must be "STAGING_DIR_PLACEHOLDER", which will be
    replaced with the path to the staging directory.

    Example:
    staging_dir_builder file_mapping.json path/to/apexer --various-apexer-flags STAGING_DIR_PLACEHOLDER path/to/out.apex.unsigned
    '''
    if len(argv) < 2:
        sys.exit('usage: staging_dir_builder MAPPING_FILE COMMAND...')
    if "STAGING_DIR_PLACEHOLDER" not in argv[1:]:
        sys.exit('At least one argument must be "STAGING_DIR_PLACEHOLDER"')

    try:
        with open(argv[0], 'r') as f:
            file_mapping = json.load(f)
    except OSError as e:
        sys.exit(str(e))
    except json.JSONDecodeError as e:
        sys.exit(argv[0] + ": JSON decode error: " + str(e))

    # Validate and clean the file_mapping. This consists of:
    #   - Making sure it's a dict[str, str]
    #   - Normalizing the paths in the staging dir and stripping leading /s
    #   - Making sure there are no duplicate paths in the staging dir
    #   - Making sure no paths use .. to break out of the staging dir
    cleaned_file_mapping = {}
    if not isinstance(file_mapping, dict):
        sys.exit(argv[0] + ": expected a JSON dict[str, str]")
    for path_in_staging_dir, path_in_bazel in file_mapping.items():
        if not isinstance(path_in_staging_dir, str) or not isinstance(path_in_bazel, str):
            sys.exit(argv[0] + ": expected a JSON dict[str, str]")
        path_in_staging_dir = os.path.normpath(path_in_staging_dir).lstrip('/')
        if path_in_staging_dir in cleaned_file_mapping:
            sys.exit("Staging dir path repeated twice: " + path_in_staging_dir)
        if path_in_staging_dir.startswith('../'):
            sys.exit("Path attempts to break out of staging dir: " + path_in_staging_dir)
        cleaned_file_mapping[path_in_staging_dir] = path_in_bazel
    file_mapping = cleaned_file_mapping

    argv = argv[1:]

    with tempfile.TemporaryDirectory() as staging_dir:
        for path_in_staging_dir, path_in_bazel in file_mapping.items():
            path_in_staging_dir = os.path.join(staging_dir, path_in_staging_dir)

            # Because Bazel execution root is a symlink forest, all the input files are symlinks, these
            # include the dependency files declared in the BUILD files as well as the files declared
            # and created in the bzl files. For sandbox runs the former are two or more level symlinks and
            # latter are one level symlinks. For non-sandbox runs, the former are one level symlinks
            # and the latter are actual files. Here are some examples:
            #
            # Two level symlinks:
            # system/timezone/output_data/version/tz_version ->
            # /usr/local/google/home/...out/bazel/output_user_root/b1ed7e1e9af3ebbd1403e9cf794e4884/
            # execroot/__main__/system/timezone/output_data/version/tz_version ->
            # /usr/local/google/home/.../system/timezone/output_data/version/tz_version
            #
            # Three level symlinks:
            # bazel-out/android_x86_64-fastbuild-ST-4ecd5e98bfdd/bin/external/boringssl/libcrypto.so ->
            # /usr/local/google/home/yudiliu/android/aosp/master/out/bazel/output_user_root/b1ed7e1e9af3ebbd1403e9cf794e4884/
            # execroot/__main__/bazel-out/android_x86_64-fastbuild-ST-4ecd5e98bfdd/bin/external/boringssl/libcrypto.so ->
            # /usr/local/google/home/yudiliu/android/aosp/master/out/bazel/output_user_root/b1ed7e1e9af3ebbd1403e9cf794e4884/
            # execroot/__main__/bazel-out/android_x86_64-fastbuild-ST-4ecd5e98bfdd/bin/external/boringssl/
            # liblibcrypto_stripped.so ->
            # /usr/local/google/home/yudiliu/android/aosp/master/out/bazel/output_user_root/b1ed7e1e9af3ebbd1403e9cf794e4884/
            # execroot/__main__/bazel-out/android_x86_64-fastbuild-ST-4ecd5e98bfdd/bin/external/boringssl/
            # liblibcrypto_unstripped.so
            #
            # One level symlinks:
            # bazel-out/android_target-fastbuild/bin/system/timezone/apex/apex_manifest.pb ->
            # /usr/local/google/home/.../out/bazel/output_user_root/b1ed7e1e9af3ebbd1403e9cf794e4884/
            # execroot/__main__/bazel-out/android_target-fastbuild/bin/system/timezone/apex/
            # apex_manifest.pb
            if os.path.islink(path_in_bazel):
                path_in_bazel = os.readlink(path_in_bazel)

                # For sandbox run these are the 2nd level symlinks and we need to resolve
                while os.path.islink(path_in_bazel) and 'execroot/__main__' in path_in_bazel:
                    path_in_bazel = os.readlink(path_in_bazel)

            os.makedirs(os.path.dirname(path_in_staging_dir), exist_ok=True)
            shutil.copyfile(path_in_bazel, path_in_staging_dir, follow_symlinks=False)

        for i in range(len(argv)):
            if argv[i] == 'STAGING_DIR_PLACEHOLDER':
                argv[i] = staging_dir

        result = subprocess.run(argv)

    sys.exit(result.returncode)

if __name__ == '__main__':
    main(sys.argv[1:])
