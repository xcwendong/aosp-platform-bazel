load("//build/bazel/rules/apex:apex_aab.bzl", "apex_aab")

modules = [
    "//build/bazel/examples/apex/minimal:build.bazel.examples.apex.minimal",
    "//frameworks/av/apex:com.android.media.swcodec",
    "//packages/modules/NeuralNetworks/apex:com.android.neuralnetworks",
    "//packages/modules/adb/apex:com.android.adbd",
    "//system/timezone/apex:com.android.tzdata",
]

name_label_map = {module[module.index(":") + 1:]: module for module in modules}

[
    apex_aab(
        name = "%s_apex_aab" % name,
        mainline_module = label,
    )
    for name, label in name_label_map.items()
]

filegroup(
    name = "mainline_modules",
    srcs = ["%s_apex_aab" % name for name, label in name_label_map.items()],
)
