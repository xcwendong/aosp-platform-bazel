package(default_visibility = ["//visibility:public"])

# The current product we're building for.
# We could've chosen this product via a --platforms flag,
# or transitioned into it. This is used to select() on
# the current product. Note that this represents the current
# android _product_ as defined in pre-bazel terms.
# There are several bazel platforms that can resolve to
# the same product, for example the host platform and the
# device platform.
constraint_setting(name = "current_product")

alias(
    name = "product_vars",
    actual = "@soong_injection//product_config_platforms:product_vars",
)
