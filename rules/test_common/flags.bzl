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

load("@bazel_skylib//lib:new_sets.bzl", "sets")
load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")

_action_flags_test_attrs = {
    "mnemonics_with_flags": attr.string_list(
        doc = """
        Actions with these mnemonics will be expected to have the specified
        flags. It is an error for this to share elements with
        mnemonics_without_flags.
        """,
    ),
    "mnemonics_without_flags": attr.string_list(
        doc = """
        Actions with these mnemonics will be expected NOT to have
        the specified flags. It is an error for this to share elements with
        mnemonics_with_flags.
        """,
    ),
    "exclusive": attr.bool(
        doc = """
        * If true when menmonics_with_flags is specified, exclusive checks
          that NO actions with other mnemonics have expected_flags
        * If true when mnemonics_without_flags is specified, exclusive checks
          that ALL actions with other mnemonics have expected_flags
        * If false, only the specified mnemonics will be checked, whether
          part of mnemonics_with_flags or mnemonics_without_flags
        * It is an error for exclusive to be specified with BOTH
          mnemonics_with_flags and mnemonics_without_flags
        """,
        default = True,
    ),
    "expected_flags": attr.string_list(doc = "The flags to be checked for"),
}

def _action_flags_test_impl(ctx):
    env = analysistest.begin(ctx)

    if (
        ctx.attr.exclusive and
        len(ctx.attr.mnemonics_with_flags) > 0 and
        len(ctx.attr.mnemonics_without_flags) > 0
    ):
        asserts.fail(env, """
                     Only one of mnemonics_with_flags and
                     mnemonics_without_flags can be specified with exclusive
                     """)
    if sets.length(
        sets.intersection(
            sets.make(ctx.attr.mnemonics_with_flags),
            sets.make(ctx.attr.mnemonics_without_flags),
        ),
    ) > 0:
        asserts.fail(env, """
                     mnemonics_with_flags and mnemonics_without_flags must not
                     overlap
                     """)

    exclusive_with_flags = False
    exclusive_without_flags = False
    if ctx.attr.exclusive:
        if len(ctx.attr.mnemonics_with_flags) > 0:
            exclusive_without_flags = True
        else:
            exclusive_with_flags = True

    actions = analysistest.target_actions(env)
    for action in actions:
        if (
            exclusive_with_flags or
            action.mnemonic in ctx.attr.mnemonics_with_flags
        ):
            for flag in ctx.attr.expected_flags:
                asserts.true(
                    env,
                    flag in action.argv,
                    "%s action did not contain flag %s" % (
                        action.mnemonic,
                        flag,
                    ),
                )
        elif (
            exclusive_without_flags or
            action.mnemonic in ctx.attr.mnemonics_without_flags
        ) and action.argv != None:
            for flag in ctx.attr.expected_flags:
                asserts.false(
                    env,
                    flag in action.argv,
                    "%s action unexpectedly contained flag %s" % (
                        action.mnemonic,
                        flag,
                    ),
                )
    return analysistest.end(env)

def create_action_flags_test_for_config(config_settings):
    return analysistest.make(
        _action_flags_test_impl,
        attrs = _action_flags_test_attrs,
        config_settings = config_settings,
    )

action_flags_test = create_action_flags_test_for_config({})
