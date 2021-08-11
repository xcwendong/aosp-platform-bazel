# A repository rule to run soong_ui --make-mode to provide the Bazel standalone
# build with prebuilts from Make/Soong that Bazel can't build yet.
def _impl(rctx):
    modules = rctx.attr.modules

    build_dir = rctx.path(Label("//:WORKSPACE")).dirname
    soong_ui_bash = str(build_dir) + "/build/soong/soong_ui.bash"
    args = [
        soong_ui_bash,
        "--make-mode",
        "--skip-soong-tests",
    ]
    args += modules

    rctx.report_progress("Building host tools with Soong: %s" % str(modules))
    out_dir = str(build_dir.dirname) + "/make_injection"
    exec_result = rctx.execute(args, environment = {"OUT_DIR": out_dir})
    if exec_result.return_code != 0:
        fail(exec_result.stdout)
        fail(exec_result.stderr)

    # Symlink host binaries. This can be extended to other types of prebuilt outputs from Make.
    rctx.symlink(out_dir + "/host/linux-x86", "host/linux-x86")
    rctx.file("BUILD", """exports_files(glob(["host/linux-x86/**/*"]))""")

make_injection_repository = repository_rule(
    implementation = _impl,
    attrs = {
        "modules": attr.string_list(mandatory = True, default = []),
    },
)
