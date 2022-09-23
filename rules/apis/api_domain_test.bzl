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

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("@bazel_skylib//lib:paths.bzl", "paths")
load(":cc_api_contribution.bzl", "VALID_API_SURFACES", "cc_api_contribution")
load(":api_domain.bzl", "api_domain")

# Check that a .json file is created
def _json_output_test_impl(ctx):
    env = analysistest.begin(ctx)
    actions = analysistest.target_actions(env)
    asserts.equals(
        env,
        expected = len(VALID_API_SURFACES),
        actual = len(actions),
    )
    asserts.equals(
        env,
        expected = 1,
        actual = len(actions[0].outputs.to_list()),
    )
    asserts.equals(
        env,
        expected = "json",
        actual = actions[0].outputs.to_list()[0].extension,
    )
    return analysistest.end(env)

json_output_test = analysistest.make(_json_output_test_impl)

def _json_output_test():
    test_name = "json_output_test"
    subject_name = test_name + "_subject"
    api_domain(
        name = subject_name,
        cc_api_contributions = [],
        tags = ["manual"],
    )
    json_output_test(
        name = test_name,
        target_under_test = subject_name,
    )
    return test_name

# Check that output contains cc_libraries information
def _json_output_contains_cc_test_impl(ctx):
    env = analysistest.begin(ctx)
    actions = analysistest.target_actions(env)
    asserts.equals(
        env,
        expected = len(VALID_API_SURFACES),
        actual = len(actions),
    )

    # First element corresponds to publicapi
    output = json.decode(actions[0].content.replace("'", ""))  # Trim the surrounding '
    asserts.true(env, "cc_libraries" in output)
    cc_contributions_in_output = output.get("cc_libraries")
    asserts.equals(
        env,
        expected = 1,
        actual = len(cc_contributions_in_output),
    )
    test_contribution = cc_contributions_in_output[0]
    asserts.equals(
        env,
        expected = ctx.attr.expected_cc_library_name,
        actual = test_contribution.get("name"),
    )
    asserts.equals(
        env,
        expected = paths.join(
            paths.dirname(ctx.build_file_path),
            ctx.attr.expected_symbolfile,
        ),
        actual = test_contribution.get("api"),
    )
    return analysistest.end(env)

json_output_contains_cc_test = analysistest.make(
    impl = _json_output_contains_cc_test_impl,
    attrs = {
        "expected_cc_library_name": attr.string(),
        "expected_symbolfile": attr.string(),
    },
)

def _json_output_contains_cc_test():
    test_name = "json_output_contains_cc_test"
    subject_name = test_name + "_subject"
    cc_subject_name = subject_name + "_cc"
    symbolfile = "libfoo.map.txt"
    cc_api_contribution(
        name = cc_subject_name,
        api = symbolfile,
        tags = ["manual"],
    )
    api_domain(
        name = subject_name,
        cc_api_contributions = [cc_subject_name],
        tags = ["manual"],
    )
    json_output_contains_cc_test(
        name = test_name,
        target_under_test = subject_name,
        expected_cc_library_name = cc_subject_name,
        expected_symbolfile = symbolfile,
    )
    return test_name

def api_domain_test_suite(name):
    native.test_suite(
        name = name,
        tests = [
            _json_output_test(),
            _json_output_contains_cc_test(),
        ],
    )
