load("//prebuilts/clang/host/linux-x86:clang_version.bzl", "DEFAULT_VERSION")

# This test requires bp2build to run and the generated BUILD files in the source tree.
sh_test(
    name = "verify_bionic_outputs",
    srcs = ["verify_bionic_outputs.sh"],
    data = [
        "//bionic/linker:ld-android",
        "//bionic/libdl:libdl_android",
        "//prebuilts/clang/host/linux-x86:test_tools",
    ],
    env = {"CLANG_DEFAULT_VERSION": DEFAULT_VERSION},
    deps = ["@bazel_tools//tools/bash/runfiles"],
)
