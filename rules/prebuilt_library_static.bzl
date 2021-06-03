def prebuilt_library_static(
    name,
    static_library,
    includes = [],
    **kwargs):
    "Bazel macro to correspond with the *_prebuilt_library_static Soong module types"

    # TODO: Handle includes somehow?
    # e.g. includes = ["clang-r416183b/prebuilt_include/llvm/lib/Fuzzer"],
    native.cc_import(
        name=name,
        static_library=static_library,
        **kwargs,
    )

