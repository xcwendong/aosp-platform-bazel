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

TRADEFED_TEST_ATTRIBUTES = {
    "test": attr.label(
        providers = [[CcInfo]],
        doc = "Test target to run in tradefed.",
    ),
    "host": attr.bool(
        default = False,
        doc = "Is a host (deviceless) test",
    ),
    "_tradefed_test_sh_template": attr.label(
        default = ":tradefed.sh.tpl",
        allow_single_file = True,
        doc = "Template script to launch tradefed.",
    ),
    "_tradefed_dependencies": attr.label_list(
        default = [
            "//prebuilts/runtime:prebuilt-runtime-adb",
            "//tools/tradefederation/prebuilts/filegroups/tradefed:bp2build_all_srcs",
            "//tools/tradefederation/prebuilts/filegroups/suite:compatibility-host-util-prebuilt",
            "//tools/tradefederation/prebuilts/filegroups/suite:compatibility-tradefed-prebuilt",
            "//tools/asuite/atest:atest-tradefed",
            "//tools/asuite/atest/bazel/reporter:bazel-result-reporter",
        ],
        doc = "Files needed on the PATH to run tradefed",
    ),

    # Test config and if test config generation attributes.
    "test_config": attr.label(
        allow_single_file = True,
        doc = "Test/Tradefed config.",
    ),
    "template_test_config": attr.label(
        allow_single_file = True,
        doc = "Template to generate test config.",
    ),
    "template_configs": attr.string_list(
        doc = "Extra tradefed config options to extend into generated test config.",
    ),
    "template_install_base": attr.string(
        default = "/data/local/tmp",
        doc = "Directory to install tests onto the device for generated config",
    ),
}

# Get test config if specified or generate test config from template.
def _get_or_generate_test_config(ctx):
    # Validate input
    c = ctx.file.test_config
    c_template = ctx.file.template_test_config
    if c and c_template:
        fail("Both test_config and test_config_template were provided, please use only 1 of them")
    if not c and not c_template:
        fail("Either test_config or test_config_template should be provided")

    # Check for existing tradefed configs and if found add a symlink.
    if c:
        out = ctx.actions.declare_file(c.basename + ".test.config")
        ctx.actions.symlink(
            output = out,
            target_file = c,
        )
        return out

    # No existing config specified - generate from template.
    out = ctx.actions.declare_file(ctx.attr.name + ".test.config")

    # Join extra configs together and add xml spacing indent.
    extra_configs = "\n    ".join(ctx.attr.template_configs)
    module_name = ctx.attr.test.label.name

    ctx.actions.expand_template(
        template = c_template,
        output = out,
        substitutions = {
            "{MODULE}": module_name,
            "{EXTRA_CONFIGS}": extra_configs,
            "{TEST_INSTALL_BASE}": ctx.attr.template_install_base,
        },
    )
    return out

# Generate tradefed result reporter config.
def _create_result_reporter_config(ctx):
    result_reporters_config_file = ctx.actions.declare_file("result-reporters.xml")
    config_lines = [
        "<?xml version=\"1.0\" encoding=\"utf-8\"?>",
        "<configuration>",
    ]

    result_reporters = [
        "com.android.tradefed.result.BazelExitCodeResultReporter",
        "com.android.tradefed.result.BazelXmlResultReporter",
    ]
    for result_reporter in result_reporters:
        config_lines.append("    <result_reporter class=\"%s\" />" % result_reporter)
    config_lines.append("</configuration>")

    ctx.actions.write(result_reporters_config_file, "\n".join(config_lines))
    return result_reporters_config_file

# Generate and run tradefed bash script.
def _tradefed_test_impl(ctx):
    # Get or generate test config.
    test_config = _get_or_generate_test_config(ctx)

    # Generate result reporter config file.
    report_config = _create_result_reporter_config(ctx)

    # Gather runfiles.
    runfiles = ctx.runfiles()
    runfiles = runfiles.merge_all([
        ctx.attr.test.default_runfiles,
        ctx.runfiles(files = ctx.files._tradefed_dependencies + [test_config, report_config]),
    ])

    # Gather directories of runfiles to put on the PATH.
    dependency_paths = {}
    for f in runfiles.files.to_list():
        dependency_paths[f.dirname] = True
    for f in runfiles.symlinks.to_list():
        dependency_paths[f.dirname] = True
    path_additions = ":".join(dependency_paths.keys())

    # Generate script to run tradefed.
    script = ctx.actions.declare_file("tradefed_test_%s.sh" % ctx.label.name)
    ctx.actions.expand_template(
        template = ctx.file._tradefed_test_sh_template,
        output = script,
        is_executable = True,
        substitutions = {
            "{MODULE}": ctx.attr.test.label.name,
            "{PATH_ADDITIONS}": path_additions,
        },
    )

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
