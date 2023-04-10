"""android_library rule."""

load(
    "//build/bazel/rules/android/android_library_aosp_internal:rule.bzl",
    "android_library_aosp_internal_macro",
)

def android_library(**attrs):
    """ android_library macro wrapper that handles custom attrs needed in AOSP

    Args:
      **attrs: Rule attributes
    """
    android_library_aosp_internal_macro(**attrs)
