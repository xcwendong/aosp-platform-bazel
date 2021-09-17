load("@rules_cc//examples:experimental_cc_shared_library.bzl", "CcSharedLibraryInfo")
load(":cc_library_common.bzl", "claim_ownership")
load(":cc_library_static.bzl", "cc_library_static")
load(":cc_library_shared.bzl", "cc_library_shared")

def _add_lists_defaulting_to_none(a, b):
    """Adds two lists a and b, but is well behaved with a `None` default."""
    if a == None:
        return b
    if b == None:
        return a
    return a + b

def cc_library(
        name,
        # attributes for both targets
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
        dynamic_deps = [],
        system_dynamic_deps = None,
        export_includes = [],
        export_system_includes = [],
        local_includes = [],
        absolute_includes = [],
        linkopts = [],
        rtti = False,
        use_libcrt = True,
        user_link_flags = [],
        version_script = None,
        strip = {},
        shared = {},  # attributes for the shared target
        static = {},  # attributes for the static target
        **kwargs):
    static_name = name + "_bp2build_cc_library_static"
    shared_name = name + "_bp2build_cc_library_shared"

    features = []
    if not use_libcrt:
        features += ["-use_libcrt"]

    # The static version of the library.
    cc_library_static(
        name = static_name,
        hdrs = hdrs,
        srcs = srcs + static.get("srcs", []),
        srcs_c = srcs_c + static.get("srcs_c", []),
        srcs_as = srcs_as + static.get("srcs_as", []),
        copts = copts + static.get("copts", []),
        cppflags = cppflags,
        conlyflags = conlyflags,
        asflags = asflags,
        export_includes = export_includes,
        export_system_includes = export_system_includes,
        local_includes = local_includes,
        absolute_includes = absolute_includes,
        linkopts = linkopts,
        rtti = rtti,
        whole_archive_deps = whole_archive_deps + static.get("whole_archive_deps", []),
        implementation_deps = implementation_deps + static.get("static_deps", []),
        dynamic_deps = dynamic_deps + static.get("dynamic_deps", []),
        system_dynamic_deps = _add_lists_defaulting_to_none(
            system_dynamic_deps,
            static.get("system_dynamic_deps", None),
        ),
        deps = deps,
        features = features,
    )

    cc_library_shared(
        name = shared_name,

        # Common arguments
        features = features,
        dynamic_deps = dynamic_deps + shared.get("dynamic_deps", []),

        # shared_root static arguments
        hdrs = hdrs,
        srcs = srcs + shared.get("srcs", []),
        srcs_c = srcs_c + shared.get("srcs_c", []),
        srcs_as = srcs_as + shared.get("srcs_as", []),
        copts = copts + shared.get("copts", []),
        cppflags = cppflags,
        conlyflags = conlyflags,
        asflags = asflags,
        export_includes = export_includes,
        export_system_includes = export_system_includes,
        local_includes = local_includes,
        absolute_includes = absolute_includes,
        linkopts = linkopts,
        rtti = rtti,
        whole_archive_deps = whole_archive_deps + shared.get("whole_archive_deps", []),
        implementation_deps = implementation_deps + shared.get("static_deps", []),
        system_dynamic_deps = _add_lists_defaulting_to_none(
            system_dynamic_deps,
            shared.get("system_dynamic_deps", None),
        ),
        deps = deps,

        # Shared library arguments
        user_link_flags = user_link_flags,
        version_script = version_script,
        strip = strip,
    )

    _cc_library_proxy(
        name = name,
        static = static_name,
        shared = shared_name,
    )

def _cc_library_proxy_impl(ctx):
    static_files = ctx.attr.static[DefaultInfo].files.to_list()
    shared_files = ctx.attr.shared[DefaultInfo].files.to_list()
    files = static_files + shared_files

    return [
        ctx.attr.shared[CcSharedLibraryInfo],
        claim_ownership(ctx, ctx.attr.static[CcInfo], ctx.attr.static.label),
        DefaultInfo(
            files = depset(direct = files),
            runfiles = ctx.runfiles(files = files),
        ),
    ]

_cc_library_proxy = rule(
    implementation = _cc_library_proxy_impl,
    attrs = {
        "shared": attr.label(mandatory = True, providers = [CcSharedLibraryInfo]),
        "static": attr.label(mandatory = True, providers = [CcInfo]),
    },
)
