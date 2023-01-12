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
import pytest

from perf_metrics import _get_column_headers


@pytest.mark.parametrize('rows, headers', [
    (['a'], 'a'),
    (['ac', 'bd'], 'abcd'),
    (['abe', 'cde'], 'abcde'),
    (['ab', 'ba'], 'ab'),
    (['ac', 'abc'], 'abc'),
], ids=lambda val: f'[{", ".join(val)}]' if isinstance(val, list) else val)
def test_get_column_headers(rows: list[str], headers: list[str]):
  rows = [{c: None for c in row} for row in rows]
  headers = [c for c in headers]
  assert _get_column_headers(rows, allow_cycles=True) == headers


@pytest.mark.parametrize('rows', [
    ['ab', 'ba'],
    ['abcd', 'db'],
], ids=lambda val: f'[{", ".join(val)}]' if isinstance(val, list) else val)
def test_cycles(rows: list[str]):
  rows = [{c: None for c in row} for row in rows]
  with pytest.raises(ValueError) as e:
    _get_column_headers(rows, allow_cycles=False)
  assert 'event ordering has cycles' in str(e.value)
