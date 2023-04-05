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

load("@bazel_skylib//lib:paths.bzl", "paths")

AidlGenInfo = provider(
    fields = [
        "srcs",
        "hdrs",
        "hash_file",
        "transitive_srcs",
        "transitive_include_dirs",
        "flags",
    ],
)

def _symlink_aidl_srcs(ctx, srcs, strip_import_prefix):
    virtual_imports = paths.join("_virtual_imports", ctx.label.name)
    include_path = paths.join(ctx.genfiles_dir.path, ctx.label.package, virtual_imports)
    workspace_root_strip_import_prefix = paths.join(ctx.label.package, strip_import_prefix)

    direct_srcs = []
    for src in srcs:
        src_path = src.short_path

        if not paths.normalize(src_path).startswith(paths.normalize(workspace_root_strip_import_prefix)):
            fail(".aidl file '%s' is not under the specified strip prefix '%s'" %
                 (src_path, workspace_root_strip_import_prefix))

        import_path = paths.relativize(src_path, workspace_root_strip_import_prefix)
        virtual_src = ctx.actions.declare_file(paths.join(virtual_imports, import_path))
        ctx.actions.symlink(
            output = virtual_src,
            target_file = src,
            progress_message = "Symlinking virtual .aidl sources for %{label}",
        )
        direct_srcs.append(virtual_src)
    return include_path, direct_srcs

def _aidl_library_rule_impl(ctx):
    transitive_srcs = []
    transitive_include_dirs = []

    aidl_import_infos = [d[AidlGenInfo] for d in ctx.attr.deps]
    for info in aidl_import_infos:
        transitive_srcs.append(info.transitive_srcs)
        transitive_include_dirs.append(info.transitive_include_dirs)

    include_path, srcs = _symlink_aidl_srcs(ctx, ctx.files.srcs, ctx.attr.strip_import_prefix)
    _, hdrs = _symlink_aidl_srcs(ctx, ctx.files.hdrs, ctx.attr.strip_import_prefix)

    return [
        DefaultInfo(files = depset(ctx.files.srcs)),
        AidlGenInfo(
            srcs = depset(srcs),
            hdrs = depset(hdrs),
            hash_file = ctx.file.hash_file,
            transitive_srcs = depset(
                direct = srcs + hdrs,
                transitive = transitive_srcs,
            ),
            transitive_include_dirs = depset(
                direct = [include_path],
                transitive = transitive_include_dirs,
                # build with preorder so that transitive_include_dirs.to_list()
                # return direct include path in the first element
                order = "preorder",
            ),
            flags = ctx.attr.flags,
        ),
    ]

aidl_library = rule(
    implementation = _aidl_library_rule_impl,
    attrs = {
        "srcs": attr.label_list(
            allow_files = [".aidl"],
            doc = "AIDL source files that contain StructuredParcelable" +
                  " AIDL defintions. These files can be compiled to language" +
                  " bindings.",
        ),
        "hdrs": attr.label_list(
            allow_files = [".aidl"],
            doc = "AIDL source files that contain UnstructuredParcelable" +
                  " AIDL defintions. These files cannot be compiled to language" +
                  " bindings, but can be referenced by other AIDL sources.",
        ),
        "hash_file": attr.label(
            allow_single_file = [".hash"],
        ),
        "deps": attr.label_list(
            providers = [AidlGenInfo],
            doc = "Targets listed here provide AIDL sources referenced" +
                  "by this library.",
        ),
        "strip_import_prefix": attr.string(
            doc = "The prefix to strip from the paths of the .aidl files in " +
                  "this rule. When set, aidl source files in the srcs " +
                  "attribute of this rule are accessible at their path with " +
                  "this prefix cut off.",
        ),
        "flags": attr.string_list(
            doc = "Flags to pass to AIDL tool",
        ),
    },
    provides = [AidlGenInfo],
)

def _generate_aidl_bindings(ctx, lang, aidl_info):
    """ Utility function for creating AIDL bindings from aidl_libraries.

    Args:
      ctx: context, used for declaring actions and new files and providing _aidl_tool
      lang: string, defines the language of the generated binding code
      aidl_src_infos: AidlGenInfo, list of sources to provide to AIDL compiler

    Returns:
        list of output files
    """

    #TODO(b/235113507) support C++ AIDL binding
    ext = ""
    if lang == "java":
        ext = ".java"
    else:
        fail("Cannot generate AIDL language bindings for `{}`.".format(lang))

    out_files = []
    for aidl_file in aidl_info.srcs.to_list():
        out_filename = paths.replace_extension(aidl_file.basename, ext)
        out_file = ctx.actions.declare_file(out_filename, sibling = aidl_file)
        out_files.append(out_file)

        args = ctx.actions.args()
        args.add_all(aidl_info.flags)

        #TODO(b/241139797) allow this flag to be controlled by an attribute
        args.add("--structured")

        args.add_all([
            "-I {}".format(i)
            for i in aidl_info.transitive_include_dirs.to_list()
        ])
        args.add(aidl_file.path)
        args.add(out_file)

        ctx.actions.run(
            inputs = aidl_info.transitive_srcs,
            outputs = [out_file],
            arguments = [args],
            progress_message = "Generating {} AIDL binding from {}".format(lang, aidl_file.short_path),
            executable = ctx.executable._aidl_tool,
        )

    return out_files

aidl_file_utils = struct(
    generate_aidl_bindings = _generate_aidl_bindings,
)
