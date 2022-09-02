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
load(":cc_binary.bzl", "cc_binary")

def _cc_binary_strip_test(ctx):
    env = analysistest.begin(ctx)
    actions = analysistest.target_actions(env)
    filtered_actions = [a for a in actions if a.mnemonic == "CcStrip"]
    if not ctx.attr.strip_flags:
        asserts.true(
            env,
            len(filtered_actions) == 0,
            "expected to not find an action with CcStrip mnemonic in %s" % actions,
        )
        return analysistest.end(env)
    else:
        # expected to find strip flags, so look for a CcStrip action.
        asserts.true(
            env,
            len(filtered_actions) == 1,
            "expected to find an action with CcStrip mnemonic in %s" % actions,
        )

        strip_action = filtered_actions[0]

        # Extract these flags from strip_action (for example):
        # build/soong/scripts/strip.sh --keep-symbols --add-gnu-debuglink -i <in> -o <out> -d <out>.d
        #                              ^^^^^^^^^^^^^^ ^^^^^^^^^^^^^^^^^^^
        flag_start_idx = 1  # starts after the strip.sh executable
        flag_end_idx = strip_action.argv.index("-i")  # end of the flags
        asserts.equals(
            env,
            strip_action.argv[flag_start_idx:flag_end_idx],
            ctx.attr.strip_flags,
        )

        return analysistest.end(env)

cc_binary_strip_test = analysistest.make(
    _cc_binary_strip_test,
    attrs = {"strip_flags": attr.string_list()},
)

def _cc_binary_strip_default():
    name = "cc_binary_strip_default"
    test_name = name + "_test"

    cc_binary(
        name = name,
        srcs = ["main.cc"],
        tags = ["manual"],
    )

    cc_binary_strip_test(
        name = test_name,
        target_under_test = name,
        strip_flags = [],
    )

    return test_name

def _cc_binary_strip_none():
    name = "cc_binary_strip_none"
    test_name = name + "_test"

    cc_binary(
        name = name,
        srcs = ["main.cc"],
        tags = ["manual"],
        strip = {"none": True},
    )

    cc_binary_strip_test(
        name = test_name,
        target_under_test = name,
        strip_flags = [],
    )

    return test_name

def _cc_binary_strip_keep_symbols():
    name = "cc_binary_strip_keep_symbols"
    test_name = name + "_test"

    cc_binary(
        name = name,
        srcs = ["main.cc"],
        tags = ["manual"],
        strip = {"keep_symbols": True},
    )

    cc_binary_strip_test(
        name = test_name,
        target_under_test = name,
        strip_flags = [
            "--keep-symbols",
            "--add-gnu-debuglink",
        ],
    )

    return test_name

def _cc_binary_strip_keep_symbols_and_debug_frame():
    name = "cc_binary_strip_keep_symbols_and_debug_frame"
    test_name = name + "_test"

    cc_binary(
        name = name,
        srcs = ["main.cc"],
        tags = ["manual"],
        strip = {"keep_symbols_and_debug_frame": True},
    )

    cc_binary_strip_test(
        name = test_name,
        target_under_test = name,
        strip_flags = [
            "--keep-symbols-and-debug-frame",
            "--add-gnu-debuglink",
        ],
    )

    return test_name

def _cc_binary_strip_keep_symbols_list():
    name = "cc_binary_strip_keep_symbols_list"
    test_name = name + "_test"

    cc_binary(
        name = name,
        srcs = ["main.cc"],
        tags = ["manual"],
        strip = {"keep_symbols_list": ["foo", "bar"]},
    )

    cc_binary_strip_test(
        name = test_name,
        target_under_test = name,
        strip_flags = [
            "-kfoo,bar",
            "--add-gnu-debuglink",
        ],
    )

    return test_name

def _cc_binary_strip_all():
    name = "cc_binary_strip_all"
    test_name = name + "_test"

    cc_binary(
        name = name,
        srcs = ["main.cc"],
        tags = ["manual"],
        strip = {"all": True},
    )

    cc_binary_strip_test(
        name = test_name,
        target_under_test = name,
        strip_flags = [
            "--add-gnu-debuglink",
        ],
    )

    return test_name

def _cc_binary_suffix_test_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)
    info = target[DefaultInfo]
    suffix = ctx.attr.suffix

    outputs = info.files.to_list()
    asserts.true(
        env,
        len(outputs) == 1,
        "Expected 1 output file; got %s" % outputs,
    )
    out = outputs[0].path
    asserts.true(
        env,
        out.endswith(suffix),
        "Expected output filename to end in `%s`; it was instead %s" % (suffix, out),
    )

    return analysistest.end(env)

cc_binary_suffix_test = analysistest.make(
    _cc_binary_suffix_test_impl,
    attrs = {"suffix": attr.string()},
)

def _cc_binary_suffix():
    name = "cc_binary_suffix"
    test_name = name + "_test"
    suffix = "-suf"

    cc_binary(
        name,
        srcs = ["src.cc"],
        tags = ["manual"],
        suffix = suffix,
    )
    cc_binary_suffix_test(
        name = test_name,
        target_under_test = name,
        suffix = suffix,
    )
    return test_name

def _cc_binary_empty_suffix():
    name = "cc_binary_empty_suffix"
    test_name = name + "_test"

    cc_binary(
        name,
        srcs = ["src.cc"],
        tags = ["manual"],
    )
    cc_binary_suffix_test(
        name = test_name,
        target_under_test = name,
    )
    return test_name

def cc_binary_test_suite(name):
    native.test_suite(
        name = name,
        tests = [
            _cc_binary_strip_default(),
            _cc_binary_strip_keep_symbols(),
            _cc_binary_strip_keep_symbols_and_debug_frame(),
            _cc_binary_strip_keep_symbols_list(),
            _cc_binary_strip_all(),
            _cc_binary_suffix(),
            _cc_binary_empty_suffix(),
        ],
    )
