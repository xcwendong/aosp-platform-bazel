# Bazel rules for Android Platform.

This directory contains Starlark extensions for building the Android Platform with Bazel.

## APEX

Run the following commands to build a miminal APEX example.

1. Build host tools with Soong as a workaround.

```
$ m aapt2 apexer apex_compression_tool aprotoc avbtool conv_apex_manifest deapexer dep_fixer e2fsdroid extract_apks jsonmodify make_f2fs merge_zips mke2fs resize2fs sbox sefcontext_compile sload_f2fs soong_javac_wrapper soong_zip symbol_inject zipalign zipsync
```

2. Run Bazel with APEXER_TOOL_PATH pointing to the two directories containing apexer host tool prebuilts, and also the --//build/bazel/rules:enable_apex=True development feature flag.

```
$ b build //build/bazel/examples/apex/minimal:build.bazel.examples.apex.minimal --//build/bazel/rules:enable_apex=True --action_env=APEXER_TOOL_PATH=$HOME/aosp/master/out/soong/host/linux-x86/bin:$HOME/aosp/master/prebuilts/sdk/tools/linux/bin
```

3. Verify the contents of the APEX

```
$ zipinfo bazel-bin/build/bazel/examples/apex/minimal/build.bazel.examples.apex.minimal.apex
```
