load(":toolchain.bzl", "partition_toolchain")

toolchain_type(name = "partition_toolchain_type")

partition_toolchain(
    name = "partition_toolchain",
    build_image = "//build/make/tools/releasetools:build_image",
    e2fsdroid = "//external/e2fsprogs/contrib/android:e2fsdroid",
    mke2fs = "//external/e2fsprogs/misc:mke2fs",
    mkuserimg_mke2fs = "//system/extras/ext4_utils:mkuserimg_mke2fs",
    tags = ["manual"],
    tune2fs = "//external/e2fsprogs/misc:tune2fs",
)

toolchain(
    name = "partition_toolchain_def",
    exec_compatible_with = [
        "//build/bazel/platforms/arch:x86_64",
        "//build/bazel/platforms/os:linux",
    ],
    tags = ["manual"],
    target_compatible_with = [
        "//build/bazel/platforms/os:android",
    ],
    toolchain = ":partition_toolchain",
    toolchain_type = ":partition_toolchain_type",
)
