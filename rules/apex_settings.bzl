ApexEnabledInfo = provider(
    doc = "A provider to enable APEX builds in Bazel.",
    fields = { "enabled": "Enable APEX builds in Bazel." }
)

def _enable_apex_flag_impl(ctx):
    return [ApexEnabledInfo(enabled = ctx.build_setting_value)]

enable_apex_flag = rule(
    implementation = _enable_apex_flag_impl,
    build_setting = config.bool(flag = True),
    doc = "Enable APEX builds in Bazel",
)
