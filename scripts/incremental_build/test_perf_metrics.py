#!/usr/bin/env python3

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

from perf_metrics import _union


def test_union():
  assert _union([], []) == []
  assert _union([1, 1], []) == [1]
  assert _union([], [1, 1]) == [1]
  assert _union([1], [1]) == [1]
  assert _union([1, 2], []) == [1, 2]
  assert _union([1, 2], [2, 1]) == [1, 2]
  assert _union([1, 2], [3, 4]) == [1, 2, 3, 4]
  assert _union([1, 5, 9], [3, 5, 7]) == [1, 5, 9, 3, 7]
