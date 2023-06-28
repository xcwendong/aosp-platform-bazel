load("//build/bazel/rules/partitions:partition.bzl", "partition")

package(default_visibility = ["//visibility:public"])

partition(
    name = "system_image",
    image_properties = """
system_fs_type=ext4
system_reserved_size=67108864
building_system_image=true
ext_mkuserimg=mkuserimg_mke2fs
fs_type=ext4
squashfs_sparse_flag=-s
f2fs_sparse_flag=-S
erofs_default_compressor=lz4hc,9
ext4_share_dup_blocks=true
use_dynamic_partition_size=true
skip_fsck=true
""",
    type = "system",
    deps = [
        "//build/bazel/examples/apex/minimal:build.bazel.examples.apex.minimal",
    ],
)
