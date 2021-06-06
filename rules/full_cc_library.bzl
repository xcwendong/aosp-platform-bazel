load(":cc_library_static.bzl", "cc_library_static")
load("@rules_cc//examples:experimental_cc_shared_library.bzl", "CcSharedLibraryInfo", "cc_shared_library")

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
        includes = [],
        linkopts = [],
        rtti = False,
        # attributes for the shared target
        dynamic_deps_for_shared = [],
        shared_srcs = [],
        shared_srcs_c = [],
        shared_srcs_as = [],
        shared_copts = [],
        static_deps_for_shared = [],
        whole_archive_deps_for_shared = [],
        user_link_flags = [],
        version_script = None,
        # attributes for the static target
        dynamic_deps_for_static = [],
        static_srcs = [],
        static_srcs_c = [],
        static_srcs_as = [],
        static_copts = [],
        static_deps_for_static = [],
        whole_archive_deps_for_static = [],
        **kwargs):
    static_name = name + "_bp2build_cc_library_static"
    shared_name = name + "_bp2build_cc_library_shared"
    shared_root_name = name + "_bp2build_cc_library_shared_root"
    _cc_library_proxy(
        name = name,
        static = static_name,
        shared = shared_name,
    )

    # The static version of the library.
    cc_library_static(
        name = static_name,
        hdrs = hdrs,
        srcs = srcs + static_srcs,
        srcs_c = srcs_c + static_srcs_c,
        srcs_as = srcs_as + static_srcs_as,
        copts = copts + static_copts,
        cppflags = cppflags,
        conlyflags = conlyflags,
        asflags = asflags,
        includes = includes,
        linkopts = linkopts,
        rtti = rtti,
        whole_archive_deps = whole_archive_deps + whole_archive_deps_for_static,
        implementation_deps = implementation_deps + static_deps_for_static,
        dynamic_deps = dynamic_deps + dynamic_deps_for_static,
        deps = deps,
    )

    # The static library at the root of the shared library.
    # This may be distinct from the static library if, for example,
    # the static-variant srcs are different than the shared-variant srcs.
    cc_library_static(
        name = shared_root_name,
        hdrs = hdrs,
        srcs = srcs + shared_srcs,
        srcs_c = srcs_c + shared_srcs_c,
        srcs_as = srcs_as + shared_srcs_as,
        copts = copts + shared_copts,
        cppflags = cppflags,
        conlyflags = conlyflags,
        asflags = asflags,
        includes = includes,
        linkopts = linkopts,
        rtti = rtti,
        whole_archive_deps = whole_archive_deps + whole_archive_deps_for_shared,
        implementation_deps = implementation_deps + static_deps_for_shared,
        dynamic_deps = dynamic_deps + dynamic_deps_for_shared,
        deps = deps,
    )

    cc_shared_library(
        name = shared_name,
        user_link_flags = user_link_flags,
        # b/184806113: Note this is a pretty a workaround so users don't have to
        # declare all transitive static deps used by this target.  It'd be great
        # if a shared library could declare a transitive exported static dep
        # instead of needing to declare each target transitively.
        static_deps = ["//:__subpackages__"] + [shared_root_name],
        dynamic_deps = dynamic_deps + dynamic_deps_for_shared,
        version_script = version_script,
        roots = [shared_root_name],
    )

# Returns a cloned copy of the given CcInfo object, except that all linker inputs
# with owner `old_owner_label` are recreated and owned by the current target.
#
# This is useful in the "macro with proxy rule" pattern, as some rules upstream
# may expect they are depending directly on a target which generates linker inputs,
# as opposed to a proxy target which is a level of indirection to such a target.
def _claim_ownership(ctx, old_owner_label, ccinfo):
    linker_inputs = []
    # This is not ideal, as it flattens a depset.
    for old_linker_input in ccinfo.linking_context.linker_inputs.to_list():
        if old_linker_input.owner == old_owner_label:
            new_linker_input = cc_common.create_linker_input(
                owner = ctx.label,
                libraries = depset(direct = old_linker_input.libraries))
            linker_inputs.append(new_linker_input)
        else:
            linker_inputs.append(old_linker_input)

    linking_context = cc_common.create_linking_context(linker_inputs = depset(direct = linker_inputs))
    return CcInfo(compilation_context = ccinfo.compilation_context, linking_context = linking_context)

def _cc_library_proxy_impl(ctx):
    static_files = ctx.attr.static[DefaultInfo].files.to_list()
    shared_files = ctx.attr.shared[DefaultInfo].files.to_list()

    files = static_files + shared_files

    return [
        ctx.attr.shared[CcSharedLibraryInfo],
        _claim_ownership(ctx, ctx.attr.static.label, ctx.attr.static[CcInfo]),
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
