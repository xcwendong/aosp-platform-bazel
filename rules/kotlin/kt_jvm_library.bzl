"""
Copyright (C) 2023 The Android Open Source Project

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

load("@rules_kotlin//kotlin:compiler_opt.bzl", "kt_compiler_opt")
load("@rules_kotlin//kotlin:jvm_library.bzl", _kt_jvm_library = "kt_jvm_library")
load("//build/bazel/rules/java:rules.bzl", "java_import")

def _kotlin_resources_impl(ctx):
    output_file = ctx.actions.declare_file("kt_resources.jar")

    args = ctx.actions.args()
    args.add("cvf")
    args.add(output_file.path)
    args.add("-C")
    args.add(ctx.attr.resource_strip_prefix)
    args.add(".")

    ctx.actions.run(
        outputs = [output_file],
        inputs = ctx.files.srcs,
        executable = ctx.executable._jar,
        arguments = [args],
    )

    return [DefaultInfo(files = depset([output_file]))]

kotlin_resources = rule(
    doc = """
    Package srcs into a jar, with the option of stripping a path prefix
    """,
    implementation = _kotlin_resources_impl,
    attrs = {
        "srcs": attr.label_list(allow_files = True),
        "resource_strip_prefix": attr.string(
            doc = """The path prefix to strip from resources.
                   If specified, this path prefix is stripped from every fil
                   in the resources attribute. It is an error for a resource
                   file not to be under this directory. If not specified
                   (the default), the path of resource file is determined
                   according to the same logic as the Java package of source
                   files. For example, a source file at stuff/java/foo/bar/a.txt
                    will be located at foo/bar/a.txt.""",
        ),
        "_jar": attr.label(default = "@bazel_tools//tools/jdk:jar", executable = True, cfg = "exec"),
    },
)

def kt_jvm_library(
        name,
        deps = None,
        resources = None,
        resource_strip_prefix = None,
        kotlincflags = None,
        **kwargs):
    "Bazel macro wrapping for kt_jvm_library"

    if resource_strip_prefix != None:
        java_import_name = name + "resources"
        kt_res_jar_name = name + "resources_jar"
        java_import(
            name = java_import_name,
            jars = [":" + kt_res_jar_name],
        )

        kotlin_resources(
            name = kt_res_jar_name,
            srcs = resources,
            resource_strip_prefix = resource_strip_prefix,
        )

        deps = deps + [":" + java_import_name]

    custom_kotlincopts = None
    if kotlincflags != None:
        ktcopts_name = name + "_kotlincopts"
        kt_compiler_opt(
            name = ktcopts_name,
            opts = kotlincflags,
        )
        custom_kotlincopts = [":" + ktcopts_name]

    _kt_jvm_library(
        name = name,
        deps = deps,
        custom_kotlincopts = custom_kotlincopts,
        **kwargs
    )
