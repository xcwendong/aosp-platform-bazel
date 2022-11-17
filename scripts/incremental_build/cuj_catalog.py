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

import dataclasses
import enum
import functools
import io
import logging
import shutil
import tempfile
import textwrap
import uuid
from datetime import datetime
from enum import Enum
from pathlib import Path
from typing import Callable
from typing import TypeAlias

import util
from ui import BuildType
from ui import UserInput

"""
Provides some representative CUJs. If you wanted to manually run something but
would like the metrics to be collated in the summary.csv file, use
`perf_metrics.py` as a stand-alone after your build.
"""


class BuildResult(Enum):
  SUCCESS = enum.auto()
  FAILED = enum.auto()
  TEST_FAILURE = enum.auto()


Action: TypeAlias = Callable[[], None]
Verify: TypeAlias = Callable[[UserInput], None]


def trivial_verify(_: UserInput):
  return None


@dataclasses.dataclass
class CujStep:
  verb: str
  """a human-readable description"""
  action: Action
  """user action(s) that are performed prior to a build attempt"""
  verify: Verify = trivial_verify
  """post-build assertions, i.e. tests.
  Should raise `Exception` for failures.
  """


@dataclasses.dataclass(frozen=True)
class CujGroup:
  """A sequence of steps to be performed, such that at the end of all steps the
  initial state of the source tree is attained.
  NO attempt is made to achieve atomicity programmatically.
  It is left as user responsibility.
  """
  description: str
  steps: list[CujStep]

  def __str__(self) -> str:
    if len(self.steps) < 2:
      return f'{self.steps[0].verb} {self.description}'
    steps_str = ' '.join(
        [f'({chr(ord("a") + i)}) {step.verb}' for i, step in
         enumerate(self.steps)])
    return f'{steps_str} {self.description}'


def mtime(p: Path) -> str:
  """stat `p` to provide its Modify timestamp in a log-friendly format"""
  if p.exists():
    ts = datetime.fromtimestamp(p.stat().st_mtime)
    return f'mtime({p.name})= {ts}'
  else:
    return f'{p.name} does not exist'


class InWorkspace(Enum):
  """For a given file in the source tree, the counterpart in the symlink forest
   could be one of these kinds.
  """
  SYMLINK = enum.auto()
  FILE = enum.auto()
  OMISSION = enum.auto()

  @staticmethod
  def ws_counterpart(p: Path) -> Path:
    return util.get_out_dir().joinpath('soong/workspace').joinpath(de_src(p))

  def verify(self, src_path: Path) -> Verify:
    ws_path = InWorkspace.ws_counterpart(src_path)

    def f(user_input: UserInput):
      if user_input.build_type == BuildType.SOONG_ONLY:
        return  # ignore
      if not ws_path.exists():
        actual = InWorkspace.OMISSION
      elif ws_path.is_symlink():
        actual = InWorkspace.SYMLINK
      else:
        actual = InWorkspace.FILE

      if self != actual:
        raise AssertionError(
            f'{ws_path} expected {self.name} but got {actual.name}')

    return f


def de_src(p: Path) -> str:
  return str(p.relative_to(util.get_top_dir()))


def src(p: str) -> Path:
  return util.get_top_dir().joinpath(p)


def modify_revert(file: Path, text: str = None) -> CujGroup:
  """
  :param file: the file to be modified and reverted
  :param text: the text to be appended to the file to modify it
  :return: A pair of CujSteps, where the first modifies the file and the
  second reverts the modification
  """
  if text is None:
    text = f'//BOGUS in {file} {uuid.uuid4()}\n'
  if not file.exists():
    raise RuntimeError(f'{file} does not exist')

  def add_line():
    with open(file, mode="a") as f:
      f.write(text)

  def revert():
    with open(file, mode="rb+") as f:
      # assume UTF-8
      f.seek(-len(text), io.SEEK_END)
      f.truncate()

  return CujGroup(de_src(file), [
      CujStep('modify', add_line),
      CujStep('revert', revert)
  ])


def create_delete(file: Path, ws: InWorkspace, text: str = None) -> CujGroup:
  """
  :param file: the file to be created and deleted
  :param ws: the expectation for the counterpart file in symlink
  forest (aka the synthetic bazel workspace) when its created
  :param text: the content of the file
  :return: A pair of CujSteps, where the fist creates the file and the
  second deletes it
  """
  if text is None:
    text = f'//Test File: safe to delete\n'
  missing_dirs = [f for f in file.parents if not f.exists()]
  shallowest_missing_dir = missing_dirs[-1] if len(missing_dirs) else None

  def create():
    if file.exists():
      raise RuntimeError(
          f'File {file} already exists. Interrupted an earlier run?\n'
          'TIP: `repo status` and revert changes!!!')
    file.parent.mkdir(parents=True, exist_ok=True)
    file.touch(exist_ok=False)
    with open(file, mode="w") as f:
      f.write(text)

  def delete():
    if shallowest_missing_dir:
      shutil.rmtree(shallowest_missing_dir)
    else:
      file.unlink(missing_ok=False)

  return CujGroup(de_src(file), [
      CujStep('create', create, ws.verify(file)),
      CujStep('delete', delete, InWorkspace.OMISSION.verify(file)),
  ])


def create_delete_android_bp(d: Path) -> CujGroup:
  """
  This is basically the same as "create_delete" but with canned content for
  an Android.bp file.
  :param d: The directory to create an Android.bp file at
  """
  # using license module type because it is always bp2build-converted
  license_text = textwrap.dedent(f'''
  license {{
    name: "license-{uuid.uuid4()}",
    license_kinds: ["SPDX-license-identifier-Apache-2.0"]
  }}
  ''')
  return create_delete(d.joinpath('Android.bp'),
                       InWorkspace.SYMLINK,
                       license_text)


def delete_restore(original: Path, ws: InWorkspace) -> CujGroup:
  """
  :param original: The file to be deleted then restored
  :param ws: When restored, expectation for the file's counterpart in the
  symlink forest (aka synthetic bazel workspace)
  :return: A pair of CujSteps, where the first deletes a file and the second
  restores it
  """
  tempdir = Path(tempfile.gettempdir())
  copied = tempdir.joinpath(f'{original.name}-{uuid.uuid4()}.bak')
  if tempdir.is_relative_to(util.get_top_dir()):
    raise SystemExit(f'Temp dir {tempdir} is under source tree')
  if tempdir.is_relative_to(util.get_out_dir()):
    raise SystemExit(f'Temp dir {tempdir} is under '
                     f'OUT dir {util.get_out_dir()}')

  return CujGroup(de_src(original), [
      CujStep('delete',
              lambda: original.rename(copied),
              InWorkspace.OMISSION.verify(original)),
      CujStep('restore',
              lambda: copied.rename(original),
              ws.verify(original))
  ])


def _sequence(a: Verify, b: Verify) -> Verify:
  def f(user_input: UserInput):
    a(user_input)
    b(user_input)

  return f


def _kept_build_file_helper(curated_file: Path, curated_content) -> (
    Verify, Verify):
  ws_file = util.get_out_dir().joinpath('soong/workspace').joinpath(
      curated_file)

  def verify_merged(user_input: UserInput):
    if user_input.build_type == BuildType.SOONG_ONLY:
      return
    with open(ws_file, "r") as f:
      for line in f:
        if line == curated_content:
          return  # found the line
      raise AssertionError(f'{curated_file} not merged in {ws_file}')

  def verify_removed(user_input: UserInput):
    if user_input.build_type == BuildType.SOONG_ONLY:
      return
    if not ws_file.exists():
      return
    with open(ws_file, "r") as f:
      for line in f:
        if line == curated_content:
          raise AssertionError(f'{curated_file} still merged in {ws_file}')

  return verify_merged, verify_removed


def modify_revert_kept_build_file(curated_file: Path) -> CujGroup:
  curated_content = f'//BOGUS in BUILD {uuid.uuid4()}\n'
  cuj_group = modify_revert(curated_file, curated_content)
  (verify_merged, verify_removed) = _kept_build_file_helper(curated_file,
                                                            curated_content)

  modify_step = cuj_group.steps[0]
  revert_step = cuj_group.steps[1]

  modify_step.verify = _sequence(modify_step.verify, verify_merged)
  revert_step.verify = _sequence(revert_step.verify, verify_removed)
  return cuj_group


def create_delete_kept_build_file(curated_file: Path) -> CujGroup:
  curated_content = f'//BOGUS {uuid.uuid4()}\n'
  package_dir_build_file: CujGroup = create_delete(curated_file,
                                                   InWorkspace.FILE,
                                                   curated_content)
  (verify_merged, verify_removed) = _kept_build_file_helper(curated_file,
                                                            curated_content)

  create_step: CujStep = package_dir_build_file.steps[0]
  delete_step: CujStep = package_dir_build_file.steps[1]

  create_step.verify = _sequence(create_step.verify, verify_merged)
  delete_step.verify = _sequence(delete_step.verify, verify_removed)

  return package_dir_build_file


NON_LEAF = '*/*'
"""If `a/*/*` is a valid path `a` is not a leaf directory"""
LEAF = '!*/*'
"""If `a/*/*` is not a valid path `a` is a leaf directory, i.e. has no other
non-empty sub-directories"""
PKG = ['Android.bp', '!BUILD', '!BUILD.bazel']
"""limiting the candidate to Android.bp file with no sibling bazel files"""
PKG_FREE = ['!**/Android.bp', '!**/BUILD', '!**/BUILD.bazel']
"""no Android.bp or BUILD or BUILD.bazel file anywhere"""


@functools.cache
def get_cujgroups() -> list[CujGroup]:
  # we are choosing "package" directories that have Android.bp but
  # not BUILD nor BUILD.bazel because
  # we can't tell if ShouldKeepExistingBuildFile would be True or not
  pkg, p_why = util.any_match(NON_LEAF, *PKG)
  leaf_pkg, lp_why = util.any_match(LEAF, *PKG)
  pkg_free, f_why = util.any_match(NON_LEAF, *PKG_FREE)
  leaf_pkg_free, _ = util.any_match(LEAF, *PKG_FREE)
  ancestor, a_why = util.any_match('!Android.bp', '!BUILD', '!BUILD.bazel',
                                   '**/Android.bp')
  logging.info(textwrap.dedent(f'''Choosing:
            package: {de_src(pkg)} has {p_why}
   package ancestor: {de_src(ancestor)} has {a_why} but no direct Android.bp
       package free: {de_src(pkg_free)} has {f_why} but no Android.bp anywhere
       leaf package: {de_src(leaf_pkg)} has {lp_why} but no sub-dirs
  leaf package free: {de_src(leaf_pkg_free)} has neither Android.bp nor sub-dirs
  '''))
  return [
      CujGroup('', [CujStep('no change', lambda: None)]),

      modify_revert(src('bionic/libc/tzcode/asctime.c')),
      modify_revert(src('bionic/libc/stdio/stdio.cpp')),
      modify_revert(src('packages/modules/adb/daemon/main.cpp')),
      modify_revert(src('frameworks/base/core/java/android/view/View.java')),

      *[create_delete(d.joinpath('unreferenced/t.txt'), InWorkspace.FILE) for
        d in [
            pkg,
            ancestor,
            pkg_free,
            leaf_pkg,
            leaf_pkg_free
        ]],

      *[create_delete(d.joinpath('unreferenced.txt'), InWorkspace.SYMLINK) for
        d in [
            ancestor,
            pkg,
            leaf_pkg,
        ]],
      *[create_delete(d.joinpath('unreferenced.txt'), InWorkspace.FILE) for d
        in [
            pkg_free,
            leaf_pkg_free
        ]],

      create_delete(src('bionic/libc/tzcode/globbed.c'), InWorkspace.FILE),

      *[delete_restore(f, InWorkspace.SYMLINK) for f in [
          util.any_file('version_script.txt'),
          util.any_file('AndroidManifest.xml')]],
      # TODO (usta): find targets that should be affected

      modify_revert(src('Android.bp')),

      *[create_delete_android_bp(d) for d in
        [ancestor, pkg_free, leaf_pkg_free]],

      *[create_delete(d.joinpath('BUILD.bazel'), InWorkspace.OMISSION) for d in
        [
            ancestor,
            pkg_free,
            leaf_pkg_free
        ]],
      # for pkg and leaf_pkg, BUILD.bazel will be created
      # but BUILD will be either merged or ignored
      *[create_delete(d.joinpath('BUILD'), InWorkspace.OMISSION) for d in [
          pkg,
          leaf_pkg,
      ]],

      # external/guava Bp2BuildKeepExistingBuildFile set True(recursive)
      create_delete_kept_build_file(
          util.any_dir_under(src('external/guava'), '!BUILD', '!BUILD.bazel')
            .joinpath('BUILD')),
      modify_revert_kept_build_file(
          util.any_file_under(src('external/guava'), 'BUILD')),
      # bionic doesn't have Bp2BuildKeepExistingBuildFile set True
      modify_revert(util.any_file_under(src('bionic'), 'BUILD')),

      # TODO(usta): add a file and then replace it with a directory
      # TODO(usta): add a dangling symlink
  ]
