# Copyright (C) 2023 The Android Open Source Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http:#www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""Macro wrapping the java_library for bp2build. """

load(
    "@rules_java//java:defs.bzl",
    _java_library = "java_library",
)

def java_library(name = "", srcs = [], deps = [], javacopts = [], **kwargs):
    # Disable the error prone check of HashtableContains by default. See https://errorprone.info/bugpattern/HashtableContains
    # HashtableContains error is reported when compiling //external/bouncycastle:bouncycastle-bcpkix-unbundled
    opts = ["-Xep:HashtableContains:OFF"] + javacopts

    _java_library(name = name, srcs = srcs, deps = deps, javacopts = opts, **kwargs)
