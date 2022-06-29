"""Copyright (C) 2022 The Android Open Source Project

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

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load(":flex.bzl", "genlex")

ROOT_PATH = "build/bazel/rules/cc/"
OUT_PATH = "bin/build/bazel/rules/cc/"

# Path will vary based on lunch target. Check ending instead of checking for
# presence in the list
def _assert_output(env, actual_action, expected_item, target_name, test_name):
    actual_list = [output.path for output in actual_action.outputs.to_list()]
    found_output = False
    for actual_item in actual_list:
        if actual_item.endswith(expected_item):
            found_output = True
            break
    asserts.true(
        env,
        found_output,
        ("Expected output %s not present or incorrect in Bazel action for " +
         "target %s in test %s") % (expected_item, target_name, test_name),
    )

def _single_l_file_to_c_test_impl(ctx):
    env = analysistest.begin(ctx)

    actions = analysistest.target_actions(env)

    asserts.equals(env, 1, len(actions))

    actual_list_foo = [input.path for input in actions[0].inputs.to_list()]
    expected_path_foo = "%s%s" % (ROOT_PATH, "foo.l")
    asserts.true(
        env,
        expected_path_foo in actual_list_foo,
        ("Input file %s not present or incorrect in Bazel action for " +
         "target foo. Actual list of inputs: %s") % (
            expected_path_foo,
            actual_list_foo,
        ),
    )
    _assert_output(
        env,
        actions[0],
        "%s%s" % (OUT_PATH, "foo.c"),
        "foo",
        "single_l_file_to_c_test",
    )

    return analysistest.end(env)

single_l_file_to_c_test = analysistest.make(_single_l_file_to_c_test_impl)

def _test_single_l_file_to_c():
    name = "single_l_file_to_c"
    test_name = name + "_test"
    genlex(
        name = name,
        srcs = ["foo.l"],
        tags = ["manual"],
    )
    single_l_file_to_c_test(
        name = test_name,
        target_under_test = name,
    )
    return test_name

def _single_ll_file_to_cc_test_impl(ctx):
    env = analysistest.begin(ctx)

    actions = analysistest.target_actions(env)

    asserts.equals(env, 1, len(actions))

    actual_list_foo = [input.path for input in actions[0].inputs.to_list()]
    expected_path_foo = "%s%s" % (ROOT_PATH, "foo.ll")
    asserts.true(
        env,
        expected_path_foo in actual_list_foo,
        ("Input file %s not present or incorrect in Bazel action for " +
         "target foo. Actual list of inputs: %s") % (
            expected_path_foo,
            actual_list_foo,
        ),
    )
    _assert_output(
        env,
        actions[0],
        "%s%s" % (OUT_PATH, "foo.cc"),
        "foo",
        "single_ll_file_to_cc_test",
    )

    return analysistest.end(env)

single_ll_file_to_cc_test = analysistest.make(_single_ll_file_to_cc_test_impl)

def _test_single_ll_file_to_cc():
    name = "single_ll_file_to_cc"
    test_name = name + "_test"
    genlex(
        name = name,
        srcs = ["foo.ll"],
        tags = ["manual"],
    )
    single_ll_file_to_cc_test(
        name = test_name,
        target_under_test = name,
    )
    return test_name

def _multiple_files_correct_type_test_impl(ctx):
    env = analysistest.begin(ctx)

    actions = analysistest.target_actions(env)

    asserts.equals(env, 2, len(actions))

    actual_list_foo = [input.path for input in actions[0].inputs.to_list()]
    expected_path_foo = "%s%s" % (ROOT_PATH, "foo.l")
    asserts.true(
        env,
        expected_path_foo in actual_list_foo,
        ("Input file %s not present or incorrect in Bazel action for " +
         "target foo. Actual list of inputs: %s") % (
            expected_path_foo,
            actual_list_foo,
        ),
    )
    actual_list_bar = [input.path for input in actions[1].inputs.to_list()]
    expected_path_bar = "%s%s" % (ROOT_PATH, "bar.l")
    asserts.true(
        env,
        expected_path_bar in actual_list_bar,
        ("Input file %s not present or incorrect in Bazel action for " +
         "target bar. Actual list of inputs: %s") % (
            expected_path_bar,
            actual_list_bar,
        ),
    )
    _assert_output(
        env,
        actions[0],
        "%s%s" % (OUT_PATH, "foo.c"),
        "foo",
        "multiple_files_correct_type",
    )
    _assert_output(
        env,
        actions[1],
        "%s%s" % (OUT_PATH, "bar.c"),
        "bar",
        "multiple_files_correct_type",
    )

    return analysistest.end(env)

multiple_files_correct_type_test = analysistest.make(
    _multiple_files_correct_type_test_impl,
)

def _test_multiple_files_correct_type():
    name = "multiple_files_correct_type"
    test_name = name + "_test"
    genlex(
        name = name,
        srcs = ["foo.l", "bar.l"],
        tags = ["manual"],
    )
    multiple_files_correct_type_test(
        name = test_name,
        target_under_test = name,
    )
    return test_name

def _output_arg_test_impl(ctx):
    env = analysistest.begin(ctx)

    actions = analysistest.target_actions(env)
    actual_list = actions[0].argv
    expected_name = "-o"
    expected_value = "%s%s" % (ROOT_PATH, "foo.c")

    found_arg = False
    for i in range(len(actual_list))[1:]:
        if actual_list[i] == expected_name:
            asserts.true(
                env,
                actual_list[i + 1].endswith(expected_value),
                "Expected value %s for arg %s but got %s for target foo" % (
                    expected_value,
                    expected_name,
                    actual_list[i + 1],
                ),
            )
            found_arg = True
    asserts.true(
        env,
        found_arg,
        ("%s argument not found in command for target foo. Actual list: " +
         "%s") % (expected_name, actual_list),
    )

    return analysistest.end(env)

output_arg_test = analysistest.make(_output_arg_test_impl)

def _test_output_arg():
    name = "output_arg"
    test_name = name + "_test"
    genlex(
        name = name,
        srcs = ["foo.l"],
        tags = ["manual"],
    )
    output_arg_test(
        name = test_name,
        target_under_test = name,
    )
    return test_name

def _input_arg_test_impl(ctx):
    env = analysistest.begin(ctx)

    actions = analysistest.target_actions(env)
    actual_list = actions[0].argv
    expected_value = "%s%s" % (ROOT_PATH, "foo.l")

    asserts.true(
        env,
        expected_value in actual_list,
        "Input file %s not present or incorrect in flex command args" %
        expected_value,
    )

    return analysistest.end(env)

input_arg_test = analysistest.make(_input_arg_test_impl)

def _test_input_arg():
    name = "input_arg"
    test_name = name + "_test"
    genlex(
        name = name,
        srcs = ["foo.l"],
        tags = ["manual"],
    )
    input_arg_test(
        name = test_name,
        target_under_test = name,
    )
    return test_name

def _lexopts_test_impl(ctx):
    env = analysistest.begin(ctx)
    actions = analysistest.target_actions(env)

    actual_args = actions[0].argv
    asserts.true(
        env,
        "foo_opt" in actual_args,
        ("Did not find expected lexopt foo_opt %s for target foo in test " +
         "lexopts_test") % actual_args,
    )
    asserts.true(
        env,
        "bar_opt" in actual_args,
        ("Did not find expected lexopt bar_opt %s for target bars in test " +
         "lexopts_test") % actual_args,
    )

    return analysistest.end(env)

lexopts_test = analysistest.make(_lexopts_test_impl)

def _test_lexopts():
    name = "lexopts"
    test_name = name + "_test"
    genlex(
        name = name,
        srcs = ["foo_lexopts.ll"],
        lexopts = ["foo_opt", "bar_opt"],
        tags = ["manual"],
    )

    lexopts_test(
        name = test_name,
        target_under_test = name,
    )
    return test_name

# TODO(b/190006308): When fixed, l and ll sources can coexist. Remove this test.
def _l_and_ll_files_fails_test_impl(ctx):
    env = analysistest.begin(ctx)

    asserts.expect_failure(
        env,
        "srcs contains both .l and .ll files. Please use separate targets.",
    )

    return analysistest.end(env)

l_and_ll_files_fails_test = analysistest.make(
    _l_and_ll_files_fails_test_impl,
    expect_failure = True,
)

def _test_l_and_ll_files_fails():
    name = "l_and_ll_files_fails"
    test_name = name + "_test"
    genlex(
        name = name,
        srcs = ["foo_fails.l", "bar_fails.ll"],
        tags = ["manual"],
    )
    l_and_ll_files_fails_test(
        name = test_name,
        target_under_test = name,
    )
    return test_name

def flex_test_suite(name):
    native.test_suite(
        name = name,
        tests = [
            _test_single_l_file_to_c(),
            _test_single_ll_file_to_cc(),
            _test_multiple_files_correct_type(),
            _test_output_arg(),
            _test_input_arg(),
            _test_lexopts(),
            _test_l_and_ll_files_fails(),
        ],
    )
