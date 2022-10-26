#!/bin/bash -eux

AOSP_ROOT="$(dirname $0)/../../.."
OUT_DIR=$(realpath ${OUT_DIR:-${AOSP_ROOT}/out})

source "$(dirname $0)/target_lists.sh"

read -ra PRODUCTS <<<"$(${AOSP_ROOT}/build/soong/soong_ui.bash --dumpvar-mode all_named_products)"

FAILED_PRODUCTS=()

function report {
  # check if FAILED_PRODUCTS is not empty
  if (( ${#FAILED_PRODUCTS[@]} )); then
    printf "Failed products:\n"
    printf '%s\n' "${FAILED_PRODUCTS[@]}"

    # Don't fail the build until every product is OK and we want to prevent backsliding.
    # exit 1
  fi
}

trap report EXIT

total=${#PRODUCTS[@]}
count=1

for product in "${PRODUCTS[@]}"; do
  echo "Product ${count}/${total}: ${product}"

  # Ensure that all processes later use the same TARGET_PRODUCT.
  export TARGET_PRODUCT="${product}"

  # Re-run product config and bp2build for every TARGET_PRODUCT.
  "${AOSP_ROOT}/build/soong/soong_ui.bash" --make-mode --skip-soong-tests bp2build
  # Remove the ninja_build output marker file to communicate to buildbot that this is not a regular Ninja build, and its
  # output should not be parsed as such.
  rm -f out/ninja_build

  STARTUP_FLAGS=(
    # Keep the Bazel server alive, package cache hot and reduce excessive I/O
    # and wall time by ensuring that max_idle_secs is longer than bp2build which
    # runs in every loop. bp2build takes ~20 seconds to run, so set this to a
    # minute to account for resource contention, but still ensure that the bazel
    # server doesn't stick around after.
    --max_idle_secs=60
  )

  FLAGS=(
    --config=bp2build
    --config=ci
    --nobuild
    --keep_going
  )

  build/bazel/bin/bazel ${STARTUP_FLAGS[@]} build ${FLAGS[@]} --config=linux_x86_64 -- ${BUILD_TARGETS} || \
    FAILED_PRODUCTS+=("${product} --config=linux_x86_64")

  build/bazel/bin/bazel ${STARTUP_FLAGS[@]} build ${FLAGS[@]} --config=android -- ${BUILD_TARGETS} || \
    FAILED_PRODUCTS+=("${product} --config=android")

  count=$((count+1))
done

