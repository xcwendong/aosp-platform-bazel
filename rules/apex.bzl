def _apex_rule_impl(ctx):
    # Create an empty target for now.
    pass

_apex = rule(
    implementation = _apex_rule_impl,
    attrs = {
        "manifest": attr.label(mandatory = True, allow_single_file = True)
    },
)

def apex(
    name,
    manifest,
    **kwargs):
    "Bazel macro to correspond with the APEX bundle Soong module."

    _apex(
        name = name,
        manifest = manifest,
        **kwargs,
    )
