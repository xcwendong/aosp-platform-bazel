# Copyright (C) 2023 The Android Open Source Project
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
import argparse
import dataclasses
import functools
import logging
import re
import shutil
import uuid
from pathlib import Path
from typing import Final

import util
from cuj import CujGroup
from cuj import CujStep
from cuj import src

_ALLOWLISTS = 'build/soong/android/allowlists/allowlists.go'


@dataclasses.dataclass
class GoList:
  lines: list[str]
  begin: int = -1
  end: int = -1

  def has_module(self, module: str) -> bool:
    for i in range(self.begin, self.end):
      if f'"{module}"' in self.lines[i]:
        return True
    return False

  def insert_clones(self, module: str, count: int):
    clones = [f'\t\t"{module}-{i + 1}",\n' for i in range(0, count)]
    self.lines = self.lines[0:self.begin] + clones + self.lines[self.begin:]
    self.end += count

  def locate(self, listname: str):
    start = re.compile(r'^\s*{l}\s=\s*\[]string\{{\s*$'.format(l=listname))
    self.begin = -1
    for i, line in enumerate(self.lines):
      if self.begin == -1 and start.match(line):
        self.begin = i + 1
      elif self.begin != -1 and line.strip() == '}':
        self.end = i
        return
    raise RuntimeError(f'{listname} not found')


def _allowlist(module: str, count: int):
  """Add clones of `module` to bazel enabled allow lists"""
  with open(src(_ALLOWLISTS), "r+") as file:
    golist = GoList(file.readlines())
    golist.locate('ProdMixedBuildsEnabledList')
    golist.insert_clones(module, count)
    golist.locate('Bp2buildModuleAlwaysConvertList')
    if golist.has_module(module):
      golist.insert_clones(module, count)

    file.seek(0)
    file.writelines(golist.lines)


def _clone(androidbp: Path, module: str, count: int):
  """
  In the given Android.bp file, find the `module` and make `count` copies
  which are identical except for their names that are '{module}-{i}'
  for i=1 to `count`
  """
  name_pattern = re.compile(
      r'^(?P<prefix>\s*name:\s*"){mod}(?P<suffix>",?)$'.format(mod=module))
  # we'll assume that the Android.bp file is properly formatted,
  # specifically, for any module definition:
  # 1. its first line matches `start_pattern` and
  # 2. its last line matches a closing curly brace, i.e. '}'
  start_pattern = re.compile(
      r'^(?P<module_type>\w+)\s*\{\s*$')  # e.g. `cc_library {`
  nameline: int = -1
  with open(androidbp, 'r+') as f:
    buffer: list[str] = []
    for line in f:
      if start_pattern.match(line):
        buffer = [line]
      elif line.rstrip() == '}':
        if nameline != -1:
          buffer.append('}')
          break
        else:
          buffer.clear()
      else:
        if nameline == -1:
          found = name_pattern.match(line) is not None
          if not found:
            buffer.clear()
          else:
            nameline = len(buffer)
        if len(buffer):
          # buffer would be empty if a module definition has not started
          # or the module definition didn't name-match
          buffer.append(line)

    if nameline == -1:
      raise RuntimeError(f'Couldn\'t find {module} in {androidbp}')

    f.seek(0, 2)  # go to the end of the file
    for i in range(1, count + 1):
      for j, line in enumerate(buffer):
        if j == nameline:
          line = re.sub(name_pattern, f'\\g<prefix>{module}-{i}\\g<suffix>',
                        line)
        f.write(line)
      f.write('\n')


def clone_and_bazel_enable(androidbp: Path, module: str, count: int):
  _allowlist(module, count)
  _clone(androidbp, module, count)


def get_cuj_group(androidbp: Path, module: str) -> CujGroup:
  marker = uuid.uuid4()
  androidbp_bak: Final[Path] = util.get_out_dir().joinpath(
      f'android.bp.{marker}')
  allowlist_bak: Final[Path] = util.get_out_dir().joinpath(
      f'allowlists.go.{marker}')

  def helper(count: int):
    if not androidbp_bak.exists():
      assert not allowlist_bak.exists()
      # if first cuj_step then back up files to restore later
      shutil.copy(androidbp, androidbp_bak)
      shutil.copy(src(_ALLOWLISTS), allowlist_bak)
    else:
      shutil.copy(androidbp_bak, androidbp)
      shutil.copy(allowlist_bak, src(_ALLOWLISTS))
    clone_and_bazel_enable(androidbp, module, count)

  def revert():
    shutil.move(androidbp_bak, androidbp)
    shutil.move(allowlist_bak, src(_ALLOWLISTS))

  counts: Final[list[int]] = [1, 500, 1000, 5000, 10_000, 15_000]
  steps = [CujStep(verb=str(count),
                   apply_change=functools.partial(helper, count))
           for count in counts]
  steps.append(CujStep(verb='0', apply_change=revert))
  return CujGroup(f'clone-{module}', steps)


def main():
  """
  provided only for manual run;
  use incremental_build.sh to invoke the cuj instead
  """
  p = argparse.ArgumentParser()
  p.add_argument('--module', '-m', default='adbd',
                 help='name of the module to clone; default=%(default)s')
  p.add_argument('--count', '-n', default=100, type=int,
                 help='number of times to clone; default: %(default)s')
  adb_bp = util.get_top_dir().joinpath('packages/modules/adb/Android.bp')
  p.add_argument('androidbp', nargs='?', default=adb_bp, type=Path,
                 help='absolute path to Android.bp file; default=%(default)s')
  options = p.parse_args()
  clone_and_bazel_enable(options.androidbp, options.module, options.count)
  logging.warning('Changes made to your source tree; TIP: `repo status`')


if __name__ == '__main__':
  logging.root.setLevel(logging.INFO)
  main()
