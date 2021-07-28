def _apex_rule_impl(ctx):
    # Create an empty target for now.
    pass

_apex = rule(
    implementation = _apex_rule_impl,
    attrs = {
        "manifest": attr.label(allow_single_file = [".json"]),
        "android_manifest": attr.label(allow_single_file = [".xml"]),
        "file_contexts": attr.label(allow_single_file = True),
        "key": attr.label(allow_single_file = True),
        "certificate": attr.label(allow_single_file = True),
        "min_sdk_version": attr.string(),
        "updatable": attr.bool(default = True),
        "installable": attr.bool(default = True),
        "native_shared_libs": attr.label_list(),
        "binaries": attr.label_list(),
    },
)

def apex(
    name,
    manifest = "apex_manifest.json",
    android_manifest = None,
    file_contexts = None,
    key = None,
    certificate = None,
    min_sdk_version = None,
    updatable = True,
    installable = True,
    native_shared_libs = [],
    binaries = [],
    **kwargs):
    "Bazel macro to correspond with the APEX bundle Soong module."

    _apex(
        name = name,
        manifest = manifest,
        android_manifest = android_manifest,
        file_contexts = file_contexts,
        key = key,
        certificate = certificate,
        min_sdk_version = min_sdk_version,
        updatable = updatable,
        installable = installable,
        native_shared_libs = native_shared_libs,
        binaries = binaries,
        **kwargs,
    )
