import dataclasses
import functools
import io
import logging
import os
import shutil
import sys
from datetime import datetime
from pathlib import Path
from typing import Callable
from typing import Final


@dataclasses.dataclass(frozen=True)
class CujStep:
  description: str
  action: Callable[[], None]
  test: Callable[[], bool] = lambda: True


@dataclasses.dataclass(frozen=True)
class CujGroup:
  """
  A sequence of steps to be performed all or none.
  NO attempt is made to achieve atomicity, it's user responsibility.
  """
  description: str
  steps: list[CujStep]

  def __str__(self) -> str:
    if len(self.steps) < 2:
      return f'{self.description}: {self.steps[0].description}'
    steps_str = ' '.join(
        [f'({chr(ord("a") + i)}) {step.description}' for i, step in
         enumerate(self.steps)])
    return f'{self.description}:  {steps_str}'


INDICATOR_FILE: Final[str] = 'build/soong/soong_ui.bash'


@functools.cache
def get_top_dir(d: Path = Path('.').absolute()) -> Path:
  """Get the path to the root of the Android source tree"""
  logging.debug('Checking if Android source tree root is %s', d)
  if d.parent == d:
    sys.exit('Unable to find ROOT source directory, specifically,'
             f'{INDICATOR_FILE} not found anywhere. '
             'Try `m nothing` and `repo sync`')
  if d.joinpath(INDICATOR_FILE).is_file():
    logging.info('Android source tree root = %s', d)
    return d
  return get_top_dir(d.parent)


@functools.cache
def get_out_dir() -> Path:
  out_dir = os.environ.get('OUT_DIR')
  return Path(out_dir) if out_dir else get_top_dir().joinpath('out')


def mtime(p: Path) -> str:
  """stat `p` to provide its Modify timestamp in a log-friendly format"""
  if p.exists():
    ts = datetime.fromtimestamp(p.stat().st_mtime)
    return f'mtime({p.name})= {ts}'
  else:
    return f'{p.name} does not exist'


def touch_file(p: Path, parents: bool = False):
  """
  Used as an approximation for file edits in CUJs.
  This works because Ninja determines freshness based on Modify timestamp.
  :param p: file to be `touch`-ed
  :param parents: if true, create the parent directories as needed
  """

  if not p.parent.exists():
    if parents:
      p.parent.mkdir(parents=True, exist_ok=True)
    else:
      raise SystemExit(f'Directory does not exist: {p.parent}')
  logging.debug('before:' + mtime(p))
  p.touch()
  logging.debug(' after:' + mtime(p))


@functools.cache
# add new Android.bp with missing source file and then added
# add a globbed src bp2build-ed module
def get_cujgroups() -> list[CujGroup]:
  def touch(p: str) -> CujStep:
    file = get_top_dir().joinpath(p)
    return CujStep('touch', lambda: touch_file(file))

  def create_and_delete(p: str, content: str) -> CujGroup:
    file = Path(p)
    if file.is_absolute():
      raise SystemExit(f'expected relative paths: {p}')
    file = get_top_dir().joinpath(file)
    missing_dirs = [f for f in file.parents if
                    not f.exists() and f.relative_to(get_top_dir())]
    shallowest_missing_dir = missing_dirs[-1] if len(missing_dirs) else None

    def create():
      if file.exists():
        raise SystemExit(
            f'File {p} already exists. Interrupted an earlier run?\n'
            f'TIP: `repo status` and revert changes!!!')
      touch_file(file, parents=True)
      with open(file, mode="w") as f:
        f.write(content)

    def delete():
      if shallowest_missing_dir:
        shutil.rmtree(shallowest_missing_dir)
      else:
        file.unlink(missing_ok=False)

    return CujGroup(description=p,
                    steps=[
                        CujStep('create', create),
                        CujStep('delete', delete)
                    ])

  def touch_delete_restore(p: str) -> CujGroup:
    original = get_top_dir().joinpath(p)
    copied = get_out_dir().joinpath(f'{original.name}.bak')

    return CujGroup(
        description=p,
        steps=[
            CujStep('touch', lambda: touch_file(original)),
            CujStep('delete', lambda: original.rename(copied)),
            CujStep('restore', lambda: copied.rename(original))
        ])

  def build_bazel_merger(file: str) -> CujGroup:
    existing = get_top_dir().joinpath(file)
    merged = get_out_dir().joinpath('soong/workspace').joinpath(file)
    bogus: Final[str] = f'//BOGUS this line added by {__file__} ' \
                        f'for testing on {datetime.now()}\n'

    def add_line():
      with open(existing, mode="a") as ef:
        ef.write(bogus)

    def revert():
      with open(existing, mode="rb+") as ef:
        #  assume UTF-8
        ef.seek(-len(bogus), io.SEEK_END)
        ef.truncate()

    def verify() -> bool:
      with open(existing, mode="rb") as ef:
        with open(merged, mode="rb") as mf:
          size = os.stat(existing).st_size
          mf.seek(-size, io.SEEK_END)
          while ef.tell() != size:
            l1 = mf.readline()
            l2 = ef.readline()
            if l1 != l2:
              return False
      return True

    return CujGroup(
        description=file,
        steps=[
            CujStep('modify', add_line, verify),
            CujStep('revert', revert, verify),
        ])

  dir_with_subpackage = 'bionic'
  package_dir = 'bionic/libc'
  dir_without_subpackage = 'bionic/libc/bionic'
  return [
      CujGroup('initial build', [CujStep('no-op', lambda: None)]),

      CujGroup('globbed bionic/libc/tzcode/asctime.c',
               [touch('bionic/libc/tzcode/asctime.c')]),
      CujGroup('stdio.cpp', [touch('bionic/libc/stdio/stdio.cpp')]),
      CujGroup('adbd', [touch('packages/modules/adb/daemon/main.cpp')]),
      CujGroup('View.java',
               [touch('frameworks/base/core/java/android/view/View.java')]),

      *[create_and_delete(
          f'{d}/unreferenced/test.txt',
          'safe to delete') for d in
          [package_dir, dir_without_subpackage, dir_with_subpackage]],
      *[create_and_delete(
          f'{d}/unreferenced.txt',
          'safe to delete') for d in
          [package_dir, dir_without_subpackage, dir_with_subpackage]],
      create_and_delete('bionic/libc/tzcode/globbed.c',
                        '// safe to delete'),

      *[touch_delete_restore(f) for f in [
          f'{package_dir}/version_script.txt',
          'art/artd/tests/AndroidManifest.xml']],

      CujGroup('root bp', [touch('Android.bp')]),

      *[create_and_delete(
          f'{d}/Android.bp',
          '//safe to delete') for d in
          [dir_with_subpackage, dir_without_subpackage]],

      *[create_and_delete(
          f'{d}/BUILD.bazel',
          '//safe to delete') for d in
          [package_dir, dir_with_subpackage, dir_without_subpackage]],

      build_bazel_merger('external/protobuf/BUILD.bazel'),

      touch_delete_restore(f'{package_dir}/BUILD'),
  ]
