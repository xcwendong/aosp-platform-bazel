load("//build/bazel/rules/partitions:partition.bzl", "partition")
package(default_visibility = ["//visibility:public"])

partition(
    name = "system_image",
    type = "system",
    deps = [
        "//build/bazel/examples/apex/minimal:build.bazel.examples.apex.minimal",
    ],
)
