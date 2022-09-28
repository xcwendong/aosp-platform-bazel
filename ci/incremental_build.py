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

"""
A tool for running builds (soong or b) and measuring the time taken.
"""

import argparse
import csv
import dataclasses
import datetime
import functools
import logging
import os
import re
import shutil
import subprocess
import sys
import textwrap
import time
from pathlib import Path
from typing import Callable
from typing import Final
from typing import Mapping

INDICATOR_FILE: Final[str] = 'build/soong/soong_ui.bash'
"""This file path is relative to the source tree root"""

repeat_count: int
"""Repeating a build should be a no-op but that has not been the case.
This instructs a build to be repeated such that we can detect anomalies"""

log_dir: Path


@functools.cache
def get_top(d: Path = Path('.').absolute()) -> Path:
  """Get the path to the root of the Android source tree"""
  logging.debug('Checking if Android source tree root is %s', d)
  if d.parent == d:
    raise RuntimeError('Unable to find ROOT source directory')
  if d.joinpath(INDICATOR_FILE).is_file():
    logging.info('Android source tree root = %s', d)
    return d
  return get_top(d.parent)


def repeat(fn: Callable[[...], None]):
  """a decorator to repeat a function"""

  @functools.wraps(fn)
  def wrapped(*args, **kwargs):
    for i in range(0, 1 + repeat_count):
      if i > 0:
        logging.info('Repetition #%d for %s', i, fn.__name__)
      fn(*args, **kwargs)

  return wrapped


@dataclasses.dataclass(frozen=True)
class Cuj:
  name: str
  do_hook: Callable[[], None]
  undo_hook: Callable[[], None]


def count_explanations(process_log_file: Path) -> int:
  explanations = 0
  pattern = re.compile(
      r'^ninja explain:(?! edge with output .* is a phony output,'
      r' so is always dirty$)')
  with open(process_log_file) as f:
    for line in f:
      if pattern.match(line):
        explanations += 1
  return explanations


@repeat
def build(
    options: argparse.Namespace,
    cuj_name: str,
    allow_dry_run: bool
):
  """
  Builds (using soong or b as appropriate) the provided `targets`.
  `log_file_gen` gives a file to direct stdout and stdin to.
  `allow_dry_run` is useful when we are primarily interested in ninja
  explanations - however, the "resetting runs" should always disallow dry runs.
  """
  ninja_args = os.environ.get('NINJA_ARGS') or ''
  if ninja_args != '':
    ninja_args += ' '
  ninja_args += '-d explain --quiet'

  pattern = re.compile(r'(?:^|\s)-n\b')
  if not allow_dry_run and pattern.search(ninja_args):
    logging.warning('ignoring "-n"')
    ninja_args = pattern.sub('', ninja_args)

  targets: Final[list[str]] = options.targets
  is_bazel = targets[0].startswith('//')
  cmd = ('source build/envsetup.sh && b build' if is_bazel else
         'build/soong/soong_ui.bash --make-mode --skip-soong-tests')
  cmd += ' '
  if options.bazel_mode_dev:
    cmd += '--bazel-mode-dev '
  if options.bazel_mode:
    cmd += '--bazel-mode'
  cmd += ' '.join(targets)
  overrides: Mapping[str, str] = {'NINJA_ARGS': ninja_args,
                                  'TARGET_BUILD_VARIANT': 'userdebug',
                                  'TARGET_PRODUCT': 'aosp_arm64'
                                  }
  env: Mapping[str, str] = {**os.environ, **overrides}
  process_log_file = get_log_file(cuj_name)
  with open(process_log_file, 'w') as f:
    logging.info('see %s', process_log_file)
    f.write(datetime.datetime.now().strftime('%m/%d/%Y %H:%M:%s\n'))
    f.write(f'Running:{cmd}\n')
    env_for_logging = [f'{k}={v}' for (k, v) in env.items()]
    env_for_logging.sort()
    env_string = '\n  '.join(env_for_logging)
    f.write(f'Environment Variables:\n  {env_string}\n\n\n')
    start = time.perf_counter()
    p = subprocess.run(cmd,
                       check=False,
                       cwd=get_top(),
                       env=env,
                       text=True,
                       shell=True,
                       stdout=f,
                       stderr=f)
    elapsed = datetime.timedelta(seconds=time.perf_counter() - start)
  # TODO(usta): `shell=False` when build/envsetup.sh needn't be sourced for `b`

  if p.returncode != 0:
    raise SystemExit(
        f'subprocess yielded {p.returncode} see {process_log_file}')

  build_type: str
  if is_bazel:
    build_type = 'b'
  elif options.bazel_mode_dev:
    build_type = 'mixed dev'
  elif options.bazel_mode:
    build_type = 'mixed'
  else:
    build_type = 'soong'

  summary = {
      'logfile': process_log_file.name,
      'build type': build_type,
      'targets': ' '.join(targets),
      'time': elapsed,
      'explanations': count_explanations(process_log_file)}
  with open(log_dir.joinpath('summary.csv'), 'a') as stream:
    writer = csv.DictWriter(stream, fieldnames=summary.keys())
    if stream.tell() == 0:  # file's empty
      writer.writeheader()
    writer.writerow(summary)


def touch(p: Path, parents: bool = False):
  def mtime():
    logging.debug('mtime(%s)= %s', p,
                  datetime.datetime.fromtimestamp(p.stat().st_mtime))

  if not p.parent.exists():
    if parents:
      p.parent.mkdir(parents=True, exist_ok=True)
    else:
      raise SystemExit(f'Directory does not exist: {p.parent}')
  if p.exists():
    mtime()
  p.touch()
  mtime()


def create_c_file(f: Path, parents: bool = False):
  touch(f, parents)
  with open(f, 'w') as f:
    f.write('''
#include <stdio.h>
int main(){
  printf("Hello World");
  return 0;
}
''')


def validate_int_in_range(lo: int, hi: int) -> Callable[[str], int]:
  def validate(i: str) -> int:
    if lo <= int(i) <= hi:
      return int(i)
    raise argparse.ArgumentError(argument=None,
                                 message=f'Invalid argument: {i},'
                                         f'expected {min} <= {i} <= {max}')

  return validate


class ValidateTargets(argparse.Action):
  """Ensures targets are either all soong or all bazel and not intermingled"""

  def __call__(self, parser, namespace, values, option_string=None):
    bazel_labels = [target for target
                    in values if re.match(r'^//', target)]
    if 0 < len(bazel_labels) < len(values):
      raise argparse.ArgumentError(
          argument=None,
          message=f'Dont mix bazel labels with soong targets: {bazel_labels}')
    setattr(namespace, self.dest, values)


@functools.cache
def get_out_dir() -> Path:
  out_dir = os.environ.get('OUT_DIR')
  return Path(out_dir) if out_dir else get_top().joinpath('out')


def get_log_file(cuj_name: str, suffix: int = 0) -> Path:
  """
  Creates a file for logging output for the given cuj_name. A numeric
  subscript is appended to the filename to distinguish different runs.
  """
  f = log_dir.joinpath(f'{cuj_name.replace(" ", "_")}_{suffix}.log')
  f.parent.mkdir(parents=True, exist_ok=True)
  if f.exists():
    return get_log_file(cuj_name, suffix + 1)
  f.touch(exist_ok=False)
  return f


@functools.cache
def get_cujs() -> list[Cuj]:
  def noop():
    logging.debug('do nothing')

  unreferenced = get_top().joinpath(
      'bionic/libc/arch-common/bionic/unreferenced-test-file.c')
  unreferenced_in_unreferenced = get_top().joinpath(
      'unreferenced/unreferenced-test-file.c')
  return [Cuj('noop', noop, noop), Cuj(
      'touch root Android.bp',
      do_hook=lambda: touch(get_top().joinpath('Android.bp')),
      undo_hook=noop
  ), Cuj(
      'new empty Android.bp',
      do_hook=lambda: touch(get_top().joinpath('some_directory/Android.bp'),
                            parents=True),
      undo_hook=lambda: shutil.rmtree(get_top().joinpath('some_directory'))
  ), Cuj(
      'new unreferenced c file',
      do_hook=lambda: create_c_file(unreferenced),
      undo_hook=unreferenced.unlink
  ), Cuj(
      'new unreferenced c file in unreferenced dir',
      do_hook=lambda: create_c_file(unreferenced_in_unreferenced, parents=True),
      undo_hook=unreferenced_in_unreferenced.unlink
  ), Cuj(
      'touch AndroidManifest.xml',
      do_hook=lambda: touch(
          get_top().joinpath('packages/apps/DevCamera/AndroidManifest.xml')),
      undo_hook=noop
  )]


def get_user_input(cujs: list[Cuj]) -> argparse.Namespace:
  p = argparse.ArgumentParser(
      formatter_class=argparse.RawTextHelpFormatter,
      description='' +
                  textwrap.dedent(sys.modules[__name__].__doc__) +
                  textwrap.dedent(main.__doc__))

  cuj_list = '\n'.join([f'{i}: {cuj.name}' for i, cuj in enumerate(cujs)])
  p.add_argument('-c', '--cujs', nargs='*',
                 type=validate_int_in_range(0, len(cujs) - 1),
                 help=f'The index number(s) for the CUJ(s):\n{cuj_list}')

  p.add_argument('-r', '--repeat', type=validate_int_in_range(0, 10), default=1,
                 help='The number of times to repeat the build invocation. '
                      'If 0, then will not repeat (i.e. do exactly once). '
                      'Defaults to %(default)d')

  log_levels = dict(getattr(logging, '_levelToName')).values()
  p.add_argument('-v', '--verbosity', choices=log_levels, default='INFO',
                 help='Log level, defaults to %(default)s')

  p.add_argument('-l', '--log-dir', type=str, default=None,
                 help='Directory to collect logs in, '
                      'defaults to $OUT_DIR/timing_logs. '
                      'There is also a summary.csv file generated there.\n'
                      'Try `cat summary.csv | column -t -s,` to view it.')

  p.add_argument('--bazel-mode-dev', action=argparse.BooleanOptionalAction)
  p.add_argument('--bazel-mode', action=argparse.BooleanOptionalAction)

  p.add_argument('targets', nargs='*',
                 action=ValidateTargets,
                 help='Targets to run, defaults to %(default)s.',
                 default=['droid', 'dist'])

  options = p.parse_args()
  if options.verbosity:
    logging.root.setLevel(options.verbosity)
  global repeat_count
  repeat_count = options.repeat

  global log_dir
  if options.log_dir:
    log_dir = Path(options.log_dir)
  else:
    log_dir = get_out_dir().joinpath("timing_logs")

  if options.bazel_mode_dev and options.bazel_mode:
    raise argparse.ArgumentError(
        argument=None,
        message="mutually exclusive flags --bazel-mode-dev and --bazel-mode")
  is_bazel = options.targets[0].startswith('//')
  if (options.bazel_mode_dev or options.bazel_mode) and is_bazel:
    raise argparse.ArgumentError(
        argument=None,
        message="--bazel-mode-dev or --bazel-mode are not applicable for bazel"
    )

  return options


def main():
  """
  Runs the provided targets under various CUJs while timing them. In pseudocode:

    time m droid dist
    for each cuj:
        make relevant changes
        time m droid dist
        revert those changes
        time m droid dist
  """
  cujs = get_cujs()
  options = get_user_input(cujs)

  logging.info('START initial build')
  build(options, 'initial build', allow_dry_run=False)
  logging.info('DONE initial build\n\n')
  for i, cuj in enumerate(cujs):
    if options.cujs and i not in options.cujs:
      logging.debug('Ignoring cuj "%s"', cuj.name)
      continue
    logging.info('START "%s"', cuj.name)
    cuj.do_hook()
    build(options, cuj.name, allow_dry_run=True)
    logging.info('Revert change from "%s"', cuj.name)
    cuj.undo_hook()
    build(options, cuj.name + ' undo', allow_dry_run=False)
    logging.info('DONE "%s"\n\n', cuj.name)

  logging.info(
      f'TIP: run `cat {log_dir.joinpath("summary.csv")} '
      f'| column -t -s,` to view the results')


if __name__ == '__main__':
  main()
