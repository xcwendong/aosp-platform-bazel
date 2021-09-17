load("@rules_cc//examples:experimental_cc_shared_library.bzl", "CcSharedLibraryInfo", "cc_shared_library")
load(":cc_library_common.bzl", "claim_ownership")
load(":cc_library_static.bzl", "cc_library_static")
load(":stripped_shared_library.bzl", "stripped_shared_library")
load(":generate_toc.bzl", "shared_library_toc")

def cc_library_shared(
        name,
        # Common arguments between shared_root and the shared library
        features = [],
        dynamic_deps = [],

        # Ultimately _static arguments for shared_root production
        srcs = [],
        srcs_c = [],
        srcs_as = [],
        copts = [],
        cppflags = [],
        conlyflags = [],
        asflags = [],
        hdrs = [],
        implementation_deps = [],
        deps = [],
        whole_archive_deps = [],
        root_dynamic_deps = [],
        system_dynamic_deps = None,
        export_includes = [],
        export_system_includes = [],
        local_includes = [],
        absolute_includes = [],
        linkopts = [],
        rtti = False,
        use_libcrt = True,

        # Purely _shared arguments
        user_link_flags = [],
        version_script = None,
        strip = {},
        **kwargs):
    "Bazel macro to correspond with the cc_library_shared Soong module."

    shared_root_name = name + "_root"
    unstripped_name = name + "_unstripped"
    stripped_name = name + "_stripped"
    toc_name = name + "_toc"

    # The static library at the root of the shared library.
    # This may be distinct from the static version of the library if e.g.
    # the static-variant srcs are different than the shared-variant srcs.
    cc_library_static(
        name = shared_root_name,
        hdrs = hdrs,
        srcs = srcs,
        srcs_c = srcs_c,
        srcs_as = srcs_as,
        copts = copts,
        cppflags = cppflags,
        conlyflags = conlyflags,
        asflags = asflags,
        export_includes = export_includes,
        export_system_includes = export_system_includes,
        local_includes = local_includes,
        absolute_includes = absolute_includes,
        linkopts = linkopts,
        rtti = rtti,
        whole_archive_deps = whole_archive_deps,
        implementation_deps = implementation_deps,
        dynamic_deps = dynamic_deps,
        system_dynamic_deps = system_dynamic_deps,
        deps = deps,
        features = features,
    )

    cc_shared_library(
        name = unstripped_name,
        user_link_flags = user_link_flags,
        # b/184806113: Note this is  a workaround so users don't have to
        # declare all transitive static deps used by this target.  It'd be great
        # if a shared library could declare a transitive exported static dep
        # instead of needing to declare each target transitively.
        static_deps = ["//:__subpackages__"] + [shared_root_name],
        dynamic_deps = dynamic_deps,
        version_script = version_script,
        roots = [shared_root_name],
        features = features,
        **kwargs
    )

    stripped_shared_library(
        name = stripped_name,
        src = unstripped_name,
        **strip
    )

    shared_library_toc(
        name = toc_name,
        src = stripped_name,
    )

    _cc_library_shared_proxy(
        name = name,
        shared = stripped_name,
        root = shared_root_name,
        table_of_contents = toc_name,
    )

def _cc_library_shared_proxy_impl(ctx):
    root_files = ctx.attr.root[DefaultInfo].files.to_list()
    shared_files = ctx.attr.shared[DefaultInfo].files.to_list()

    files = root_files + shared_files + [ctx.file.table_of_contents]

    return [
        ctx.attr.shared[CcSharedLibraryInfo],
        claim_ownership(ctx, ctx.attr.root[CcInfo], ctx.attr.root.label, ctx.attr.shared.label),
        DefaultInfo(
            files = depset(direct = files),
            runfiles = ctx.runfiles(files = files),
        ),
    ]

_cc_library_shared_proxy = rule(
    implementation = _cc_library_shared_proxy_impl,
    attrs = {
        "shared": attr.label(mandatory = True, providers = [CcSharedLibraryInfo]),
        "root": attr.label(mandatory = True, providers = [CcInfo]),
        "table_of_contents": attr.label(mandatory = True, allow_single_file = True),
    },
)
