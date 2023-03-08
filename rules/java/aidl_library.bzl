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

load("//build/bazel/rules/aidl:library.bzl", "AidlGenInfo", "aidl_file_utils")

JavaAidlAspectInfo = provider("JavaAidlAspectInfo", fields = ["jars"])

def _java_aidl_gen_aspect_impl(target, ctx):
    aidl_gen_java_files = aidl_file_utils.generate_aidl_bindings(ctx, "java", target[AidlGenInfo])
    java_deps = [
        d[JavaInfo]
        for d in ctx.rule.attr.deps + ctx.attr._sdk_dependency
    ]
    out_jar = ctx.actions.declare_file(target.label.name + "-aidl-gen.jar")
    java_info = java_common.compile(
        ctx,
        source_files = aidl_gen_java_files,
        deps = java_deps,
        output = out_jar,
        java_toolchain = ctx.toolchains["@bazel_tools//tools/jdk:toolchain_type"].java,
    )

    return [
        java_info,
        JavaAidlAspectInfo(
            jars = depset([out_jar]),
        ),
    ]

_java_aidl_gen_aspect = aspect(
    implementation = _java_aidl_gen_aspect_impl,
    attr_aspects = ["deps"],
    attrs = {
        "_aidl_tool": attr.label(
            allow_files = True,
            executable = True,
            cfg = "exec",
            default = Label("//prebuilts/build-tools:linux-x86/bin/aidl"),
        ),
        "_sdk_dependency": attr.label_list(
            default = [
                # TODO(b/215230098) remove forced dependency on current public android.jar
                "//prebuilts/sdk:system_current_android_sdk_java_import",
                # TODO(b/229251008) remove hard-coded dependency on framework-connectivity
                "//prebuilts/sdk:current_module_lib_framework_connectivity",
            ],
            providers = [JavaInfo],
        ),
    },
    toolchains = ["@bazel_tools//tools/jdk:toolchain_type"],
    fragments = ["java"],
    provides = [JavaInfo, JavaAidlAspectInfo],
)

def _java_aidl_library_rule_impl(ctx):
    java_info = java_common.merge([d[JavaInfo] for d in ctx.attr.deps])
    runtime_jars = depset(transitive = [dep[JavaAidlAspectInfo].jars for dep in ctx.attr.deps])
    transitive_runtime_jars = depset(transitive = [java_info.transitive_runtime_jars])

    return [
        java_info,
        DefaultInfo(
            files = runtime_jars,
            runfiles = ctx.runfiles(transitive_files = transitive_runtime_jars),
        ),
        OutputGroupInfo(default = depset()),
    ]

java_aidl_library = rule(
    implementation = _java_aidl_library_rule_impl,
    attrs = {
        "deps": attr.label_list(
            providers = [AidlGenInfo],
            aspects = [_java_aidl_gen_aspect],
        ),
    },
    provides = [JavaInfo],
)
