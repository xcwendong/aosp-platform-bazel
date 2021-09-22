def add_lists_defaulting_to_none(a, b):
    """Adds two lists a and b, but is well behaved with a `None` default."""
    if a == None:
        return b
    if b == None:
        return a
    return a + b

# Returns a cloned copy of the given CcInfo object, except that all linker inputs
# with owner `old_owner_label` are recreated and owned `new_owner_label`,
# defaulting to `ctx.label`.
#
# This is useful in the "macro with proxy rule" pattern, as some rules upstream
# may expect they are depending directly on a target which generates linker inputs,
# as opposed to a proxy target which is a level of indirection to such a target.
def claim_ownership(ctx, ccinfo, old_owner_label, new_owner_label = None):
    if new_owner_label == None:
        new_owner_label = ctx.label
    linker_inputs = []

    # This is not ideal, as it flattens a depset.
    for old_linker_input in ccinfo.linking_context.linker_inputs.to_list():
        if old_linker_input.owner == old_owner_label:
            new_linker_input = cc_common.create_linker_input(
                owner = new_owner_label,
                libraries = depset(direct = old_linker_input.libraries),
            )
            linker_inputs.append(new_linker_input)
        else:
            linker_inputs.append(old_linker_input)

    linking_context = cc_common.create_linking_context(linker_inputs = depset(direct = linker_inputs))
    return CcInfo(compilation_context = ccinfo.compilation_context, linking_context = linking_context)
