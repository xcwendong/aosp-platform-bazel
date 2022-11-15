"""Parallels variable.go to provide variables and create a platform based on converted config."""

load("//build/bazel/product_variables:constants.bzl", "constants")
load("//prebuilts/clang/host/linux-x86:cc_toolchain_constants.bzl", "variant_name")
load("//build/bazel/platforms/arch/variants:constants.bzl", _arch_constants = "constants")

def _product_variables_providing_rule_impl(ctx):
    return [
        platform_common.TemplateVariableInfo(ctx.attr.product_vars),
    ]

# Provides product variables for templated string replacement.
product_variables_providing_rule = rule(
    implementation = _product_variables_providing_rule_impl,
    attrs = {
        "product_vars": attr.string_dict(),
    },
)

_arch_os_only_suffix = "_arch_os"
_product_only_suffix = "_product"

def add_providing_var(providing_vars, typ, var, value):
    if typ == "bool":
        providing_vars[var] = "1" if value else "0"
    elif typ == "list":
        providing_vars[var] = ",".join(value)
    elif typ == "int":
        providing_vars[var] = str(value)
    elif typ == "string":
        providing_vars[var] = value

def product_variable_config(name, product_config_vars):
    constraints = []

    local_vars = dict(product_config_vars)

    # Native_coverage is not set within soong.variables, but is hardcoded
    # within config.go NewConfig
    local_vars["Native_coverage"] = (
        local_vars.get("ClangCoverage", False) or
        local_vars.get("GcovCoverage", False)
    )

    providing_vars = {}

    # Generate constraints for Soong config variables (bool, value, string typed).
    vendor_vars = local_vars.pop("VendorVars", default = {})
    for (namespace, variables) in vendor_vars.items():
        for (var, value) in variables.items():
            # All vendor vars are Starlark string-typed, even though they may be
            # boxed bools/strings/arbitrary printf'd values, like numbers, so
            # we'll need to do some translation work here by referring to
            # soong_injection's generated data.

            if value == "":
                # Variable is not set so skip adding this as a constraint.
                continue

            # Create the identifier for the constraint var (or select key)
            config_var = namespace + "__" + var

            # List of all soong_config_module_type variables.
            if not config_var in constants.SoongConfigVariables:
                continue

            # Normalize all constraint vars (i.e. select keys) to be lowercased.
            constraint_var = config_var.lower()

            if config_var in constants.SoongConfigBoolVariables:
                constraints.append("//build/bazel/product_variables:" + constraint_var)
            elif config_var in constants.SoongConfigStringVariables:
                # The string value is part of the the select key.
                constraints.append("//build/bazel/product_variables:" + constraint_var + "__" + value.lower())
            elif config_var in constants.SoongConfigValueVariables:
                # For value variables, providing_vars add support for substituting
                # the value using TemplateVariableInfo.
                constraints.append("//build/bazel/product_variables:" + constraint_var)
                add_providing_var(providing_vars, "string", constraint_var, value)

    for (var, value) in local_vars.items():
        # TODO(b/187323817): determine how to handle remaining product
        # variables not used in product_variables
        constraint_var = var.lower()
        if not constants.ProductVariables.get(constraint_var):
            continue

        # variable.go excludes nil values
        add_constraint = (value != None)
        add_providing_var(providing_vars, type(value), var, value)
        if type(value) == "bool":
            # variable.go special cases bools
            add_constraint = value

        if add_constraint:
            constraints.append("//build/bazel/product_variables:" + constraint_var)

    arch_configs = _determine_target_arches_from_config(local_vars)

    # TODO(b/258802089): figure out how to deal with multiple arches for target
    if len(arch_configs) > 0:
        arch = arch_configs[0]
        native.alias(
            name = name,
            actual = "{os}_{arch}{variant}".format(os = "android", arch = arch.arch, variant = _variant_name(arch.arch, arch.arch_variant, arch.cpu_variant)),
        )

    native.platform(
        name = name + _product_only_suffix,
        constraint_values = constraints,
    )

    product_variables_providing_rule(
        name = name + "_product_vars",
        product_vars = providing_vars,
    )

def _is_variant_default(arch, variant):
    return variant == None or variant in (arch, "generic")

def _variant_name(arch, arch_variant, cpu_variant):
    if _is_variant_default(arch, arch_variant):
        arch_variant = ""
    if _is_variant_default(arch, cpu_variant):
        cpu_variant = ""
    variant = struct(
        arch_variant = arch_variant,
        cpu_variant = cpu_variant,
    )
    return variant_name(variant)

def _soong_arch_config_to_struct(soong_arch_config):
    return struct(
        arch = soong_arch_config["arch"],
        arch_variant = soong_arch_config["arch_variant"],
        cpu_variant = soong_arch_config["cpu_variant"],
    )

def android_platform(name = None, constraint_values = [], product = None):
    """ android_platform creates a platform with the specified constraint_values and product constraints."""
    native.platform(
        name = name,
        constraint_values = constraint_values,
        parents = [product + _product_only_suffix],
    )

def _determine_target_arches_from_config(config):
    arches = []

    # ndk_abis and aml_abis explicitly get handled first as they override any setting
    # for DeviceArch, DeviceSecondaryArch in Soong:
    # https://cs.android.com/android/platform/superproject/+/master:build/soong/android/config.go;l=455-468;drc=b45a2ea782074944f79fc388df20b06e01f265f7
    if config.get("Ndk_abis"):
        for arch_config in _arch_constants.ndk_arches:
            arches.append(_soong_arch_config_to_struct(arch_config))
        return arches
    elif config.get("Aml_abis"):
        for arch_config in _arch_constants.aml_arches:
            arches.append(_soong_arch_config_to_struct(arch_config))
        return arches

    arch = config.get("DeviceArch")
    arch_variant = config.get("DeviceArchVariant")
    cpu_variant = config.get("DeviceCpuVariant")

    if not arch:
        # TODO(b/258839711): determine how to better id whether a config is actually host only or we're just missing the target config
        if "DeviceArch" in config:
            fail("No architecture was specified in the product config, expected one of Ndk_abis, Aml_abis, or DeviceArch to be set:\n%s" % config)
        else:
            return arches

    arches.append(struct(
        arch = arch,
        arch_variant = arch_variant,
        cpu_variant = cpu_variant,
    ))

    arch = config.get("DeviceSecondaryArch")
    arch_variant = config.get("DeviceSecondaryArchVariant")
    cpu_variant = config.get("DeviceSecondaryCpuVariant")

    if arch:
        arches.append(struct(
            arch = arch,
            arch_variant = arch_variant,
            cpu_variant = cpu_variant,
        ))
    return arches
