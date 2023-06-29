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

load(":installable_info.bzl", "InstallableInfo", "installable_aspect")

_IMAGE_TYPES = [
    "system",
    "system_other",
    "userdata",
    "cache",
    "vendor",
    "product",
    "system_ext",
    "odm",
    "vendor_dlkm",
    "system_dlkm",
    "oem",
]

def _get_python3(ctx):
    python_interpreter = ctx.toolchains["@bazel_tools//tools/python:toolchain_type"].py3_runtime.interpreter
    if python_interpreter.basename == "python3":
        return python_interpreter

    renamed = ctx.actions.declare_file("python3")
    ctx.actions.symlink(
        output = renamed,
        target_file = python_interpreter,
        is_executable = True,
    )
    return renamed

def _partition_impl(ctx):
    if ctx.attr.type != "system":
        fail("currently only system images are supported")

    toolchain = ctx.toolchains[":partition_toolchain_type"].toolchain_info
    python_interpreter = _get_python3(ctx)

    # build_image requires that the output file be named specifically <type>.img, so
    # put all the outputs under a name-qualified folder.
    image_info = ctx.actions.declare_file(ctx.attr.name + "/image_info.txt")
    output_image = ctx.actions.declare_file(ctx.attr.name + "/" + ctx.attr.type + ".img")
    ctx.actions.write(image_info, ctx.attr.image_properties)

    files = {}
    for dep in ctx.attr.deps:
        files.update(dep[InstallableInfo].files)

    for v in files.keys():
        if not v.startswith("/system"):
            fail("Files outside of /system are not currently supported: %s", v)

    staging_dir_builder_options_file = ctx.actions.declare_file(ctx.attr.name + "/staging_dir_builder_options.json")

    ctx.actions.write(staging_dir_builder_options_file, json.encode({
        # It seems build_image will prepend /system to the paths when building_system_image=true
        "file_mapping": {k.removeprefix("/system"): v.path for k, v in files.items()},
    }))

    staging_dir = ctx.actions.declare_directory(ctx.attr.name + "_staging_dir")

    build_image_files = toolchain.build_image[DefaultInfo].files_to_run

    # These are tools that are run from build_image or another tool that build_image runs.
    # They are all expected to be available in the PATH.
    extra_tools = [
        toolchain.e2fsdroid[DefaultInfo].files_to_run,
        toolchain.mke2fs[DefaultInfo].files_to_run,
        toolchain.mkuserimg_mke2fs[DefaultInfo].files_to_run,
        toolchain.tune2fs[DefaultInfo].files_to_run,
    ]

    ctx.actions.run(
        inputs = [
            image_info,
            staging_dir_builder_options_file,
        ] + files.values(),
        tools = extra_tools + [
            build_image_files,
            python_interpreter,
        ],
        outputs = [output_image, staging_dir],
        executable = ctx.executable._staging_dir_builder,
        arguments = [
            staging_dir_builder_options_file.path,
            staging_dir.path,
            build_image_files.executable.path,
            staging_dir.path,
            image_info.path,
            output_image.path,
            staging_dir.path,
        ],
        mnemonic = "BuildPartition",
        env = {
            # The dict + .keys() is to dedup the path elements, as some tools are in the same folder
            "PATH": ":".join({t.executable.dirname: True for t in extra_tools}.keys() + [
                # TODO: the /usr/bin addition is because build_image uses the du command
                # in GetDiskUsage(). This can probably be rewritten to just use python code
                # instead.
                "/usr/bin",
            ]),
        },
    )

    return DefaultInfo(files = depset([output_image]))

_partition = rule(
    implementation = _partition_impl,
    attrs = {
        "type": attr.string(
            mandatory = True,
            values = _IMAGE_TYPES,
        ),
        "image_properties": attr.string(
            doc = "The image property dictionary in key=value format. TODO: consider replacing this with explicit bazel properties for each property in this file.",
        ),
        "deps": attr.label_list(
            providers = [[InstallableInfo]],
            aspects = [installable_aspect],
        ),
        "_staging_dir_builder": attr.label(
            cfg = "exec",
            doc = "The tool used to build a staging directory, because if bazel were to build it it would be entirely symlinks.",
            executable = True,
            default = "//build/bazel/rules:staging_dir_builder",
        ),
    },
    toolchains = [
        ":partition_toolchain_type",
        "@bazel_tools//tools/python:toolchain_type",
    ],
)

def partition(target_compatible_with = [], **kwargs):
    target_compatible_with = select({
        "//build/bazel/platforms/os:android": [],
        "//conditions:default": ["@platforms//:incompatible"],
    }) + target_compatible_with
    _partition(
        target_compatible_with = target_compatible_with,
        **kwargs
    )
