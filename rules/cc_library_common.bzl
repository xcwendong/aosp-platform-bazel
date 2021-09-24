load("//build/bazel/product_variables:constants.bzl", "constants")

_bionic_targets = ["//bionic/libc", "//bionic/libdl", "//bionic/libm"]

# The default system_dynamic_deps value for cc libraries. This value should be
# used if no value for system_dynamic_deps is specified.
system_dynamic_deps_defaults = select({
    constants.ArchVariantToConstraints["linux_bionic"]: _bionic_targets,
    constants.ArchVariantToConstraints["android"]: _bionic_targets,
    "//conditions:default": [],
})

def add_lists_defaulting_to_none(a, b):
    """Adds two lists a and b, but is well behaved with a `None` default."""
    if a == None:
        return b
    if b == None:
        return a
    return a + b
