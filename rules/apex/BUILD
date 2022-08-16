load("//build/bazel/rules/apex:toolchain.bzl", "apex_toolchain")
load("@bazel_skylib//rules:common_settings.bzl", "bool_flag", "string_list_setting", "string_setting")
load(":apex_test.bzl", "apex_test_suite")
load(":apex_aab_test.bzl", "apex_aab_test_suite")

string_setting(
    name = "apex_name",
    build_setting_default = "",
    visibility = ["//visibility:public"],
)

config_setting(
    name = "non_apex",
    flag_values = {
        ":apex_name": "",
    },
)

string_list_setting(
    name = "apex_direct_deps",
    build_setting_default = [],
    visibility = ["//visibility:public"],
)

bool_flag(
    name = "apexer_verbose",
    build_setting_default = False,
    visibility = ["//visibility:public"],
)

toolchain_type(name = "apex_toolchain_type")

apex_toolchain(
    name = "apex_toolchain",
    aapt2 = "//prebuilts/sdk/tools:linux/bin/aapt2",
    android_jar = "//prebuilts/sdk/current:public/android.jar",
    apex_compression_tool = "//system/apex/tools:apex_compression_tool",
    apexer = "//system/apex/apexer",
    avbtool = "//external/avb:avbtool",
    conv_apex_manifest = "//system/apex/apexer:conv_apex_manifest",
    e2fsdroid = "//external/e2fsprogs/contrib/android:e2fsdroid",
    jsonmodify = "//build/soong/scripts:jsonmodify",
    mke2fs = "//external/e2fsprogs/misc:mke2fs",
    resize2fs = "//external/e2fsprogs/resize:resize2fs",
    sefcontext_compile = "//external/selinux/libselinux:sefcontext_compile",
    soong_zip = "//prebuilts/build-tools:linux-x86/bin/soong_zip",
)

toolchain(
    name = "apex_toolchain_def",
    exec_compatible_with = [
        "//build/bazel/platforms/arch:x86_64",
        "//build/bazel/platforms/os:linux",
    ],
    target_compatible_with = [
        "//build/bazel/platforms/os:android",
    ],
    toolchain = ":apex_toolchain",
    toolchain_type = "//build/bazel/rules/apex:apex_toolchain_type",
)

apex_test_suite(
    name = "apex_tests",
)

apex_aab_test_suite(
    name = "apex_aab_tests",
)
