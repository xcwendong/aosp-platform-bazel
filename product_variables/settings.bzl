"""Macros to generate constraint settings and values for Soong variables."""

load("@bazel_skylib//lib:selects.bzl", "selects")
load("//build/bazel/utils:config_setting_boolean_algebra.bzl", "config_setting_boolean_algebra")
load(":constants.bzl", "constants")

def soong_config_variables(bool_vars, value_vars, string_vars):
    """
    soong_config_variables creates all the constraint values that represent the
    soong config variables. They're then included in the android_product() platform.
    """
    for variable in bool_vars.keys() + value_vars.keys():
        variable = variable.lower()
        native.constraint_setting(
            name = variable + "_constraint",
        )
        native.constraint_value(
            name = variable,
            constraint_setting = variable + "_constraint",
        )

        # We need a "conditions_default" config setting so that we can select on the variable
        # being off, but there being some arch/os constraint in addition. This won't be used
        # directly in build files, but the below combinations of it + and arch will. For example:
        # soong_config_variables: {
        #   my_bool_var: {
        #     conditions_default: {
        #       target: {
        #         android: {
        #           cflags: ["-DFOO"],
        #         },
        #       },
        #     },
        #   },
        # },
        # would become:
        # select({
        #   "//build/bazel/product_variables:my_namespace__my_bool_variable__conditions_default__android": ["-DFOO"],
        #   "//conditions:default": [],
        # })
        # TODO(b/281568854) Update the bp2build converter to emit something like the following instead:
        # select({
        #   "//build/bazel/product_variables:my_namespace__my_bool_variable__android": [],
        #   "//build/bazel/os:android": ["-DFOO"],
        #   "//conditions:default": [],
        # })
        native.alias(
            name = variable + "__conditions_default",
            actual = select({
                ":" + variable: "//build/bazel/utils:always_off_config_setting",
                "//conditions:default": "//build/bazel/utils:always_on_config_setting",
            }),
        )

        # see the comment below about these arch-specific config settings
        for arch, archConstraint in constants.ArchVariantToConstraints.items():
            selects.config_setting_group(
                name = variable + "__" + arch,
                match_all = [
                    ":" + variable,
                    archConstraint,
                ],
            )
            selects.config_setting_group(
                name = variable + "__conditions_default__" + arch,
                match_all = [
                    ":" + variable + "__conditions_default",
                    archConstraint,
                ],
            )

    for variable, choices in string_vars.items():
        native.constraint_setting(
            name = variable + "_constraint",
        )
        for choice in choices:
            var_with_choice = (variable + "__" + choice).lower()
            native.constraint_value(
                name = var_with_choice,
                constraint_setting = variable + "_constraint",
            )

            # These config settings combine the soong config variable with architecture,
            # so that when a user has a build file like:
            # my_soong_config_module {
            #     name: "foo",
            #     target: {
            #         android: {
            #             cflags: ["-DFOO"],
            #         },
            #     },
            #     soong_config_variables: {
            #         my_string_variable: {
            #             value1: {
            #                 cflags: ["-DVALUE1_NOT_ANDROID"],
            #                 target: {
            #                     android: {
            #                         cflags: ["-DVALUE1"],
            #                     },
            #                 },
            #             },
            #             conditions_default: {
            #                 target: {
            #                     android: {
            #                         cflags: ["-DSTRING_VAR_CONDITIONS_DEFAULT"],
            #                     },
            #                 },
            #             },
            #         },
            #     },
            # }
            #
            # We emit something like:
            #
            # cflags = select({
            #     "//build/bazel/platforms/os:android": ["-DFOO"],
            #     "//conditions:default": [],
            # }) + select({
            #     "//build/bazel/product_variables:my_namespace__my_string_variable__value1": ["-DVALUE1_NOT_ANDROID"],
            #     "//conditions:default": [],
            # }) + select({
            #     "//build/bazel/product_variables:my_namespace__my_string_variable__conditions_default__android": ["-DSTRING_VAR_CONDITIONS_DEFAULT"],
            #     "//build/bazel/product_variables:my_namespace__my_string_variable__value1__android": ["-DVALUE1"],
            #     "//conditions:default": [],
            # }),
            for arch, archConstraint in constants.ArchVariantToConstraints.items():
                selects.config_setting_group(
                    name = var_with_choice + "__" + arch,
                    match_all = [
                        ":" + var_with_choice,
                        archConstraint,
                    ],
                )

        # Emit config settings that represent the string setting being off (as in, none of the
        # possible choices), but other arch/os requirements being active.
        for arch, archConstraint in constants.ArchVariantToConstraints.items():
            config_setting_boolean_algebra(
                name = (variable + "__conditions_default__" + arch).lower(),
                expr = {"AND": [
                    archConstraint,
                ] + [
                    {"NOT": ":" + (variable + "__" + choice).lower()}
                    for choice in choices
                ]},
            )
