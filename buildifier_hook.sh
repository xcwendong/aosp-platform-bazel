#!/bin/bash
[[ ! $(command -v buildifier) ]] || buildifier -mode=check `printf "%s\n" $@ | grep -E "^(BUILD|BUILD.bazel|bazel.WORKSPACE|.*\\.bzl)$"` < /dev/null
