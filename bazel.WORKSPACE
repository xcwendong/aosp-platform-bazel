toplevel_output_directories(paths = ["out"])

load("//build/bazel/rules:lunch.bzl", "lunch")

lunch()

register_toolchains(
    "//prebuilts/clang/host/linux-x86:all"
)
