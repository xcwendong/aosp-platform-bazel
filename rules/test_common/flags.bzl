# Copyright (C) 2022 The Android Open Source Project
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

load("@bazel_skylib//lib:new_sets.bzl", "sets")
load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")

# Checks for the presence of a set of given flags in a set of given actions
# exclusively. In other words, it confirms that *only* the specified actions
# contain the specified flags.
def _action_flags_present_only_for_mnemonic_test_impl(ctx):
    env = analysistest.begin(ctx)

    actions = analysistest.target_actions(env)
    for action in actions:
        if action.mnemonic in ctx.attr.mnemonics:
            if action.argv == None:
                asserts.true(
                    env,
                    False,
                    "expected %s action to have arguments, but argv was None" % (
                        action.mnemonic,
                    ),
                )
                continue
            for flag in ctx.attr.expected_flags:
                asserts.true(
                    env,
                    flag in action.argv,
                    "%s action did not contain flag %s; argv: %s" % (
                        action.mnemonic,
                        flag,
                        action.argv,
                    ),
                )
        elif action.argv != None:
            for flag in ctx.attr.expected_flags:
                asserts.false(
                    env,
                    flag in action.argv,
                    "%s action unexpectedly contained flag %s; argv: %s" % (
                        action.mnemonic,
                        flag,
                        action.argv,
                    ),
                )

    return analysistest.end(env)

action_flags_present_only_for_mnemonic_test = analysistest.make(
    _action_flags_present_only_for_mnemonic_test_impl,
    attrs = {
        "mnemonics": attr.string_list(
            doc = """
            Actions with these mnemonics will be expected to have the flags
            specified in expected_flags
            """,
        ),
        "expected_flags": attr.string_list(doc = "The flags to be checked for"),
    },
)

# Checks that a given set of flags are NOT present in a given set of actions.
# Unlike the above test, this test does NOT confirm the absence of flags
# *exclusively*. It does not confirm that the flags are present in actions
# other than those specified
def _action_flags_absent_for_mnemonic_test_impl(ctx):
    env = analysistest.begin(ctx)

    actions = analysistest.target_actions(env)
    for action in actions:
        if action.mnemonic in ctx.attr.mnemonics and action.argv != None:
            for flag in ctx.attr.expected_absent_flags:
                asserts.false(
                    env,
                    flag in action.argv,
                    "%s action unexpectedly contained flag %s; argv: %s" % (
                        action.mnemonic,
                        flag,
                        action.argv,
                    ),
                )

    return analysistest.end(env)

action_flags_absent_for_mnemonic_test = analysistest.make(
    _action_flags_absent_for_mnemonic_test_impl,
    attrs = {
        "mnemonics": attr.string_list(
            doc = """
            Actions with these mnemonics will be expected NOT to have the flags
            specificed in expected_flags
            """,
        ),
        "expected_absent_flags": attr.string_list(
            doc = """
            The flags to be confirmed are absent from the actions in mnemonics
            """,
        ),
    },
)
