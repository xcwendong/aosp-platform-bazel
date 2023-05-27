#!/bin/bash -eu
readonly TOP="$(realpath "$(dirname "$0")/../../../..")"
"$TOP/build/soong/soong_ui.bash" \
  --build-mode \
  --all-modules \
  --dir="$(pwd)" \
  --skip-soong-tests \
  bp2build

# to debug use `--run_under /usr/lib/python3.10/pdb.py`
# or simply add `breakpoint()` in the code somewhere
ANDROID_BUILD_TOP=$TOP "$TOP/build/bazel/bin/bazel" \
  run --config=bp2build --verbose_failures \
  //build/bazel/scripts/incremental_build -- "$@"

# Alternatively, we could use python_zip_file, https://github.com/bazelbuild/bazel/pull/9453
