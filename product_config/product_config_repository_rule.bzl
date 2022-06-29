# Copyright (C) 2022 The Android Open Source Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

def _make_vars_to_starlark(txt):
    lines = []
    for l in txt.split('\n'):
        l = l.strip()
        if not l or l.startswith('$'):
            continue
        parts = l.split(':=', 1)
        parts[0] = parts[0].strip().replace('"', '\\"')
        parts[1] = parts[1].strip().replace('"', '\\"')
        lines.append(parts)

    return '''product_config = {
    %s
}
''' % "\n    ".join(['"'+x[0]+'": "'+x[1]+'",' for x in lines])

def _impl(rctx):
    workspace_root = str(rctx.path(Label("//:WORKSPACE")).dirname)
    output_file = rctx.path("out/rbc_variable_dump.txt")

    res = rctx.execute(["mkdir", str(output_file.dirname)])
    if res.return_code != 0:
        fail("mkdir "+str(output_file.dirname)+" failed to run\n"+res.stderr)

    res = rctx.execute([
        'prebuilts/build-tools/linux-x86/bin/ckati',
        '-f',
        'build/make/core/config.mk'
    ], environment={
        "OUT_DIR": str(rctx.path("out")),
        "TMPDIR": str(rctx.path("tmp")),
        "BUILD_DATETIME_FILE": str(rctx.path("out/build_date.txt")),
        "CALLED_FROM_SETUP": 'true',
        "TARGET_PRODUCT": rctx.os.environ.get("TARGET_PRODUCT", "aosp_arm"),
        "TARGET_BUILD_VARIANT": rctx.os.environ.get("TARGET_BUILD_VARIANT", "eng"),
        "RBC_DUMP_CONFIG_FILE": str(output_file),
    }, working_directory = workspace_root)
    if res.return_code != 0:
        fail("ckati -f config.mk failed to run\n"+res.stderr)

    res = rctx.execute(["cat", str(output_file)])
    if res.return_code != 0:
        fail("cat "+str(output_file)+" failed to run\n"+res.stderr)


    rctx.file("product_config.bzl", _make_vars_to_starlark(res.stdout), executable=False)
    exports_files = ("""exports_files([
    %s
])
""" % ",\n    ".join(["\"product_config.bzl\""]))
    rctx.file("BUILD", exports_files, executable=False)

product_config = repository_rule(
    implementation=_impl,
    local=True,
    environ=["TARGET_PRODUCT", "TARGET_BUILD_VARIANT"],
)
