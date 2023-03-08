#!/usr/bin/env bash

###############
# Build and test targets for device target platform.
###############
BUILD_TARGETS=(
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
  //prebuilts/runtime/...
  //prebuilts/tools/...
  //platform_testing/...
  //system/...
  //tools/apksig/...
  //tools/asuite/...
  //tools/platform-compat/...

  # These tools only build for host currently
  -//external/e2fsprogs/misc:all
  -//external/e2fsprogs/resize:all
  -//external/e2fsprogs/debugfs:all
  -//external/e2fsprogs/e2fsck:all

  # TODO(b/215230098): remove after handling sdk_version for aidl
  -//frameworks/av:av-types-aidl-java

  # TODO(b/266459895): remove these after re-enabling libunwindstack
  -//bionic/libc/malloc_debug:libc_malloc_debug
  -//bionic/libfdtrack:libfdtrack
  -//frameworks/av/services/mediacodec:mediaswcodec
  -//frameworks/av/media/codec2/hidl/1.0/utils:libcodec2_hidl@1.0
  -//frameworks/native/opengl/libs:libEGL
  -//frameworks/av/media/module/bqhelper:libstagefright_bufferqueue_helper_novndk
  -//frameworks/native/opengl/libs:libGLESv2
  -//frameworks/av/media/codec2/hidl/1.1/utils:libcodec2_hidl@1.1
  -//frameworks/av/media/module/codecserviceregistrant:libmedia_codecserviceregistrant
  -//frameworks/av/media/codec2/hidl/1.2/utils:libcodec2_hidl@1.2
  -//system/unwinding/libunwindstack:all
  -//system/core/libutils:all
)

TEST_TARGETS=(
  //build/bazel/...
)

HOST_ONLY_TEST_TARGETS=(
  //tools/trebuchet:AnalyzerKt
  //tools/metalava:metalava
  # Test both unstripped and stripped versions of a host native unit test
  //system/core/libcutils:libcutils_test
  //system/core/libcutils:libcutils_test__test_binary_unstripped
  # TODO(b/268186228): adb_test fails only on CI
  -//packages/modules/adb:adb_test
  # TODO(b/268185249): libbase_test asserts on the Soong basename of the test
  -//system/libbase:libbase_test
)

HOST_INCOMPATIBLE_TARGETS=(
  # TODO(b/216626461): add support for host_ldlibs
  -//packages/modules/adb:all
  -//packages/modules/adb/pairing_connection:all
)
