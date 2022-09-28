#!/bin/bash -eux
# Verifies that bp2build-generated BUILD files result in successful Bazel
# builds.
#
# This verification script is designed to be used for continuous integration
# tests, though may also be used for manual developer verification.

#######
# Setup
#######

# Set the test output directories.
AOSP_ROOT="$(dirname $0)/../../.."
OUT_DIR=$(realpath ${OUT_DIR:-${AOSP_ROOT}/out})
if [[ -z ${DIST_DIR+x} ]]; then
  DIST_DIR="${OUT_DIR}/dist"
  echo "DIST_DIR not set. Using ${OUT_DIR}/dist. This should only be used for manual developer testing."
fi

# Before you add flags to this list, cosnider adding it to the "ci" bazelrc
# config instead of this list so that flags are not duplicated between scripts
# and bazelrc, and bazelrc is the Bazel-native way of organizing flags.
FLAGS_LIST=(
  --config=bp2build
  --config=ci
)
FLAGS="${FLAGS_LIST[@]}"

source "$(dirname $0)/target_lists.sh"

###############
# Build and test targets for device target platform.
###############

###########
# Iterate over various products supported in the platform build.
###########
product_prefix="aosp_"
for arch in arm arm64 x86 x86_64; do
  # Re-run product config and bp2build for every TARGET_PRODUCT.
  product=${product_prefix}${arch}
  "${AOSP_ROOT}/build/soong/soong_ui.bash" --make-mode BP2BUILD_VERBOSE=1 TARGET_PRODUCT=${product} --skip-soong-tests bp2build dist
  # Remove the ninja_build output marker file to communicate to buildbot that this is not a regular Ninja build, and its
  # output should not be parsed as such.
  rm -f out/ninja_build

  # Dist the entire workspace of generated BUILD files, rooted from
  # out/soong/bp2build. This is done early so it's available even if
  # builds/tests fail. Currently the generated BUILD files can be different
  # between products due to Soong plugins and non-deterministic codegeneration.
  tar --mtime='1970-01-01' -czf "${DIST_DIR}/bp2build_generated_workspace_${product}.tar.gz" -C out/soong/bp2build .

  STARTUP_FLAGS=(
    --max_idle_secs=5
    # Unique output bases per product to help with incremental builds across
    # invocations of this script.
    # e.g. the second invocation of this script for aosp_x86 would use the output_base
    # of aosp_x86 from the first invocation.
    --output_base="${OUT_DIR}/bazel/test_output_bases/${product}"
  )

  # Use a loop to prevent unnecessarily switching --platforms because that drops
  # the Bazel analysis cache.
  #
  # 1. Build every target in $BUILD_TARGETS
  tools/bazel ${STARTUP_FLAGS[@]} build ${FLAGS} --config=android -k -- ${BUILD_TARGETS}
  # 2. Test every target that is compatible with an android target platform (e.g. analysis_tests, sh_tests, diff_tests).
  tools/bazel ${STARTUP_FLAGS[@]} test ${FLAGS} --build_tests_only --config=android -k -- ${TEST_TARGETS}
  # 3. Dist mainline modules.
  tools/bazel ${STARTUP_FLAGS[@]} run //build/bazel/ci/dist:mainline_modules ${FLAGS} --config=android -- --dist_dir="${DIST_DIR}/mainline_modules_${arch}"
done

#########
# Host-only builds and tests
#########

# We can safely build and test all targets on the host linux config, and rely on
# incompatible target skipping for tests that cannot run on the host.
tools/bazel --max_idle_secs=5 test ${FLAGS} --build_tests_only=false -k \
  -- ${BUILD_TARGETS} ${TEST_TARGETS} "${HOST_INCOMPATIBLE_TARGETS[@]}"

###################
# bp2build-progress
###################

function get_soong_names_from_queryview() {
  names=$( tools/bazel query --config=ci --config=queryview --output=xml "${@}" \
    | awk -F'"' '$2 ~ /soong_module_name/ { print $4 }' \
    | sort -u )
  echo "${names[@]}"
}

# Generate bp2build progress reports and graphs for these modules into the dist
# dir so that they can be downloaded from the CI artifact list.
BP2BUILD_PROGRESS_MODULES=(
  NetworkStackNext  # not updatable but will be
  build-tools  # host sdk
  com.android.runtime  # not updatable but will be
  platform-tools  # host sdk
)

# Query for some module types of interest so that we don't have to hardcode the
# lists
"${AOSP_ROOT}/build/soong/soong_ui.bash" --make-mode BP2BUILD_VERBOSE=1 --skip-soong-tests queryview
rm -f out/ninja_build

# Only apexes/apps that specify updatable=1 are mainline modules, the other are
# "just" apexes/apps. Often this is not specified in the process of becoming a
# mainline module as enables a number of validations.
# Ignore defaults and test rules.
APEX_QUERY='attr(updatable, 1, //...) - kind("_defaults rule", //...) - kind("apex_test_ rule", //...)'
APEX_VNDK_QUERY="kind(\"apex_vndk rule\", //...)"

BP2BUILD_PROGRESS_MODULES+=( $(get_soong_names_from_queryview "${APEX_QUERY}"" + ""${APEX_VNDK_QUERY}" ) )

bp2build_progress_script="//build/bazel/scripts/bp2build-progress:bp2build-progress"
bp2build_progress_output_dir="${DIST_DIR}/bp2build-progress"
mkdir -p "${bp2build_progress_output_dir}"

report_args=""
for m in "${BP2BUILD_PROGRESS_MODULES[@]}"; do
  report_args="$report_args -m ""${m}"
  if [[ "${m}" =~ (media.swcodec|neuralnetworks)$ ]]; then
    tools/bazel run ${FLAGS} --config=linux_x86_64 "${bp2build_progress_script}" -- graph  -m "${m}" > "${bp2build_progress_output_dir}/${m}_graph.dot"
  fi
done

tools/bazel run ${FLAGS} --config=linux_x86_64 "${bp2build_progress_script}" -- \
  report ${report_args} \
  --proto-file=$( realpath "${bp2build_progress_output_dir}" )"/bp2build-progress.pb" \
  > "${bp2build_progress_output_dir}/progress_report.txt"
