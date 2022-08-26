"""
Copyright (C) 2022 The Android Open Source Project

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under thes License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
"""

load("//build/bazel/rules/aidl:library.bzl", "AidlGenInfo")
load("@bazel_skylib//lib:paths.bzl", "paths")
load(":cc_library_common.bzl", "create_ccinfo_for_includes")
load("//build/bazel/rules/cc:cc_library_static.bzl", "cc_library_static")

_SOURCES = "sources"
_HEADERS = "headers"
_INCLUDE_DIR = "include_dir"

def cc_aidl_library(name, deps, **kwargs):
    """
    Generate AIDL stub code for C++ and wrap it in a cc_library_static target

    Args:
        name:           (String) name of the cc_library_static target
        deps:           (list[AidlGenInfo]) list of all aidl_libraries that this
                        this cc_aidl_library depends on
    """
    aidl_code_gen = name + "_aidl_code_gen"
    _cc_aidl_code_gen(
        name = aidl_code_gen,
        deps = deps,
        **kwargs
    )
    cc_library_static(
        name = name,
        srcs = [":" + aidl_code_gen],
        # The generated headers from aidl_code_gen include the headers in
        # :libbinder_headers. All cc library/binary targets that depends on
        # cc_aidl_library needs to to explicitly include
        # //frameworks/native/libs/binder:libbinder which re-exports
        # //frameworks/native/libs/binder:libbinder_headers
        implementation_deps = [
            "//frameworks/native/libs/binder:libbinder_headers",
        ],
        deps = [aidl_code_gen],
        **kwargs
    )

def _cc_aidl_code_gen_impl(ctx):
    """
    Generate stub C++ code from direct aidl srcs using transitive deps

    Args:
        ctx: (RuleContext)
    Returns:
        (DefaultInfo) Generated .cpp and .cpp.d files
        (CcInfo)      Generated headers and their include dirs
    """
    generated_srcs, generated_hdrs, include_dirs = [], [], []

    for aidl_info in [d[AidlGenInfo] for d in ctx.attr.deps]:
        stub = _compile_aidl_srcs(ctx, aidl_info)
        generated_srcs.extend(stub[_SOURCES])
        generated_hdrs.extend(stub[_HEADERS])
        include_dirs.extend([stub[_INCLUDE_DIR]])

    return [
        DefaultInfo(files = depset(direct = generated_srcs + generated_hdrs)),
        create_ccinfo_for_includes(
            ctx,
            hdrs = generated_hdrs,
            includes = include_dirs,
        ),
    ]

_cc_aidl_code_gen = rule(
    implementation = _cc_aidl_code_gen_impl,
    attrs = {
        "deps": attr.label_list(
            providers = [AidlGenInfo],
        ),
        "_aidl": attr.label(
            allow_single_file = True,
            executable = True,
            cfg = "exec",
            default = Label("//prebuilts/build-tools:linux-x86/bin/aidl"),
        ),
    },
    provides = [CcInfo],
)

def _declare_stub_files(ctx, aidl_file):
    """
    Declare stub files that AIDL compiles to for cc

    Args:
      ctx:        (Context) Used to register declare_file actions.
      aidl_file:  (File) The aidl file
    Returns:
      (list[File]) List of declared stub files
    """
    ret = {}
    ret[_SOURCES], ret[_HEADERS] = [], []
    short_basename = paths.replace_extension(aidl_file.basename, "")

    ret[_SOURCES] = [
        ctx.actions.declare_file(
            paths.join(
                ctx.label.name,
                paths.dirname(aidl_file.short_path),
                short_basename + ".cpp",
            ),
        ),
    ]

    headers = [short_basename + ".h"]

    # Strip prefix I before creating basenames for bp and bn headers
    if short_basename.startswith("I"):
        short_basename = short_basename.removeprefix("I")
    headers.extend([
        "Bp" + short_basename + ".h",
        "Bn" + short_basename + ".h",
    ])
    for basename in headers:
        ret[_HEADERS].append(ctx.actions.declare_file(
            paths.join(ctx.label.name, paths.dirname(aidl_file.short_path), basename),
        ))

    return ret

def _compile_aidl_srcs(ctx, aidl_info):
    """
    Compile AIDL stub code for direct AIDL srcs

    Args:
      ctx:        (Context) Used to register declare_file actions.
      aidl_info:  (AidlGenInfo)
    Returns:
      (Dict)      A dict of where the the values are generated headers (.h) and their boilerplate implementation (.cpp)
    """

    ret = {}
    ret[_SOURCES], ret[_HEADERS] = [], []

    # transitive_include_dirs is traversed in preorder
    direct_include_dir = aidl_info.transitive_include_dirs.to_list()[0]

    # Path to generated headers that is relative to the package dir
    ret[_INCLUDE_DIR] = paths.join(
        ctx.label.name,
        paths.relativize(direct_include_dir, ctx.bin_dir.path),
    )

    # AIDL needs to know the full path to outputs
    out_dir = paths.join(
        ctx.bin_dir.path,
        ctx.label.package,
        ret[_INCLUDE_DIR],
    )

    outputs = []
    for aidl_file in aidl_info.srcs.to_list():
        files = _declare_stub_files(ctx, aidl_file)
        outputs.extend(files[_SOURCES] + files[_HEADERS])
        ret[_SOURCES].extend(files[_SOURCES])
        ret[_HEADERS].extend(files[_HEADERS])

    args = ctx.actions.args()
    args.add_all([
        "--ninja",
        "--lang=cpp",
        "--out={}".format(out_dir),
        "--header_out={}".format(out_dir),
    ])
    args.add_all(["-I {}".format(i) for i in aidl_info.transitive_include_dirs.to_list()])
    args.add_all(["{}".format(aidl_file.path) for aidl_file in aidl_info.srcs.to_list()])

    ctx.actions.run(
        inputs = aidl_info.transitive_srcs,
        outputs = outputs,
        executable = ctx.executable._aidl,
        arguments = [args],
        progress_message = "Compiling AIDL binding",
    )

    return ret
