load("//build/bazel/rules/android:rules.bzl", "android_binary", "android_library")
load("//build/bazel/rules/cc:cc_library_shared.bzl", "cc_library_shared")
load("//build/bazel/rules/cc:cc_library_static.bzl", "cc_library_static")

android_binary(
    name = "app",
    manifest = "AndroidManifest.xml",
    target_compatible_with = ["//build/bazel/platforms/os:android"],
    deps = [
        ":applib",
    ],
)

android_binary(
    name = "app-cert-string",
    certificate_name = "platform",
    manifest = "AndroidManifest.xml",
    target_compatible_with = ["//build/bazel/platforms/os:android"],
    deps = [
        ":applib",
    ],
)

android_binary(
    name = "app-cert-module",
    certificate = "//build/make/target/product/security:aosp-testkey",
    manifest = "AndroidManifest.xml",
    target_compatible_with = ["//build/bazel/platforms/os:android"],
    deps = [
        ":applib",
    ],
)

android_library(
    name = "applib",
    srcs = [
        "Jni.java",
        "MainActivity.java",
        "some_kotlin.kt",
    ],
    manifest = "AndroidManifest.xml",
    resource_files = glob(["res/**"]),
    target_compatible_with = ["//build/bazel/platforms/os:android"],
    deps = [
        # TODO(b/240555494): re-enable JNI when it is supported
        # ":jni",
        ":lib",
    ],
)

android_library(
    name = "lib",
    srcs = ["Lib.java"],
    target_compatible_with = ["//build/bazel/platforms/os:android"],
)

cc_library_shared(
    name = "jni",
    srcs = ["jni.cc"],
    deps = [":jni_dep"],
)

cc_library_static(
    name = "jni_dep",
    srcs = ["jni_dep.cc"],
    hdrs = ["jni_dep.h"],
    deps = ["//libnativehelper:jni_headers"],
)
