# Copyright (C) 2022 The Android Open Source Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

PartitionToolchainInfo = provider(
    doc = "Partitions toolchain",
    fields = [
        "build_image",
        "e2fsdroid",
        "mke2fs",
        "mkuserimg_mke2fs",
        "tune2fs",
    ],
)

def _partition_toolchain_impl(ctx):
    toolchain_info = platform_common.ToolchainInfo(
        toolchain_info = PartitionToolchainInfo(
            build_image = ctx.attr.build_image,
            e2fsdroid = ctx.attr.e2fsdroid,
            mke2fs = ctx.attr.mke2fs,
            mkuserimg_mke2fs = ctx.attr.mkuserimg_mke2fs,
            tune2fs = ctx.attr.tune2fs,
        ),
    )
    return [toolchain_info]

partition_toolchain = rule(
    implementation = _partition_toolchain_impl,
    attrs = {
        "build_image": attr.label(cfg = "exec", executable = True, mandatory = True),
        "e2fsdroid": attr.label(cfg = "exec", executable = True, mandatory = True),
        "mke2fs": attr.label(cfg = "exec", executable = True, mandatory = True),
        "mkuserimg_mke2fs": attr.label(cfg = "exec", executable = True, mandatory = True),
        "tune2fs": attr.label(cfg = "exec", executable = True, mandatory = True),
    },
)
