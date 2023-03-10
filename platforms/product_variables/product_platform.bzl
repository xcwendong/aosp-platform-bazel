"""Parallels variable.go to provide variables and create a platform based on converted config."""

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

def _is_variant_default(arch, variant):
    return variant == None or variant in (arch, "generic")

def _soong_arch_config_to_struct(soong_arch_config):
    return struct(
        arch = soong_arch_config["arch"],
        arch_variant = soong_arch_config["arch_variant"],
        cpu_variant = soong_arch_config["cpu_variant"],
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

    if _is_variant_default(arch, arch_variant):
        arch_variant = ""
    if _is_variant_default(arch, cpu_variant):
        cpu_variant = ""

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

    if _is_variant_default(arch, arch_variant):
        arch_variant = ""
    if _is_variant_default(arch, cpu_variant):
        cpu_variant = ""

    if arch:
        arches.append(struct(
            arch = arch,
            arch_variant = arch_variant,
            cpu_variant = cpu_variant,
        ))
    return arches

determine_target_arches_from_config = _determine_target_arches_from_config
