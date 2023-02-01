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
import os

import pytest

from util import _next_path_helper
from util import any_match
from util import get_top_dir


@pytest.mark.parametrize('pattern, expected', [
    ('output', 'output-1'),
    ('output.x', 'output-1.x'),
    ('output.x.y', 'output-1.x.y'),
    ('output-1', 'output-2'),
    ('output-9', 'output-10'),
    ('output-10', 'output-11'),
])
def test_next_path_helper(pattern: str, expected: str):
  assert _next_path_helper(pattern) == expected


def test_any_match():
  path, matches = any_match('root.bp')
  assert matches == ['root.bp']
  assert path == get_top_dir().joinpath('build/soong')

  path, matches = any_match('!Android.bp', '!BUILD',
                            'scripts/incremental_build/incremental_build.py')
  assert matches == ['scripts/incremental_build/incremental_build.py']
  assert path == get_top_dir().joinpath('build/bazel')

  path, matches = any_match('BUILD', 'README.md')
  assert matches == ['BUILD', 'README.md']
  assert path.joinpath('BUILD').exists()
  assert path.joinpath('README.md').exists()

  path, matches = any_match('BUILD', '!README.md')
  assert matches == ['BUILD']
  assert path.joinpath('BUILD').exists()
  assert not path.joinpath('README.md').exists()

  path, matches = any_match('!*.bazel', '*')
  assert len(matches) > 0
  children = os.listdir(path)
  assert len(children) > 0
  for child in children:
    assert not child.endswith('.bazel')

  path, matches = any_match('*/BUILD', '*/README.md')
  assert len(matches) > 0
  for m in matches:
    assert path.joinpath(m).exists()

  path, matches = any_match('!**/BUILD', '**/*.cpp')
  assert len(matches) == 1
  assert path.joinpath(matches[0]).exists()
  assert matches[0].endswith('.cpp')
  for _, dirs, files in os.walk(path):
    assert 'BUILD' not in dirs
    assert 'BUILD' not in files
