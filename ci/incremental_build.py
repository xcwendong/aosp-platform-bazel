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
import json
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
from typing import Optional
from typing import TypeVar

INDICATOR_FILE: Final[str] = 'build/soong/soong_ui.bash'
SUMMARY_CSV: Final[str] = 'summary.csv'
TIP: Final[str] = (
    f'TIP: For a quick look at key data points in {SUMMARY_CSV} try:\n'
    '  tail -n +2 summary.csv | \\\n'  # skip the header row
    '  column -t -s, -J \\\n'  # load as json
    '    -N "$(head -n 1 summary.csv)" | \\\n'  # first row is the header
    '  jq -r ".table[] | [.time, .ninja_explains, .logfile] | @tsv"'
    # display the selected attributes as a table'
)

# the following variables capture user input, see respective help messages
repeat_count: int
log_dir: Path


@functools.cache
def get_top(d: Path = Path('.').absolute()) -> Path:
  """Get the path to the root of the Android source tree"""
  logging.debug('Checking if Android source tree root is %s', d)
  if d.parent == d:
    sys.exit('Unable to find ROOT source directory, specifically,'
             f'{INDICATOR_FILE} not found anywhere. '
             'Try `m nothing` and `repo sync`')
  if d.joinpath(INDICATOR_FILE).is_file():
    logging.info('Android source tree root = %s', d)
    return d
  return get_top(d.parent)


@dataclasses.dataclass
class Cuj:
  name: str
  do: Callable[[], None]
  undo: Optional[Callable[[], None]]

  def with_prefix(self, prefix: str) -> 'Cuj':
    self.name = f'{prefix} {self.name}'
    return self


def _count_explanations(process_log_file: Path) -> int:
  explanations = 0
  pattern = re.compile(
      r'^ninja explain:(?! edge with output .* is a phony output,'
      r' so is always dirty$)')
  with open(process_log_file) as f:
    for line in f:
      if pattern.match(line):
        explanations += 1
  return explanations


@dataclasses.dataclass
class PerfInfoOrEvent:
  """
  A duck-typed union of `soong_build_metrics.PerfInfo` and
  `soong_build_bp2build_metrics.Event`
  """
  name: str
  real_time: datetime.timedelta
  start_time: int
  description: str = ''  # Bp2BuildMetrics#Event doesn't have description

  def __post_init__(self):
    if isinstance(self.real_time, int):
      self.real_time = datetime.timedelta(microseconds=self.real_time / 1000)


def read_perf_info(
    pb_file: Path,
    proto_file: Path,
    proto_message: str
) -> list[PerfInfoOrEvent]:
  """
  Loads PerfInfo or Event from the file sorted chronologically
  Note we are not using protoc-generated classes for simplicity (e.g. dependency
  on `google.protobuf`)
  """
  cmd = (f'printproto --proto2  --raw_protocol_buffer '
         f'--message={proto_message} '
         f'--proto="{proto_file}" '
         '--multiline '
         '--json --json_accuracy_loss_reaction=ignore '
         f'"{pb_file}" '
         '| jq ".. | objects | select(.real_time) | select(.name)" '
         '| jq -s ". | sort_by(.start_time)"')
  result = subprocess.check_output(cmd, shell=True, cwd=get_top())

  def parse(d: dict) -> Optional[PerfInfoOrEvent]:
    fields: set[str] = {f.name for f in dataclasses.fields(PerfInfoOrEvent)}
    filtered = {k: v for (k, v) in d.items() if k in fields}
    return PerfInfoOrEvent(**filtered)

  metrics: list[PerfInfoOrEvent] = [parse(d) for d in json.loads(result)]

  return metrics


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

  ninja_dry_run = re.compile(r'(?:^|\s)-n\b')

  soong_ui_ninja_args = os.environ.get('SOONG_UI_NINJA_ARGS') or ''
  if ninja_dry_run.search(soong_ui_ninja_args):
    sys.exit('"-n" in SOONG_UI_NINJA_ARGS would not update build.ninja etc')

  if soong_ui_ninja_args != '':
    soong_ui_ninja_args += ' '
  soong_ui_ninja_args += '-d explain --quiet'

  if not allow_dry_run and ninja_dry_run.search(ninja_args):
    logging.warning(f'ignoring "-n" in NINJA_ARGS={ninja_args}')
    ninja_args = ninja_dry_run.sub('', ninja_args)

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
                                  'SOONG_UI_NINJA_ARGS': soong_ui_ninja_args,
                                  'TARGET_BUILD_VARIANT': 'userdebug',
                                  'TARGET_PRODUCT': 'aosp_arm64'
                                  }
  env: Mapping[str, str] = {**os.environ, **overrides}

  build_type: str
  if is_bazel:
    build_type = 'b'
  elif options.bazel_mode_dev:
    build_type = 'mixed dev'
  elif options.bazel_mode:
    build_type = 'mixed'
  else:
    build_type = 'soong'

  env_for_logging = [f'{k}={v}' for (k, v) in env.items()]
  env_for_logging.sort()
  env_string = '\n  '.join(env_for_logging)

  for run_number in range(0, repeat_count + 1):
    process_log_file = _cuj2filename(cuj_name, 'log', run_number)
    with open(process_log_file, 'w') as f:
      logging.info('TIP: to see the log:\n  tail -f "%s"', process_log_file)
      f.write(datetime.datetime.now().strftime('%m/%d/%Y %H:%M:%s\n'))
      f.write(f'Environment Variables:\n  {env_string}\n\n\n')
      f.write(f'Running:{cmd}\n')
      start = time.time_ns()
      # ^ not time.perf_counter_ns() as we need wall clock time for stat()
      p = subprocess.run(
          cmd,
          check=False,
          cwd=get_top(),
          env=env,
          text=True,
          shell=True,
          # TODO(usta): `shell=False` when `source build/envsetup.sh` not needed
          stdout=f,
          stderr=f)
      elapsed = datetime.timedelta(
        microseconds=(time.time_ns() - start) / 1000)

    if p.returncode != 0:
      logging.error(
          f'subprocess yielded {p.returncode} see {process_log_file}')

    _write_summary(
        start,
        cuj=cuj_name,
        run=run_number,
        build_type=build_type if p.returncode == 0 else f'FAILED {build_type}',
        targets=' '.join(targets),
        time=elapsed,
        ninja_explains=_count_explanations(process_log_file))


T = TypeVar('T')


def merge(list_a: list[T], list_b: list[T]) -> list[T]:
  """
  Merges two lists while maintaining order assuming the two have a
  consistent ordering, i.e. for any two elements present in both lists,
  their order is the same in both (i.e. the same element comes first)
  merge([],[]) -> []
  merge([],[1,2]) -> [1,2]
  merge([1, 5, 3], [2, 5, 9, 3]) -> [1, 2, 5, 9, 3]
  """
  j = 0
  acc = []
  for i in range(0, len(list_a)):
    if j == len(list_b):
      acc.extend(list_a[i:])
      break
    a = list_a[i]
    try:
      k = list_b.index(a, j)
      acc.extend(list_b[j:k + 1])
      j = k + 1
    except ValueError:
      acc.append(a)
  acc.extend(list_b[j:])
  return acc


# run with pytest
def test_merge():
  assert merge([], []) == []
  assert merge([1, 2], []) == [1, 2]
  assert merge([1, 2], [3, 4]) == [1, 2, 3, 4]
  assert merge([1, 5, 9], [3, 5, 7]) == [1, 3, 5, 9, 7]
  assert merge([1, 2, 3], [5, 7]) == [1, 2, 3, 5, 7]
  assert merge([1, 2, 3], [5, 7, 1]) == [5, 7, 1, 2, 3]


def _write_summary(start_nanos: int, **row):
  """
  Writes the row combined with metrics from `out/soong_metrics`
  to summary.csv. For `write_summary(time.time_ns(), a = 1, b = 'hi')`, the file
  content will be:
    |  a  |  b  | ... | soong/bootstrap | soong_build/soong_build | ...
    |  1  | hi  | ... | 0:02:07.979398  | 0:01:51.517449          | ...
  :param row: metadata columns for a row, e.g.
                 cuj, target(s) built, etc.
  """
  headers_for_run: list[str] = [k for k in row]

  pb_file = get_out_dir().joinpath('soong_metrics')
  if pb_file.exists() and pb_file.stat().st_mtime_ns > start_nanos:
    for m in read_perf_info(
        pb_file=pb_file,
        proto_file=get_top().joinpath(
            'build/soong/ui/metrics/'
            'metrics_proto/metrics.proto'),
        proto_message='soong_build_metrics.MetricsBase'
    ):
      key = f'{m.name}/{m.description}'
      headers_for_run.append(key)
      row[key] = m.real_time

  pb_file = get_out_dir().joinpath('bp2build_metrics.pb')
  if pb_file.exists() and pb_file.stat().st_mtime_ns > start_nanos:
    for m in read_perf_info(
        pb_file=pb_file,
        proto_file=get_top().joinpath(
            'build/soong/ui/metrics/'
            'bp2build_metrics_proto/bp2build_metrics.proto'),
        proto_message='soong_build_bp2build_metrics.Bp2BuildMetrics'
    ):
      key = f'{m.name}/{m.description}'
      headers_for_run.append(key)
      row[key] = m.real_time

  summary_csv = log_dir.joinpath('summary.csv')
  append_to_file = summary_csv.exists()
  rows: list[dict[str, any]] = []
  if append_to_file:
    with open(summary_csv, mode='r', newline='') as f:
      reader = csv.DictReader(f)
      headers_in_summary_csv: list[str] = reader.fieldnames or []
      if headers_in_summary_csv != headers_for_run:
        # an example of why the headers would differ: unlike a mixed build,
        # a legacy build wouldn't have bp2build metrics
        logging.debug('headers differ:\n%s\n%s',
                      headers_in_summary_csv, headers_for_run)
        append_to_file = False  # to be re-written
        headers_for_run = merge(headers_in_summary_csv, headers_for_run)
        logging.debug('merged headers:\n%s', headers_for_run)
        rows = [r for r in reader]  # read current rows to rewrite later
  rows.append(row)
  with open(summary_csv, mode='a' if append_to_file else 'w',
            newline='') as f:
    writer = csv.DictWriter(f, headers_for_run)
    if not append_to_file:
      writer.writeheader()
    writer.writerows(rows)


def _validate_int_in_range(lo: int, hi: int) -> Callable[[str], int]:
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


def _cuj2filename(cuj_name: str, extension: str, suffix: int) -> Path:
  """
  Creates a file for logging output for the given cuj_name. A numeric
  suffix is appended to the filename to distinguish different runs.
  """
  f = log_dir.joinpath(
      f'{cuj_name.replace("/", "__")}-{suffix}.{extension}')
  f.parent.mkdir(parents=True, exist_ok=True)
  if f.exists():
    return _cuj2filename(cuj_name, extension, suffix + 1)
  f.touch(exist_ok=False)
  return f


def touch_file(p: Path, parents: bool = False):
  """
  Used as an approximation for file edits in CUJs.
  This works because Ninja determines freshness based on Modify timestamp.
  :param p: file to be `touch`-ed
  :param parents: if true, create the parent directories as needed
  """

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


@functools.cache
def _get_cujs() -> list[Cuj]:
  def touch(p: str):
    return Cuj(name=f'touch {p}',
               do=lambda: touch_file(get_top().joinpath(p)),
               undo=None)

  def new(p: str, content: Optional[str] = None):
    file = Path(p)
    if file.is_absolute():
      raise SystemExit(f'expected relative paths: {p}')
    file = get_top().joinpath(file)
    if file.exists():
      raise SystemExit(
          f'File {p} already exists, probably due to an interrupted earlier run'
          f'of {__file__}, TIP: `repo status` and revert changes!!!')
    missing_dirs = [f for f in file.parents if
                    not f.exists() and f.relative_to(get_top())]
    shallowest_missing_dir = missing_dirs[-1] if len(missing_dirs) else None

    def do():
      touch_file(file, parents=True)
      if content:
        with open(file, mode="w") as f:
          f.write(content)

    def undo():
      if shallowest_missing_dir:
        shutil.rmtree(shallowest_missing_dir)
      else:
        file.unlink(missing_ok=False)

    return Cuj(name=f'new {p}', do=do, undo=undo)

  def delete_create(p: str):
    original = get_top().joinpath(p)
    copied = get_out_dir().joinpath(f'{original.name}.bak')

    return Cuj(name=f'delete and create {p}',
               do=lambda: original.rename(copied),
               undo=lambda: copied.rename(original))

  return [
      Cuj(name='noop',
          do=lambda: logging.debug('d nothing'),
          undo=None),
      touch('Android.bp'),
      new('some_directory/Android.bp', '// empty test file'),
      new('unreferenced/unreferenced-file.c', '''
          #include <stdio.h>
          int main(){
            printf("Hello World");
            return 0;
          }
        '''),
      new('bionic/libc/arch-common/bionic/unreferenced.c'),
      touch('bionic/libc/bionic/icu.cpp'),
      delete_create('bionic/libc/bionic/icu.cpp'),
      touch('libcore/benchmarks/src/benchmarks/Foo.java').with_prefix(
          'globbed'),
      delete_create('libcore/benchmarks/src/benchmarks/Foo.java').with_prefix(
          'globbed'),
      touch('art/artd/tests/AndroidManifest.xml'),
      delete_create('art/artd/tests/AndroidManifest.xml'),
  ]


def _get_user_input(cujs: list[Cuj]) -> argparse.Namespace:
  p = argparse.ArgumentParser(
      formatter_class=argparse.RawTextHelpFormatter,
      description='' +
                  textwrap.dedent(sys.modules[__name__].__doc__) +
                  textwrap.dedent(main.__doc__))

  cuj_list = '\n'.join([f'{i}: {cuj.name}' for i, cuj in enumerate(cujs)])
  p.add_argument('-c', '--cujs', nargs='*',
                 type=_validate_int_in_range(0, len(cujs) - 1),
                 help=f'The index number(s) for the CUJ(s):\n{cuj_list}')

  p.add_argument('-r', '--repeat', type=_validate_int_in_range(0, 10),
                 default=1,
                 help='The number of times to repeat the build invocation. '
                      'If 0, do not repeat (i.e. do exactly once). '
                      'Defaults to %(default)d\n'
                      'TIP: Repetitions should ideally be null builds.')

  log_levels = dict(getattr(logging, '_levelToName')).values()
  p.add_argument('-v', '--verbosity', choices=log_levels, default='INFO',
                 help='Log level, defaults to %(default)s\n'
                      'TIP: specify a directory outside of the source tree')

  p.add_argument('-l', '--log-dir', type=str, default=None,
                 help='Directory to collect logs in, defaults to '
                      f'$OUT_DIR/timing_logs. There is also a {SUMMARY_CSV} '
                      f'file generated there.\n{TIP}')

  p.add_argument('--bazel-mode-dev', default=False, action='store_true')
  p.add_argument('--bazel-mode', default=False, action='store_true')
  p.add_argument('--skip-repo-status', default=False, action='store_true',
                 help='Skip "repo status" check')

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


def has_uncommitted_changed() -> bool:
  """
  effectively a quick 'repo status' that fails fast
  if any project has uncommitted changes
  """
  for cmd in ['diff', 'diff --staged']:
    diff = subprocess.run(
        args=f'repo forall -c git {cmd} --quiet --exit-code'.split(),
        cwd=get_top(), text=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL)
    if diff.returncode != 0:
      return True
  return False


def main():
  """
  Run provided target(s) under various CUJs and collect metrics.
  In pseudocode:
    time m <target>
    collect metrics
    for each cuj:
        make relevant changes
        time m <target>
        collect metrics
        revert those changes
        time m <target>
        collect metrics
  """
  cujs = _get_cujs()
  options = _get_user_input(cujs)

  if not options.skip_repo_status and has_uncommitted_changed():
    response = input('There are uncommitted changes (TIP: repo status).\n'
                     'Continue?[Y/n]')
    if response.upper() != 'Y':
      return

  logging.warning('If you kill this process, make sure to `repo status` and '
                  'revert unwanted changes.\n'
                  'TIP: If you have no local changes of interest you may\n  '
                  'repo forall -p -c git reset --hard\n        and\n  '
                  'repo forall -p -c git clean --force\n        and even\n  '
                  'm clean')
  logging.info('START initial build')
  build(options, 'initial build', allow_dry_run=False)
  logging.info('DONE initial build\n\n')
  for i, cuj in enumerate(cujs):
    if options.cujs and i not in options.cujs:
      logging.debug('Ignoring cuj "%s"', cuj.name)
      continue
    logging.info('START "%s"', cuj.name)
    cuj.do()
    build(options, cuj.name, allow_dry_run=True)
    if cuj.undo:
      logging.info('Revert change from "%s"', cuj.name)
      cuj.undo()
      build(options, cuj.name + ' undo', allow_dry_run=False)
    logging.info('DONE "%s"\n\n', cuj.name)

  logging.info(TIP)


if __name__ == '__main__':
  main()
