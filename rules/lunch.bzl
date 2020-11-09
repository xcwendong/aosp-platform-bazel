_CAPTURED_ENV_VARS = [
    "PWD",
    "TARGET_PRODUCT",
    "TARGET_BUILD_VARIANT",
    "ABSOLUTE_OUT_DIR",
]

_ALLOWED_SPECIAL_CHARACTERS = [
    "/",
    "_",
    "-",
    "'",
]

# Since we write the env var value literally into a .bzl file, ensure that the string
# does not contain special characters like '"', '\n' and '\'. Use an allowlist approach
# and check that the remaining string is alphanumeric.
def _validate_env_value(env_var, env_value):
    if env_value == None:
        fail("The env var " + env_var + " is not defined.")

    for allowed_char in _ALLOWED_SPECIAL_CHARACTERS:
        env_value = env_value.replace(allowed_char, "")
    if not env_value.isalnum():
        fail("The value of " +
             env_var +
             " can only consist of alphanumeric and " +
             _ALLOWED_SPECIAL_CHARACTERS +
             " characters: " +
             str(env_value))

def _lunch_impl(rctx):

    env_vars = {}
    for env_var in _CAPTURED_ENV_VARS:
        env_value = rctx.os.environ.get(env_var)
        _validate_env_value(env_var, env_value)
        env_vars[env_var] = env_value

    out_dir = env_vars["ABSOLUTE_OUT_DIR"]
    ret = rctx.execute(["ls"], working_directory = out_dir)
    if ret.return_code != 0:
        fail("Unable to list files in the output directory: %s: %s" % (out_dir, ret.stderr))
    # TODO(b/172775644): This doesn't work with Kati suffixes that
    # are md5 hashed when the original suffix is longer than 64
    # characters.
    # https://cs.android.com/android/platform/superproject/+/master:build/soong/ui/build/kati.go;l=46-57;drc=ce679d29ec735058a0f655cd2dc5948dd521dd5c
    ninja_file_prefix = "build-" + env_vars["TARGET_PRODUCT"]
    combined_ninja_file_prefix = "combined-" + env_vars["TARGET_PRODUCT"]
    for f in ret.stdout.split("\n"):
        if f.startswith(ninja_file_prefix):
            if f.endswith("cleanspec.ninja"):
                # Bazel doesn't need cleanspec.
                continue
            elif f.endswith("package.ninja"):
                package_ninja = f
            elif f.endswith(".ninja"):
                kati_ninja = f
            else:
                continue
        elif f.startswith(combined_ninja_file_prefix) and f.endswith(".ninja"):
            combined_ninja = f

    if package_ninja == None:
        fail("Could not find package.ninja")
    elif kati_ninja == None:
        fail("Could not find Kati-generated .ninja")
    elif combined_ninja == None:
        fail("Could not find combined .ninja")

    env_vars["COMBINED_NINJA"] = combined_ninja
    env_vars["PACKAGE_NINJA"] = package_ninja
    env_vars["KATI_NINJA"] = kati_ninja

    rctx.file("BUILD.bazel", """
exports_files(["env.bzl"])
""")

    # Re-export captured environment variables in a .bzl file.
    rctx.file("env.bzl", "\n".join([
        item[0] + " = \"" + str(item[1]) + "\""
        for item in env_vars.items()
    ]))

_lunch = repository_rule(
    implementation = _lunch_impl,
    configure = True,
    environ = _CAPTURED_ENV_VARS,
    doc = "A repository rule to capture environment variables based on the lunch choice.",
)

def lunch():
    # Hardcode repository name to @lunch.
    _lunch(name = "lunch")
