#!/usr/bin/python3

# This script rsyncs generated bp2build BUILD files from out/soong/bp2build to
# the top level AOSP source tree. It can also delete these files from the source
# tree.
#
# Write BUILD files in declared packages:  ./build/bazel/scripts/bp2build-sync.py write
# Remove BUILD files in declared packages: ./build/bazel/scripts/bp2build-sync.py remove

import argparse
import glob
import json
import os
import subprocess
import sys

AOSP_ROOT = os.path.abspath(os.path.dirname(__file__ +"/../../../../"))

def converted_directories():
    '''A static list of directories for conversion.'''
    # TODO(jingwen): replace with an allowlist.
    return [
        "bionic"
    ]


def write_build_files(directories):
    '''Recursively write all BUILD files under the converted directories to the source tree.'''
    for d in directories:
        cmd = [
            'rsync',
            '-av',
            '--include="*/"',
            '--include="BUILD"',
            '--exclude="*"',
            os.path.join("out/soong/bp2build", d),
            os.path.dirname(d)
        ]
        process = subprocess.call(cmd, cwd=AOSP_ROOT)

def remove_build_files(directories):
    '''Recursively remove all BUILD files under the converted directories.'''
    for d in directories:
        for f in glob.glob(os.path.join(AOSP_ROOT, d, "**", "BUILD")):
            os.remove(f)

def run(action):
    '''Primary entry point of this script.'''
    directories = converted_directories()
    if action == "write":
        write_build_files(directories)
    elif action =="remove":
        remove_build_files(directories)
    else:
        # shouldn't happen, based on argparse's choices.
        sys.exit(1)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "action",
        choices=["write", "remove"],
        help="write or remove generated BUILD files")
    args = parser.parse_args()
    run(args.action)
