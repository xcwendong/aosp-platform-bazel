load(":apex_diff_test.bzl", "apex_diff_test")
load(":apex_test.bzl", "apex_compression_test")
load(":apex_aab_test.bzl", "apex_aab_test")
load(":apex_aapt2_test.bzl", "apex_package_name_test")
load("@bazel_skylib//rules:diff_test.bzl", "diff_test")

# Test that the compressed apex and uncompressed apex have the same contents
apex_diff_test(
    name = "com.android.adbd_compressed_vs_uncompressed",
    apex1 = "//packages/modules/adb/apex:com.android.adbd.capex",
    apex2 = "//packages/modules/adb/apex:com.android.adbd.apex",
    target_compatible_with = ["//build/bazel/platforms/os:android"],
)

apex_compression_test(
    name = "build.bazel.examples.apex.minimal_apex",
    apex = "//build/bazel/examples/apex/minimal:build.bazel.examples.apex.minimal.apex",
    compressed = False,
)

apex_compression_test(
    name = "build.bazel.examples.apex.minimal_capex",
    apex = "//build/bazel/examples/apex/minimal:build.bazel.examples.apex.minimal_compressed.capex",
    compressed = True,
)

apex_aab_test(
    name = "build.bazel.examples.apex.minimal_mainline-module",
    apex = "//build/bazel/examples/apex/minimal:build.bazel.examples.apex.minimal",
    golden = ":build.bazel.examples.apex.minimal.aab",
)

apex_package_name_test(
    name = "build.bazel.examples.apex.minimal_package_name",
    apex = "//build/bazel/examples/apex/minimal:build.bazel.examples.apex.minimal.apex",
    expected_package_name = "build.bazel.examples.apex.minimal",
)

apex_package_name_test(
    name = "build.bazel.examples.apex.override.minimal_package_name",
    apex = "//build/bazel/examples/apex/minimal:build.bazel.examples.apex.override.minimal.apex",
    expected_package_name = "build.bazel.examples.apex.override.minimal",
)

apex_package_name_test(
    name = "com.android.adbd_package_name",
    apex = "//packages/modules/adb/apex:com.android.adbd.apex",
    expected_package_name = "com.android.adbd",
)

genrule(
    name = "com.android.adbd.apex_manifest_json",
    srcs = ["//packages/modules/adb/apex:com.android.adbd.apex"],
    outs = ["com.android.adbd.apex_manifest.json"],
    cmd = "$(location //system/apex/tools:deapexer) info $< > $@",
    tools = ["//system/apex/tools:deapexer"],
)

diff_test(
    name = "com.android.adbd.apex_manifest_diff_test",
    file1 = "com.android.adbd.apex_manifest.json",
    file2 = "com.android.adbd.apex_manifest.json.golden",
    target_compatible_with = ["//build/bazel/platforms/os:linux"],
)
