#!/bin/bash

# TODO: Refactor build/make/envsetup.sh to make gettop() available elsewhere
function gettop
{
    local TOPFILE=build/make/core/envsetup.mk
    if [ -n "$TOP" -a -f "$TOP/$TOPFILE" ] ; then
        # The following circumlocution ensures we remove symlinks from TOP.
        (cd "$TOP"; PWD= /bin/pwd)
    else
        if [ -f $TOPFILE ] ; then
            # The following circumlocution (repeated below as well) ensures
            # that we record the true directory name and not one that is
            # faked up with symlink names.
            PWD= /bin/pwd
        else
            local HERE=$PWD
            local T=
            while [ \( ! \( -f $TOPFILE \) \) -a \( "$PWD" != "/" \) ]; do
                \cd ..
                T=`PWD= /bin/pwd -P`
            done
            \cd "$HERE"
            if [ -f "$T/$TOPFILE" ]; then
                echo "$T"
            fi
        fi
    fi
}

T="$(gettop)"
if [ ! "$T" ]; then
    echo "Couldn't locate the top of the tree.  Try setting TOP."
    return
fi

case $(uname -s) in
    Darwin)
        ANDROID_BAZEL_PATH="${T}/prebuilts/bazel/darwin-x86_64/bazel"
        ANDROID_BAZELRC_PATH="${T}/build/bazel/darwin.bazelrc"
        ANDROID_BAZEL_JDK_PATH="${T}/prebuilts/jdk/jdk11/darwin-x86"
        ;;
    Linux)
        ANDROID_BAZEL_PATH="${T}/prebuilts/bazel/linux-x86_64/bazel"
        ANDROID_BAZELRC_PATH="${T}/build/bazel/linux.bazelrc"
        ANDROID_BAZEL_JDK_PATH="${T}/prebuilts/jdk/jdk11/linux-x86"
        ;;
    *)
        ANDROID_BAZEL_PATH=
        ANDROID_BAZELRC_PATH=
        ANDROID_BAZEL_JDK_PATH=
        ;;
esac

if [ -n "$ANDROID_BAZEL_PATH" -a -f "$ANDROID_BAZEL_PATH" ]; then
    export ANDROID_BAZEL_PATH
else
    echo "Couldn't locate Bazel binary"
    return
fi

if [ -n "$ANDROID_BAZELRC_PATH" -a -f "$ANDROID_BAZELRC_PATH" ]; then
    export ANDROID_BAZELRC_PATH
else
    echo "Couldn't locate bazelrc file for Bazel"
    return
fi

if [ -n "$ANDROID_BAZEL_JDK_PATH" -a -d "$ANDROID_BAZEL_JDK_PATH" ]; then
    export ANDROID_BAZEL_JDK_PATH
else
    echo "Couldn't locate JDK to use for Bazel"
    return
fi

echo "WARNING: Bazel support for the Android Platform is experimental and is undergoing development."
echo "WARNING: Currently, build stability is not guaranteed. Thank you."
echo

"${ANDROID_BAZEL_PATH}" --server_javabase="${ANDROID_BAZEL_JDK_PATH}" --bazelrc="${ANDROID_BAZELRC_PATH}" "$@"
