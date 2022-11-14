"""
Copyright (C) 2022 The Android Open Source Project

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under thes License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
"""

# Types where generating a tradefed config is supported.
# These map to the template specified in _config_templates
_config_templates = {
    "cc": "//build/make/core:native_test_config_template.xml",
    "cc-host": "//build/make/core:native_host_test_config_template.xml",
}

TRADEFED_TEST_ATTRIBUTES = {
    "test": attr.label(
        providers = [[CcInfo]],
        doc = "Test target to run in tradefed.",
    ),
    "_tradefed_test_sh_template": attr.label(
        default = ":tradefed.sh.tpl",
        allow_single_file = True,
        doc = "Template script to launch tradefed.",
    ),
    "host": attr.bool(
        default = False,
        doc = "Is a host (deviceless) test",
    ),

    # Tradefed config specific attributes.
    "extra_configs": attr.string(
        doc = "Extra configs to extend into tradefed config file.",
    ),
    "test_install_base": attr.string(
        default = "/data/local/tmp",
        doc = "Directory to install the tests onto the device",
    ),
    "_config_templates": attr.label_list(
        default = _config_templates.values(),
        allow_files = True,
        doc = "List of templates to generate a tradefed config based on a provider type.",
    ),
}

# Generate tradefed config from template.
def _create_tradefed_test_config(ctx):
    out = ctx.actions.declare_file(ctx.attr.name + ".tradefed.config")

    module_name = ctx.attr.test.label.name

    # Choose template based on test target provider and host attribute.
    key = ""
    template_file = None
    if CcInfo in ctx.attr.test:
        key = "cc"
    if ctx.attr.host:
        key += "-host"
    for t in ctx.attr._config_templates:
        if str(t.label) == "@" + _config_templates[key]:
            template_file = t.files.to_list()[0]
    if not template_file:
        fail("Unsupported target for tradefed config generation: " + str(ctx.attr.test))

    ctx.actions.expand_template(
        template = template_file,
        output = out,
        substitutions = {
            "{MODULE}": module_name,
            "{EXTRA_CONFIGS}": ctx.attr.extra_configs,
            "{TEST_INSTALL_BASE}": ctx.attr.test_install_base,
        },
    )
    return out

# Generate and run tradefed bash script.
def _tradefed_test_impl(ctx):
    # Generate tradefed config.
    config = _create_tradefed_test_config(ctx)

    # Generate script to run tradefed.
    script = ctx.actions.declare_file("tradefed_test_%s.sh" % ctx.label.name)
    ctx.actions.expand_template(
        template = ctx.file._tradefed_test_sh_template,
        output = script,
        is_executable = True,
        substitutions = {},
    )

    # Gather runfiles.
    runfiles = ctx.runfiles()
    runfiles = runfiles.merge(ctx.attr.test.default_runfiles)
    runfiles = runfiles.merge(ctx.runfiles(files = [config]))

    return [DefaultInfo(
        executable = script,
        runfiles = runfiles,
    )]

# Generate and run tradefed bash script for deviceless (host) tests.
_tradefed_test = rule(
    doc = "A rule used to run tests using Tradefed",
    attrs = TRADEFED_TEST_ATTRIBUTES,
    test = True,
    implementation = _tradefed_test_impl,
)

def tradefed_device_test(**kwargs):
    _tradefed_test(
        host = False,
        **kwargs
    )

def tradefed_deviceless_test(**kwargs):
    _tradefed_test(
        host = True,
        **kwargs
    )
