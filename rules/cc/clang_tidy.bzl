"""
Copyright (C) 2022 The Android Open Source Project

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
"""

load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load("@bazel_skylib//lib:paths.bzl", "paths")
load("@bazel_tools//tools/cpp:toolchain_utils.bzl", "find_cpp_toolchain")
load(
    "@bazel_tools//tools/build_defs/cc:action_names.bzl",
    "CPP_COMPILE_ACTION_NAME",
    "C_COMPILE_ACTION_NAME",
)
load("@soong_injection//product_config:product_variables.bzl", "product_vars")
load("@soong_injection//cc_toolchain:constants.bzl", "constants")

ClangTidyInfo = provider(
    "Info provided from clang-tidy actions",
    fields = {
        "tidy_files": "Outputs from the clang-tidy tool",
    },
)

_PRODUCT_VARIABLE_TIDY_CHECKS = product_vars["TidyChecks"].split(",") if "TidyChecks" in product_vars else []
_TIDY_GLOBAL_NO_CHECKS = constants.TidyGlobalNoChecks.split(",")
_TIDY_GLOBAL_NO_ERROR_CHECKS = constants.TidyGlobalNoErrorChecks.split(",")
_TIDY_DEFAULT_GLOBAL_CHECKS = constants.TidyDefaultGlobalChecks.split(",")
_TIDY_EXTERNAL_VENDOR_CHECKS = constants.TidyExternalVendorChecks.split(",")

def _get_compilation_args(toolchain, feature_config, flags, compilation_ctx, action_name):
    compilation_vars = cc_common.create_compile_variables(
        cc_toolchain = toolchain,
        feature_configuration = feature_config,
        user_compile_flags = flags,
        include_directories = compilation_ctx.includes,
        quote_include_directories = compilation_ctx.quote_includes,
        system_include_directories = compilation_ctx.system_includes,
        framework_include_directories = compilation_ctx.framework_includes,
    )

    return cc_common.get_memory_inefficient_command_line(
        feature_configuration = feature_config,
        action_name = action_name,
        variables = compilation_vars,
    )

def _check_bad_tidy_flags(tidy_flags):
    """should be kept up to date with
    https://cs.android.com/android/platform/superproject/+/master:build/soong/cc/check.go;l=128;drc=b45a2ea782074944f79fc388df20b06e01f265f7
    """
    for flag in tidy_flags:
        flag = flag.strip()
        if not flag.startswith("-"):
            fail("Flag `%s` must start with `-`" % flag)
        if flag.startswith("-fix"):
            fail("Flag `%s` is not allowed, since it could cause multiple writes to the same source file" % flag)
        if flag.startswith("-checks="):
            fail("Flag `%s` is not allowed, use `tidy_checks` property instead" % flag)
        if "-warnings-as-errors=" in flag:
            fail("Flag `%s` is not allowed, use `tidy_checks_as_errors` property instead" % flag)
        if " " in flag:
            fail("Bad flag: `%s` is not an allowed multi-word flag. Should it be split into multiple flags?" % flag)

def _check_bad_tidy_checks(tidy_checks):
    """should be kept up to date with
    https://cs.android.com/android/platform/superproject/+/master:build/soong/cc/check.go;l=145;drc=b45a2ea782074944f79fc388df20b06e01f265f7
    """
    for check in tidy_checks:
        if " " in check:
            fail("Check `%s` invalid, cannot contain spaces" % check)
        if "," in check:
            fail("Check `%s` invalid, cannot contain commas. Split each entry into it's own string instead" % check)

def _add_with_tidy_flags(ctx, tidy_flags):
    with_tidy_flags = ctx.attr._with_tidy_flags[BuildSettingInfo].value
    if with_tidy_flags:
        return tidy_flags + with_tidy_flags
    return tidy_flags

def _add_header_filter(ctx, tidy_flags):
    """If TidyFlags does not contain -header-filter, add default header filter.
    """
    for flag in tidy_flags:
        # Find the substring because the flag could also appear as --header-filter=...
        # and with or without single or double quotes.
        if "-header-filter=" in flag:
            return tidy_flags

    # Default header filter should include only the module directory,
    # not the out/soong/.../ModuleDir/...
    # Otherwise, there will be too many warnings from generated files in out/...
    # If a module wants to see warnings in the generated source files,
    # it should specify its own -header-filter flag.
    default_dirs = ctx.attr._default_tidy_header_dirs[BuildSettingInfo].value
    if default_dirs == "":
        header_filter = "-header-filter=^" + ctx.label.package + "/"
    else:
        header_filter = "-header-filter=\"(^%s/|%s)\"" % (ctx.label.package, default_dirs)
    return tidy_flags + [header_filter]

def _add_extra_arg_flags(tidy_flags):
    """keep up to date with
    https://cs.android.com/android/platform/superproject/+/master:build/soong/cc/tidy.go;l=138-152;drc=ff2efae9b014d644fcce8143258fa652fc2bcf13
    TODO(b/255750565) export this
    """
    extra_arg_flags = [
        # We might be using the static analyzer through clang tidy.
        # https://bugs.llvm.org/show_bug.cgi?id=32914
        "-D__clang_analyzer__",

        # A recent change in clang-tidy (r328258) enabled destructor inlining, which
        # appears to cause a number of false positives. Until that's resolved, this turns
        # off the effects of r328258.
        # https://bugs.llvm.org/show_bug.cgi?id=37459
        "-Xclang",
        "-analyzer-config",
        "-Xclang",
        "c++-temp-dtor-inlining=false",
    ]
    return tidy_flags + ["-extra-arg-before=" + f for f in extra_arg_flags]

def _add_quiet_if_not_global_tidy(tidy_flags):
    if len(_PRODUCT_VARIABLE_TIDY_CHECKS) == 0:
        return tidy_flags + [
            "-quiet",
            "-extra-arg-before=-fno-caret-diagnostics",
        ]
    return tidy_flags

def _clang_rewrite_tidy_checks(tidy_checks):
    # List of tidy checks that should be disabled globally. When the compiler is
    # updated, some checks enabled by this module may be disabled if they have
    # become more strict, or if they are a new match for a wildcard group like
    # `modernize-*`.
    clang_tidy_disable_checks = [
        "misc-no-recursion",
        "readability-function-cognitive-complexity",  # http://b/175055536
    ]

    tidy_checks = tidy_checks + ["-" + c for c in clang_tidy_disable_checks]

    # clang-tidy does not allow later arguments to override earlier arguments,
    # so if we just disabled an argument that was explicitly enabled we must
    # remove the enabling argument from the list.
    return [t for t in tidy_checks if t not in clang_tidy_disable_checks]

def _add_checks_for_dir(directory):
    """should be kept up to date with
    https://cs.android.com/android/platform/superproject/+/master:build/soong/cc/config/tidy.go;l=170;drc=b45a2ea782074944f79fc388df20b06e01f265f7
    """

    # This is a map of local path prefixes to the set of default clang-tidy checks
    # to be used.  This is like android.IsThirdPartyPath, but with more patterns.
    # The last matched local_path_prefix should be the most specific to be used.
    directory_checks = [
        ("external/", _TIDY_EXTERNAL_VENDOR_CHECKS),
        ("frameworks/compile/mclinker/", _TIDY_EXTERNAL_VENDOR_CHECKS),
        ("hardware/", _TIDY_EXTERNAL_VENDOR_CHECKS),
        ("hardware/google/", _TIDY_DEFAULT_GLOBAL_CHECKS),
        ("hardware/interfaces/", _TIDY_DEFAULT_GLOBAL_CHECKS),
        ("hardware/ril/", _TIDY_DEFAULT_GLOBAL_CHECKS),
        ("hardware/libhardware", _TIDY_DEFAULT_GLOBAL_CHECKS),  # all 'hardware/libhardware*'
        ("vendor/", _TIDY_EXTERNAL_VENDOR_CHECKS),
        ("vendor/google", _TIDY_DEFAULT_GLOBAL_CHECKS),  # all 'vendor/google*'
        ("vendor/google/external/", _TIDY_EXTERNAL_VENDOR_CHECKS),
        ("vendor/google_arc/libs/org.chromium.arc.mojom", _TIDY_EXTERNAL_VENDOR_CHECKS),
        ("vendor/google_devices/", _TIDY_EXTERNAL_VENDOR_CHECKS),  # many have vendor code
    ]

    for d, checks in reversed(directory_checks):
        if directory.startswith(d):
            return checks

    return _TIDY_DEFAULT_GLOBAL_CHECKS

def _add_global_tidy_checks(ctx, local_checks):
    global_tidy_checks = []
    if product_vars["TidyChecks"]:
        global_tidy_checks = _PRODUCT_VARIABLE_TIDY_CHECKS
    else:
        global_tidy_checks = _add_checks_for_dir(ctx.label.package)

    # If Tidy_checks contains "-*", ignore all checks before "-*".
    for i, check in enumerate(local_checks):
        if check == "-*":
            global_tidy_checks = []
            local_checks = local_checks[i:]

    tidy_checks = global_tidy_checks + _clang_rewrite_tidy_checks(local_checks)
    tidy_checks.extend(_TIDY_GLOBAL_NO_CHECKS)

    #TODO(b/255747672) disable cert check on windows only
    return tidy_checks

def _add_global_tidy_checks_as_errors(tidy_checks_as_errors):
    return tidy_checks_as_errors + _TIDY_GLOBAL_NO_ERROR_CHECKS

def _create_clang_tidy_action(
        ctx,
        clang_tool,
        input_file,
        tidy_checks,
        tidy_checks_as_errors,
        tidy_flags,
        clang_flags,
        headers,
        tidy_timeout):
    tidy_flags = _add_with_tidy_flags(ctx, tidy_flags)
    tidy_flags = _add_header_filter(ctx, tidy_flags)
    tidy_flags = _add_extra_arg_flags(tidy_flags)
    tidy_flags = _add_quiet_if_not_global_tidy(tidy_flags)
    tidy_checks = _add_global_tidy_checks(ctx, tidy_checks)
    tidy_checks_as_errors = _add_global_tidy_checks_as_errors(tidy_checks_as_errors)

    _check_bad_tidy_checks(tidy_checks)
    _check_bad_tidy_flags(tidy_flags)

    args = ctx.actions.args()
    args.add(input_file)
    if tidy_checks:
        args.add("-checks=" + ",".join(tidy_checks))
    if tidy_checks_as_errors:
        args.add("-warnings-as-errors=" + ",".join(tidy_checks_as_errors))
    if tidy_flags:
        args.add_all(tidy_flags)
    args.add("--")
    args.add_all(clang_flags)

    tidy_file = ctx.actions.declare_file(paths.join(ctx.label.name, input_file.short_path + ".tidy"))
    env = {
        "CLANG_CMD": clang_tool,
        "TIDY_FILE": tidy_file.path,
    }
    if tidy_timeout:
        env["TIDY_TIMEOUT"] = tidy_timeout

    ctx.actions.run(
        inputs = [input_file] + headers,
        outputs = [tidy_file],
        arguments = [args],
        env = env,
        progress_message = "Running clang-tidy on {}".format(input_file.short_path),
        tools = [
            ctx.executable._clang_tidy,
            ctx.executable._clang_tidy_real,
        ],
        executable = ctx.executable._clang_tidy_sh,
        execution_requirements = {
            "no-sandbox": "1",
        },
    )

    return tidy_file

def generate_clang_tidy_actions(
        ctx,
        flags,
        deps,
        srcs,
        hdrs,
        language,
        tidy_flags,
        tidy_checks,
        tidy_checks_as_errors,
        tidy_timeout):
    """Generates actions for clang tidy

    Args:
        ctx (Context): rule context that is expected to contain
            - ctx.executable._clang_tidy
            - ctx.executable._clang_tidy_sh
            - ctx.executable._clang_tidy_real
            - ctx.label._with_tidy_flags
        flags (list[str]): list of target-specific (non-toolchain) flags passed to clang compile action
        deps (list[Target]): list of Targets which provide headers to compilation context
        srcs (list[File]): list of srcs to which clang-tidy will be applied
        hdrs (list[File]): list of headers used by srcs. This is used to provide explicit inputs to the action
        language (str): must be one of ["c++", "c"]. This is used to decide what toolchain arguments are passed to the clang compile action
        tidy_flags (list[str]): additional flags to pass to the clang-tidy tool
        tidy_checks (list[str]): list of checks for clang-tidy to perform
        tidy_checks_as_errors (list[str]): list of checks to pass as "-warnings-as-errors" to clang-tidy
        tidy_checks_as_errors (str): timeout to pass to clang-tidy tool
    Returns:
        tidy_file_outputs: (list[File]): list of .tidy files output by the clang-tidy.sh tool
    """
    toolchain = find_cpp_toolchain(ctx)
    feature_config = cc_common.configure_features(
        ctx = ctx,
        cc_toolchain = toolchain,
        language = "c++",
        requested_features = ctx.features,
        unsupported_features = ctx.disabled_features,
    )

    language = language
    action_name = ""
    if language == "c++":
        action_name = CPP_COMPILE_ACTION_NAME
    elif language == "c":
        action_name = C_COMPILE_ACTION_NAME
    else:
        fail("invalid language:", language)

    dep_info = cc_common.merge_cc_infos(direct_cc_infos = [d[CcInfo] for d in deps])
    compilation_ctx = dep_info.compilation_context
    args = _get_compilation_args(
        toolchain = toolchain,
        feature_config = feature_config,
        flags = flags,
        compilation_ctx = compilation_ctx,
        action_name = action_name,
    )

    clang_tool = cc_common.get_tool_for_action(
        feature_configuration = feature_config,
        action_name = action_name,
    )

    header_inputs = (
        hdrs +
        compilation_ctx.headers.to_list() +
        compilation_ctx.direct_headers +
        compilation_ctx.direct_private_headers +
        compilation_ctx.direct_public_headers +
        compilation_ctx.direct_textual_headers
    )

    tidy_file_outputs = []
    for src in srcs:
        tidy_file = _create_clang_tidy_action(
            ctx = ctx,
            input_file = src,
            headers = header_inputs,
            clang_tool = paths.basename(clang_tool),
            tidy_checks = tidy_checks,
            tidy_checks_as_errors = tidy_checks_as_errors,
            tidy_flags = tidy_flags,
            clang_flags = args,
            tidy_timeout = tidy_timeout,
        )
        tidy_file_outputs.append(tidy_file)

    return tidy_file_outputs
