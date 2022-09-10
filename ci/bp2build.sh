#!/bin/bash -eux
# Verifies that bp2build-generated BUILD files result in successful Bazel
# builds.
#
# This verification script is designed to be used for continuous integration
# tests, though may also be used for manual developer verification.

#######
# Setup
#######

if [[ -z ${DIST_DIR+x} ]]; then
  echo "DIST_DIR not set. Using out/dist. This should only be used for manual developer testing."
  DIST_DIR="out/dist"
fi

# Generate BUILD files into out/soong/bp2build
AOSP_ROOT="$(dirname $0)/../../.."

# Before you add flags to this list, cosnider adding it to the "ci" bazelrc
# config instead of this list so that flags are not duplicated between scripts
# and bazelrc, and bazelrc is the Bazel-native way of organizing flags.
FLAGS_LIST=(
  --config=bp2build
  --config=ci
)
FLAGS="${FLAGS_LIST[@]}"

###############
# Build and test targets for device target platform.
###############
BUILD_TARGETS_LIST=(
  //art/...
  //bionic/...
  //bootable/recovery/tools/recovery_l10n/...
  //build/...
  //cts/...
  //development/...
  //external/...
  //frameworks/...
  //libnativehelper/...
  //packages/...
  //prebuilts/clang/host/linux-x86:all
  //prebuilts/build-tools/tests/...
  //platform_testing/...
  //system/...
  //tools/apksig/...
  //tools/platform-compat/...

  # These tools only build for host currently
  -//external/e2fsprogs/misc:all
  -//external/e2fsprogs/resize:all
  -//external/e2fsprogs/debugfs:all
  -//external/e2fsprogs/e2fsck:all
)
BUILD_TARGETS="${BUILD_TARGETS_LIST[@]}"

TEST_TARGETS_LIST=(
  //build/bazel/...
)
TEST_TARGETS="${TEST_TARGETS_LIST[@]}"

###########
# Iterate over various architectures supported in the platform build.
###########

product_prefix="aosp_"
for arch in arm arm64 x86 x86_64; do
  product=${product_prefix}${arch}
  # Re-run product config and bp2build for every TARGET_PRODUCT.
  "${AOSP_ROOT}/build/soong/soong_ui.bash" --make-mode BP2BUILD_VERBOSE=1 TARGET_PRODUCT=${product} --skip-soong-tests bp2build dist
  # Remove the ninja_build output marker file to communicate to buildbot that this is not a regular Ninja build, and its
  # output should not be parsed as such.
  rm -f out/ninja_build


  # Dist the entire workspace of generated BUILD files, rooted from
  # out/soong/bp2build. This is done early so it's available even if
  # builds/tests fail. Currently the generated BUILD files can be different
  # between products due to Soong plugins and non-deterministic codegeneration.
  tar --mtime='1970-01-01' -czf "${DIST_DIR}/bp2build_generated_workspace_${product}.tar.gz" -C out/soong/bp2build .

  # Use a loop to prevent unnecessarily switching --platforms because that drops
  # the Bazel analysis cache.
  #
  # 1. Build every target in $BUILD_TARGETS
  tools/bazel --max_idle_secs=5 build ${FLAGS} --config=android -k -- ${BUILD_TARGETS}
  # 2. Test every target that is compatible with an android target platform (e.g. analysis_tests, sh_tests, diff_tests).
  tools/bazel --max_idle_secs=5 test ${FLAGS} --build_tests_only --config=android -k -- ${TEST_TARGETS}
  # 3. Dist mainline modules.
  tools/bazel --max_idle_secs=5 run //build/bazel/ci/dist:mainline_modules ${FLAGS} --config=android -- --dist_dir="${DIST_DIR}/mainline_modules_${arch}"
done

#########
# Host-only builds and tests
#########

HOST_INCOMPATIBLE_TARGETS=(
  # TODO(b/216626461): add support for host_ldlibs
  -//packages/modules/adb:all
  -//packages/modules/adb/pairing_connection:all
)

# We can safely build and test all targets on the host linux config, and rely on
# incompatible target skipping for tests that cannot run on the host.
tools/bazel --max_idle_secs=5 test ${FLAGS} --build_tests_only=false -k \
  -- ${BUILD_TARGETS} ${TEST_TARGETS} "${HOST_INCOMPATIBLE_TARGETS[@]}"

###################
# bp2build-progress
###################

# Generate bp2build progress reports and graphs for these modules into the dist
# dir so that they can be downloaded from the CI artifact list.
BP2BUILD_PROGRESS_MODULES=(
  com.android.neuralnetworks
  com.android.media.swcodec
)
bp2build_progress_script="//build/bazel/scripts/bp2build-progress:bp2build-progress"
bp2build_progress_output_dir="${DIST_DIR}/bp2build-progress"
mkdir -p "${bp2build_progress_output_dir}"

report_args=""
for m in "${BP2BUILD_PROGRESS_MODULES[@]}"; do
  report_args="$report_args -m ""${m}"
  tools/bazel run ${FLAGS} --config=linux_x86_64 "${bp2build_progress_script}" -- graph  -m "${m}" > "${bp2build_progress_output_dir}/${m}_graph.dot"
done

tools/bazel run ${FLAGS} --config=linux_x86_64 "${bp2build_progress_script}" -- \
  report ${report_args} \
  --proto-file=$( realpath "${bp2build_progress_output_dir}" )"/bp2build-progress.pb" \
  > "${bp2build_progress_output_dir}/progress_report.txt"
