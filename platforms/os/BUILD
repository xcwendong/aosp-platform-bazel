# Standard constraint_setting and constraint_values to be used in platforms.

load("@bazel_skylib//lib:selects.bzl", "selects")

licenses(["notice"])

package(
    default_visibility = ["//visibility:public"],
)

constraint_value(
    name = "android",
    constraint_setting = "@platforms//os:os",
)

# Alias to the local_jdk's toolchain constraint to make local_jdk resolve
# correctly with --tool_java_runtime_version=local_jdk and the checked-in JDK.
alias(
    name = "linux",
    actual = "@platforms//os:linux",
)

alias(
    name = "linux_glibc",
    actual = "@platforms//os:linux",
)

constraint_value(
    name = "linux_bionic",
    constraint_setting = "@platforms//os:os",
)

constraint_value(
    name = "windows",
    constraint_setting = "@platforms//os:os",
)

constraint_value(
    name = "fuchsia",
    constraint_setting = "@platforms//os:os",
)

constraint_value(
    name = "darwin",
    constraint_setting = "@platforms//os:os",
)

selects.config_setting_group(
    name = "bionic",
    match_any = [
        ":android",
        ":linux_bionic",
    ],
)
