load("@rules_cc//cc:find_cc_toolchain.bzl", "find_cpp_toolchain")

def cc_library_static(
        name,
        implementation_deps = [],
        deps = [],
        hdrs = [],
        includes = [],
        native_bridge_supported = False,  # TODO: not supported yet.
        whole_archive_deps = [],
        rtti = False,
        # Flags for all languages
        copts = [],
        # C++ attributes
        srcs = [],
        cppflags = [],
        # C attributes
        srcs_c = [],
        conlyflags = [],
        # asm attributes
        srcs_as = [],
        asflags = [],
        **kwargs):
    "Bazel macro to correspond with the cc_library_static Soong module."
    cpp_name = "%s_cpp" % name
    c_name = "%s_c" % name
    asm_name = "%s_asm" % name

    features = []
    if rtti:
        features += ["rtti"]

    # Silently drop these attributes for now:
    # - native_bridge_supported
    common_attrs = dict(
        [
            ("hdrs", hdrs),
            ("implementation_deps", implementation_deps),
            # TODO(b/187533117): Handle whole_archive_deps differently from regular static deps.
            ("deps", deps + whole_archive_deps),
            ("includes", includes),
            ("features", features),
        ] + sorted(kwargs.items()),
    )

    native.cc_library(
        name = cpp_name,
        srcs = srcs,
        copts = copts + cppflags,
        **common_attrs
    )
    native.cc_library(
        name = c_name,
        srcs = srcs_c,
        copts = copts + conlyflags,
        **common_attrs
    )
    native.cc_library(
        name = asm_name,
        srcs = srcs_as,
        copts = copts + asflags,
        **common_attrs
    )

    # Root target to handle combining of the providers of the language-specific targets.
    _cc_library_combiner(
        name = name,
        deps = [cpp_name, c_name, asm_name],
    )

# Returns a CcInfo object which combines one or more CcInfo objects, except that all linker inputs
# with owners in `old_owner_labels` are recreated and owned by the current target.
#
# This is useful in the "macro with proxy rule" pattern, as some rules upstream
# may expect they are depending directly on a target which generates linker inputs,
# as opposed to a proxy target which is a level of indirection to such a target.
def _combine_and_own(ctx, old_owner_labels, cc_infos):
    combined_info = cc_common.merge_cc_infos(cc_infos=cc_infos)

    objects_to_link = []
    linker_inputs = []
    # This is not ideal, as it flattens a depset.
    for old_linker_input in combined_info.linking_context.linker_inputs.to_list():
        if old_linker_input.owner in old_owner_labels:
            # Drop the linker input and store the objects of that linker input.
            # The objects will be recombined into a single linker input.
            for lib in old_linker_input.libraries:
                objects_to_link.extend(lib.objects)
        else:
            linker_inputs.append(old_linker_input)
    return _link_archive(ctx, objects_to_link)

def _cc_library_combiner_impl(ctx):
    dep_labels = []
    cc_infos = []
    for dep in ctx.attr.deps:
        dep_labels.append(dep.label)
        cc_infos.append(dep[CcInfo])
    return _combine_and_own(ctx, dep_labels, cc_infos)

# Rule logic to handle propagation of a 'stub' library
def _link_archive(ctx, objects):
    cc_toolchain = find_cpp_toolchain(ctx)
    CPP_LINK_STATIC_LIBRARY_ACTION_NAME = "c++-link-static-library"
    feature_configuration = cc_common.configure_features(
        ctx = ctx,
        cc_toolchain = cc_toolchain,
        requested_features = ctx.features,
        unsupported_features = ctx.disabled_features + ["linker_flags"],
    )

    output_file = ctx.actions.declare_file("lib" + ctx.label.name + ".a")
    linker_input = cc_common.create_linker_input(
        owner = ctx.label,
        libraries = depset(direct = [
            cc_common.create_library_to_link(
                actions = ctx.actions,
                feature_configuration = feature_configuration,
                cc_toolchain = cc_toolchain,
                static_library = output_file,
                objects = objects,
            ),
        ]),
    )
    compilation_context = cc_common.create_compilation_context()
    linking_context = cc_common.create_linking_context(linker_inputs = depset(direct = [linker_input]))

    archiver_path = cc_common.get_tool_for_action(
        feature_configuration = feature_configuration,
        action_name = CPP_LINK_STATIC_LIBRARY_ACTION_NAME,
    )
    archiver_variables = cc_common.create_link_variables(
        feature_configuration = feature_configuration,
        cc_toolchain = cc_toolchain,
        output_file = output_file.path,
        is_using_linker = False,
    )
    command_line = cc_common.get_memory_inefficient_command_line(
        feature_configuration = feature_configuration,
        action_name = CPP_LINK_STATIC_LIBRARY_ACTION_NAME,
        variables = archiver_variables,
    )
    args = ctx.actions.args()
    args.add_all(command_line)
    args.add_all(objects)

    ctx.actions.run(
        executable = archiver_path,
        arguments = [args],
        inputs = depset(
            direct = objects,
            transitive = [
                cc_toolchain.all_files,
            ],
        ),
        outputs = [output_file],
    )

    cc_info = cc_common.merge_cc_infos(cc_infos = [dep[CcInfo] for dep in ctx.attr.deps]  +
        [CcInfo(compilation_context = compilation_context, linking_context = linking_context)])
    return [
        DefaultInfo(files = depset([output_file])),
        cc_info,
    ]

# A rule which combines objects of oen or more cc_library targets into a single
# static linker input. This outputs a single archive file combining the objects
# of its direct deps, and propagates Cc providers describing that these objects
# should be linked for linking rules upstream.
# This rule is useful for maintaining the illusion that the target's deps are
# comprised by a single consistent rule:
#   - A single archive file is always output by this rule.
#   - A single linker input struct is always output by this rule, and it is 'owned'
#       by this rule.
_cc_library_combiner = rule(
    implementation = _cc_library_combiner_impl,
    attrs = {
        # This should really be a label attribute since it always contains a
        # single dependency, but cc_shared_library requires that C++ rules
        # depend on each other through the "deps" attribute.
        "deps": attr.label_list(providers = [CcInfo]),
        "_cc_toolchain": attr.label(
            default = Label("@local_config_cc//:toolchain"),
            providers = [cc_common.CcToolchainInfo],
        ),
    },
    toolchains = ["@bazel_tools//tools/cpp:toolchain_type"],
    fragments = ["cpp"],
)
