# Copyright (C) 2023 The Android Open Source Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

load("@bazel_skylib//lib:dicts.bzl", "dicts")
load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("//build/bazel/rules/cc:cc_library_shared.bzl", "cc_library_shared")
load("//build/bazel/rules/cc:cc_library_static.bzl", "cc_library_static")

# TODO(b/270583469): Extract this and the equivalent logic for FDO
ActionArgsInfo = provider(
    fields = {
        "argv_map": "A dict with compile action arguments keyed by the target label",
    },
)

def _compile_action_argv_aspect_impl(target, ctx):
    argv_map = {}
    if ctx.rule.kind == "cc_library":
        cpp_compile_commands_args = []
        for action in target.actions:
            if action.mnemonic == "CppCompile":
                cpp_compile_commands_args.extend(action.argv)

        if len(cpp_compile_commands_args):
            argv_map = dicts.add(
                argv_map,
                {
                    target.label.name: cpp_compile_commands_args,
                },
            )
    elif ctx.rule.kind == "_cc_library_combiner":
        # propagate compile actions flags from [implementation_]whole_archive_deps upstream
        for dep in ctx.rule.attr.deps:
            argv_map = dicts.add(
                argv_map,
                dep[ActionArgsInfo].argv_map,
            )

        # propagate compile actions flags from roots (e.g. _cpp) upstream
        for root in ctx.rule.attr.roots:
            argv_map = dicts.add(
                argv_map,
                root[ActionArgsInfo].argv_map,
            )

        # propagate action flags from locals and exports
        for include in ctx.rule.attr.includes:
            argv_map = dicts.add(
                argv_map,
                include[ActionArgsInfo].argv_map,
            )
    elif ctx.rule.kind == "_cc_includes":
        for dep in ctx.rule.attr.deps:
            argv_map = dicts.add(
                argv_map,
                dep[ActionArgsInfo].argv_map,
            )
    elif ctx.rule.kind == "_cc_library_shared_proxy":
        # propagate compile actions flags from root upstream
        argv_map = dicts.add(
            argv_map,
            ctx.rule.attr.deps[0][ActionArgsInfo].argv_map,
        )
    return ActionArgsInfo(
        argv_map = argv_map,
    )

# _compile_action_argv_aspect is used to examine compile action from static deps
# as the result of the fdo transition attached to the cc_library_shared's deps
# and __internal_root_cpp which have cc compile actions.
# Checking the deps directly using their names give us the info before
# transition takes effect.
_compile_action_argv_aspect = aspect(
    implementation = _compile_action_argv_aspect_impl,
    attr_aspects = ["root", "roots", "deps", "includes"],
    provides = [ActionArgsInfo],
)

lto_flag = "-flto=thin"
static_cpp_suffix = "_cpp"
shared_cpp_suffix = "__internal_root_cpp"

def _lto_deps_test_impl(ctx):
    env = analysistest.begin(ctx)
    target_under_test = analysistest.target_under_test(env)
    argv_map = target_under_test[ActionArgsInfo].argv_map

    for target in ctx.attr.targets_with_lto:
        asserts.true(
            env,
            target in argv_map,
            "can't find {} in argv map".format(target),
        )
        argv = argv_map[target]
        asserts.true(
            env,
            lto_flag in argv,
            "Compile action of {} didn't have LTO but it was expected".format(
                target,
            ),
        )
    for target in ctx.attr.targets_without_lto:
        asserts.true(
            env,
            target in argv_map,
            "can't find {} in argv map".format(target),
        )
        argv = argv_map[target]
        asserts.true(
            env,
            lto_flag not in argv,
            "Compile action of {} had LTO but it wasn't expected".format(
                target,
            ),
        )
    return analysistest.end(env)

lto_deps_test = analysistest.make(
    _lto_deps_test_impl,
    attrs = {
        "targets_with_lto": attr.string_list(),
        "targets_without_lto": attr.string_list(),
    },
    # We need to use aspect to examine the dependencies' actions of the apex
    # target as the result of the transition, checking the dependencies directly
    # using names will give you the info before the transition takes effect.
    extra_target_under_test_aspects = [_compile_action_argv_aspect],
)

def _test_static_deps_have_lto():
    name = "static_deps_have_lto"
    requested_target_name = name + "_requested_target"
    static_dep_name = name + "_static_dep"
    static_dep_of_static_dep_name = "_static_dep_of_static_dep"
    test_name = name + "_test"

    cc_library_static(
        name = requested_target_name,
        srcs = ["foo.cpp"],
        deps = [static_dep_name],
        features = ["android_thin_lto"],
        tags = ["manual"],
    )

    cc_library_static(
        name = static_dep_name,
        srcs = ["bar.cpp"],
        deps = [static_dep_of_static_dep_name],
        tags = ["manual"],
    )

    cc_library_static(
        name = static_dep_of_static_dep_name,
        srcs = ["baz.cpp"],
        tags = ["manual"],
    )

    lto_deps_test(
        name = test_name,
        target_under_test = requested_target_name,
        targets_with_lto = [
            requested_target_name + static_cpp_suffix,
            static_dep_name + static_cpp_suffix,
            static_dep_of_static_dep_name + static_cpp_suffix,
        ],
        targets_without_lto = [],
    )

    return test_name

def _test_deps_of_shared_have_lto_if_enabled():
    name = "deps_of_shared_have_lto_if_enabled"
    requested_target_name = name + "_requested_target"
    shared_dep_name = name + "_shared_dep"
    static_dep_of_shared_dep_name = name + "_static_dep_of_shared_dep"
    test_name = name + "_test"

    cc_library_static(
        name = requested_target_name,
        srcs = ["foo.cpp"],
        dynamic_deps = [shared_dep_name],
        tags = ["manual"],
    )

    cc_library_shared(
        name = shared_dep_name,
        srcs = ["bar.cpp"],
        deps = [static_dep_of_shared_dep_name],
        features = ["android_thin_lto"],
        tags = ["manual"],
    )

    cc_library_static(
        name = static_dep_of_shared_dep_name,
        srcs = ["baz.cpp"],
        tags = ["manual"],
    )

    lto_deps_test(
        name = test_name,
        target_under_test = requested_target_name,
        targets_with_lto = [
            shared_dep_name + "__internal_root_cpp",
            static_dep_of_shared_dep_name + static_cpp_suffix,
        ],
        targets_without_lto = [requested_target_name + static_cpp_suffix],
    )

    return test_name

def _test_deps_of_shared_deps_no_lto_if_disabled():
    name = "deps_of_shared_deps_no_lto_if_disabled"
    requested_target_name = name + "_requested_target"
    shared_dep_name = name + "_shared_dep"
    static_dep_of_shared_dep_name = name + "_static_dep_of_shared_dep"
    test_name = name + "_test"

    cc_library_static(
        name = requested_target_name,
        srcs = ["foo.cpp"],
        dynamic_deps = [shared_dep_name],
        features = ["android_thin_lto"],
        tags = ["manual"],
    )

    cc_library_shared(
        name = shared_dep_name,
        srcs = ["bar.cpp"],
        deps = [static_dep_of_shared_dep_name],
        tags = ["manual"],
    )

    cc_library_static(
        name = static_dep_of_shared_dep_name,
        srcs = ["baz.cpp"],
        tags = ["manual"],
    )

    lto_deps_test(
        name = test_name,
        target_under_test = requested_target_name,
        targets_with_lto = [requested_target_name + static_cpp_suffix],
        targets_without_lto = [
            shared_dep_name + shared_cpp_suffix,
            static_dep_of_shared_dep_name + static_cpp_suffix,
        ],
    )

    return test_name

def lto_transition_test_suite(name):
    native.test_suite(
        name = name,
        tests = [
            _test_static_deps_have_lto(),
            _test_deps_of_shared_have_lto_if_enabled(),
            _test_deps_of_shared_deps_no_lto_if_disabled(),
        ],
    )
