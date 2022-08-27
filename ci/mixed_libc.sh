#!/bin/bash -eux
# Verifies mixed builds succeeds when building "libc".
# This verification script is designed to be used for continuous integration
# tests, though may also be used for manual developer verification.

if [[ -z ${DIST_DIR+x} ]]; then
  echo "DIST_DIR not set. Using out/dist. This should only be used for manual developer testing."
  DIST_DIR="out/dist"
fi

#TODO(b/241283350): once the bug is fixed and the TODO(b/241283350) in allowlist.go is cleaned, check the following targets are converted in bp2build.
TARGETS=(
  libbacktrace
  libfdtrack
  libsimpleperf
  com.android.adbd
  com.android.runtime
  bluetoothtbd
  framework-minus-apex
)

# Run a mixed build of "libc"
build/soong/soong_ui.bash --make-mode \
  --mk-metrics \
  BP2BUILD_VERBOSE=1 \
  USE_BAZEL_ANALYSIS=1 \
  BAZEL_STARTUP_ARGS="--max_idle_secs=5" \
  BAZEL_BUILD_ARGS="--color=no --curses=no --show_progress_rate_limit=5" \
  TARGET_PRODUCT=aosp_arm64 \
  TARGET_BUILD_VARIANT=userdebug \
  "${TARGETS[@]}" \
  dist DIST_DIR=$DIST_DIR

echo "Verifying libc.so..."
LIBC_OUTPUT_FILE="$(find out/ -regex '.*/bazel-out/android_arm64-fastbuild.*/bin/bionic/libc/libc.so' || echo '')"
LIBC_STUB_OUTPUT_FILE="$(find out/ -regex '.*/bazel-out/android_arm64-fastbuild.*/bin/bionic/libc/liblibc_stub_libs-current_so.so' || echo '')"

if [ -z "$LIBC_OUTPUT_FILE" -a -z "$LIBC_STUB_OUTPUT_FILE" ]; then
  echo "Could not find libc.so or its stub lib at expected path."
  exit 1
fi

if [ -L "$LIBC_OUTPUT_FILE" ]; then
  # It's problematic to have libc.so be a symlink, as it means that installed
  # libc.so in an Android system image will be a symlink to a location outside
  # of that system image.
  echo "$LIBC_OUTPUT_FILE is expected as a file not a symlink"
  exit 1
fi

echo "libc.so verified."
