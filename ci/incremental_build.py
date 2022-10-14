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
import enum
import functools
import io
import json
import logging
import os
import re
import shutil
import subprocess
import sys
import textwrap
import time
from enum import Enum
from pathlib import Path
from typing import Callable
from typing import Final
from typing import Mapping
from typing import Optional
from typing import TypeVar

INDICATOR_FILE: Final[str] = 'build/soong/soong_ui.bash'
SUMMARY_CSV: Final[str] = 'summary.csv'


def _get_tip(d: Path) -> str:
  """
  :param d: the path to log directory
  :return: a quick shell command to view some collected metrics
  """
  return (
      f'TIP: For a quick look at key data points in {SUMMARY_CSV} try:\n'
      f'  tail -n +2 "{d}/{SUMMARY_CSV}" | \\\n'  # skip the header row
      '  column -t -s, -J \\\n'  # load as json
      f'  -N "$(head -n 1 \'{d}/{SUMMARY_CSV}\')" | \\\n'  # row 1 = header
      '  jq -r ".table[] | [.time, .ninja_explains, .description] | @tsv"'
      # display the selected attributes as a table'
  )


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


class BuildResult(Enum):
  SUCCESS = enum.auto()
  FAILED = enum.auto()
  TEST_FAILURE = enum.auto()


@dataclasses.dataclass(frozen=True)
class CujStep:
  description: str
  action: Callable[[], None]
  test: Callable[[], bool] = lambda: True


@dataclasses.dataclass(frozen=True)
class Cuj:
  """
  A sequence of steps to be performed all or none.
  NO attempt is made to achieve atomicity, it's user responsibility.
  """
  description: str
  steps: list[CujStep]

  def __str__(self) -> str:
    if len(self.steps) < 2:
      return f'{self.description}: {self.steps[0].description}'
    steps_list = ' THEN '.join(
        [f'{i + 1}# {s.description}' for i, s in enumerate(self.steps)])
    return f'{self.description}: {steps_list}'


_SOONG_CMD: Final[str] = ('build/soong/soong_ui.bash '
                          '--make-mode --skip-soong-tests')


class BuildType(Enum):
  LEGACY = _SOONG_CMD
  MIXED_PROD = f'{_SOONG_CMD} --bazel-mode '
  MIXED_DEV = f'{_SOONG_CMD} --bazel-mode-dev '
  B = 'source build/envsetup.sh && b build '


@dataclasses.dataclass(frozen=True)
class UserInput:
  build_type: BuildType
  chosen_cujs: list[int]
  log_dir: Path
  repeat_count: int
  targets: list[str]


def _count_explanations(process_log_file: Path) -> int:
  """
  Builds are run with '-d explain' flag and ninja's explanations for running an
  action (except for phony outputs) are counted. The text of the explanations
  helps debugging. The count is an over-approximation of actions run, but it
  will be ZERO for a no-op build.
  """
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
  `soong_build_bp2build_metrics.Event` protobuf message types
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


def _prepare_env() -> Mapping[str, str]:
  ninja_dry_run = re.compile(r'(?:^|\s)-n\b')

  def get_soong_build_ninja_args():
    ninja_args = os.environ.get('NINJA_ARGS') or ''
    if ninja_args != '':
      ninja_args += ' '
    ninja_args += '-d explain --quiet'
    if ninja_dry_run.search(ninja_args):
      logging.warning(f'Running dry ninja runs NINJA_ARGS={ninja_args}')
    return ninja_args

  def get_soong_ui_ninja_args():
    soong_ui_ninja_args = os.environ.get('SOONG_UI_NINJA_ARGS') or ''
    if ninja_dry_run.search(soong_ui_ninja_args):
      sys.exit('"-n" in SOONG_UI_NINJA_ARGS would not update build.ninja etc')

    if soong_ui_ninja_args != '':
      soong_ui_ninja_args += ' '
    soong_ui_ninja_args += '-d explain --quiet'
    return soong_ui_ninja_args

  overrides: Mapping[str, str] = {
      'NINJA_ARGS': get_soong_build_ninja_args(),
      'SOONG_UI_NINJA_ARGS': get_soong_ui_ninja_args()
  }
  env = {**os.environ, **overrides}
  if not os.environ.get('TARGET_BUILD_PRODUCT'):
    env['TARGET_BUILD_PRODUCT'] = 'aosp_arm64'
    env['TARGET_BUILD_VARIANT'] = 'userdebug'
  return env


T = TypeVar('T')


def _union(list_a: list[T], list_b: list[T]) -> list[T]:
  acc = []
  acc.extend(list_a)
  acc.extend([b for b in list_b if b not in list_a])
  return acc


# run with pytest
def test_union():
  assert _union([], []) == []
  assert _union([1, 2], []) == [1, 2]
  assert _union([1, 2], [3, 4]) == [1, 2, 3, 4]
  assert _union([1, 5, 9], [3, 5, 7]) == [1, 5, 9, 3, 7]


def _write_summary(summary_csv: Path, start_nanos: int, **row):
  """
  Writes the row combined with metrics from `out/soong_metrics`
  to summary.csv. For `write_summary(time.time_ns(), a = 1, b = 'hi')`, the file
  content will be:
    |  a  |  b  | ... | soong/bootstrap | soong_build/soong_build | ...
    |  1  | hi  | ... | 0:02:07.979398  | 0:01:51.517449          | ...
  :param row: metadata columns for a row, e.g.
                 description, target(s) built, etc.
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

  append_to_file = summary_csv.exists()
  rows: list[dict[str, any]] = []
  if append_to_file:
    with open(summary_csv, mode='r', newline='') as f:
      reader = csv.DictReader(f)
      headers_in_summary_csv: list[str] = reader.fieldnames or []
      if headers_in_summary_csv != headers_for_run:
        # an example of why the headers would differ: unlike a mixed build,
        # a legacy build wouldn't have bp2build metrics
        logging.debug('Headers differ:\n%s\n%s',
                      headers_in_summary_csv, headers_for_run)
        append_to_file = False  # to be re-written
        headers_for_run = _union(headers_for_run, headers_in_summary_csv)
        logging.debug('Merged headers:\n%s', headers_for_run)
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


@functools.cache
def get_out_dir() -> Path:
  out_dir = os.environ.get('OUT_DIR')
  return Path(out_dir) if out_dir else get_top().joinpath('out')


def _to_file(parent: Path, description: str, suffix: int, ext: str) -> Path:
  """
  Basically a safer f'{description}-{suffix}.{extension}'.
  If such a file already exists the suffix is incremented as needed.
  """
  f = parent.joinpath(
      f'{description.replace("/", "__")}-{suffix}.{ext}')
  f.parent.mkdir(parents=True, exist_ok=True)
  if f.exists():
    return _to_file(parent, description, suffix + 1, ext)
  f.touch(exist_ok=False)
  return f


def mtime(p: Path) -> str:
  """stat `p` to provide its Modify timestamp in a log-friendly format"""
  if p.exists():
    ts = datetime.datetime.fromtimestamp(p.stat().st_mtime)
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
def _get_cujs() -> list[Cuj]:
  def touch(p: str) -> CujStep:
    file = get_top().joinpath(p)
    return CujStep(description=f'touch {p}', action=lambda: touch_file(file))

  def create_and_delete(desc: str, p: str, content: str) -> Cuj:
    file = Path(p)
    if file.is_absolute():
      raise SystemExit(f'expected relative paths: {p}')
    file = get_top().joinpath(file)
    missing_dirs = [f for f in file.parents if
                    not f.exists() and f.relative_to(get_top())]
    shallowest_missing_dir = missing_dirs[-1] if len(missing_dirs) else None

    def do():
      if file.exists():
        raise SystemExit(
            f'File {p} already exists. Interrupted an earlier run?\n'
            f'TIP: `repo status` and revert changes!!!')
      touch_file(file, parents=True)
      with open(file, mode="w") as f:
        f.write(content)

    def undo():
      if shallowest_missing_dir:
        shutil.rmtree(shallowest_missing_dir)
      else:
        file.unlink(missing_ok=False)

    return Cuj(description=desc,
               steps=[
                   CujStep(f'create {p}', do),
                   CujStep(f'delete {p}', undo)
               ])

  def touch_delete_create(desc: str, p: str) -> Cuj:
    original = get_top().joinpath(p)
    copied = get_out_dir().joinpath(f'{original.name}.bak')

    return Cuj(
        description=desc,
        steps=[
            CujStep(f'touch {p}', lambda: touch_file(original)),
            CujStep(f'delete {p}', lambda: original.rename(copied)),
            CujStep(f'create {p}', lambda: copied.rename(original))
        ])

  def build_bazel_merger(file: str) -> Cuj:
    existing = get_top().joinpath(file)
    merged = get_out_dir().joinpath('soong/workspace').joinpath(file)
    bogus: Final[str] = f'//BOGUS this line added by {__file__} ' \
                        f'for testing on {datetime.datetime.now()}\n'

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

    return Cuj(
        description='generated BUILD.bazel includes manual one',
        steps=[
            CujStep(f'modify {file}', add_line, verify),
            CujStep(f'revert {file}', revert, verify),
        ])

  package_dir = 'bionic/libc'
  dir_without_subpackage = 'bionic/libc/bionic'
  dir_with_subpackage = 'bionic'
  globbed_dir = 'libcore/benchmarks/src/benchmarks'
  return [
      Cuj('initial build', [CujStep('no-op', lambda: logging.info("no op"))]),
      Cuj('root bp', [touch('Android.bp')]),

      create_and_delete(
          f'Android.bp in {dir_with_subpackage=}',
          f'{dir_with_subpackage}/Android.bp',
          '//safe to delete'),
      create_and_delete(
          f'Android.bp in {dir_without_subpackage=}',
          f'{dir_without_subpackage}/Android.bp',
          '//safe to delete'),

      create_and_delete(
          f'BUILD in {dir_with_subpackage=}',
          f'{dir_with_subpackage}/Android.bp',
          '//safe to delete'),
      create_and_delete(
          f'BUILD in {dir_without_subpackage=}',
          f'{dir_without_subpackage}/BUILD',
          '//safe to delete'),

      create_and_delete(
          f'unreferenced dir in {dir_with_subpackage=}',
          f'{dir_with_subpackage}/unreferenced/test.txt',
          'safe to delete'),
      create_and_delete(
          f'unreferenced dir in {dir_without_subpackage=}',
          f'{dir_without_subpackage}/unreferenced/test.txt',
          'safe to delete'),

      create_and_delete(
          f'unreferenced file in {package_dir=}',
          f'{package_dir}/test.txt',
          'safe to delete'),
      create_and_delete(
          f'unreferenced file in {dir_with_subpackage=}',
          f'{dir_with_subpackage}/test.txt',
          'safe to delete'),
      create_and_delete(
          f'unreferenced file in {dir_without_subpackage=}',
          f'{dir_without_subpackage}/test.txt',
          'safe to delete'),

      build_bazel_merger('external/protobuf/BUILD.bazel'),

      touch_delete_create(
          f'existing BUILD in {package_dir=}',
          f'{package_dir}/BUILD'),
      touch_delete_create(
          f'existing file in {package_dir=}',
          f'{package_dir}/version_script.txt'),
      touch_delete_create(
          'existing Android Manifest',
          'art/artd/tests/AndroidManifest.xml'),
      touch_delete_create(
          f'existing src in {dir_without_subpackage=}',
          f'{dir_without_subpackage}/icu.cpp'),
      touch_delete_create(
          f'existing globbed file in {globbed_dir=}',
          f'{globbed_dir}/Foo.java'),
  ]


def _handle_user_input() -> UserInput:
  p = argparse.ArgumentParser(
      formatter_class=argparse.RawTextHelpFormatter,
      description='' +
                  textwrap.dedent(sys.modules[__name__].__doc__) +
                  textwrap.dedent(main.__doc__))

  cujs = _get_cujs()
  cuj_list = '\n'.join([f'{i:2}: {cuj}' for i, cuj in enumerate(cujs)])
  p.add_argument('-c', '--cujs', nargs='*',
                 type=_validate_int_in_range(0, len(cujs) - 1),
                 help='Index number(s) for the CUJ(s) from the following list.'
                      f'Note the ordering will be respected:\n{cuj_list}')
  p.add_argument('-C', '--exclude-cujs', nargs='*',
                 type=_validate_int_in_range(0, len(cujs) - 1),
                 help='The index number(s) for the CUJ(s) to be excluded')

  p.add_argument('-r', '--repeat', type=_validate_int_in_range(0, 10),
                 default=1,
                 help='The number of times to repeat the build invocation. '
                      'If 0, do not repeat (i.e. do exactly once). '
                      'Defaults to %(default)d\n'
                      'TIP: Repetitions should ideally be null builds.')

  log_levels = dict(getattr(logging, '_levelToName')).values()
  p.add_argument('-v', '--verbosity', choices=log_levels, default='INFO',
                 help='Log level, defaults to %(default)s')

  p.add_argument('-l', '--log-dir', type=str, default=None,
                 help='Directory to collect logs in, defaults to '
                      '$OUT_DIR/timing_logs.'
                      'TIP: specify a directory outside of the source tree\n'
                      f'There is also a {SUMMARY_CSV}\n'
                      f'{_get_tip(Path("<log_dir>"))}')

  p.add_argument('--bazel-mode-dev', default=False, action='store_true')
  p.add_argument('--bazel-mode', default=False, action='store_true')
  p.add_argument('--skip-repo-status', default=False, action='store_true',
                 help='Skip "repo status" check')

  p.add_argument('targets', nargs='*', default=['droid', 'dist'],
                 help='Targets to run, defaults to %(default)s.')

  options = p.parse_args()
  if options.verbosity:
    logging.root.setLevel(options.verbosity)
    f = logging.Formatter('%(levelname)s: %(message)s')
    for h in logging.root.handlers:
      h.setFormatter(f)

  if options.cujs and options.exclude_cujs:
    sys.exit('specify either --cujs or --exclude-cujs not both')
  chosen_cujs: list[int]
  if options.exclude_cujs:
    chosen_cujs = [i for i in range(0, len(cujs)) if
                   i not in options.exclude_cujs]
  elif options.cujs:
    chosen_cujs = options.cujs
  else:
    chosen_cujs = [i for i in range(0, len(cujs))]

  if options.bazel_mode_dev and options.bazel_mode:
    sys.exit('mutually exclusive options --bazel-mode-dev and --bazel-mode')
  bazel_labels = [target for target in options.targets if
                  target.startswith('//')]
  if 0 < len(bazel_labels) < len(options.targets):
    sys.exit(f'Don\'t mix bazel labels {bazel_labels} with soong targets '
             f'{[t for t in options.targets if t not in bazel_labels]}')
  build_type: BuildType
  if len(bazel_labels):
    if options.bazel_mode_dev or options.bazel_mode:
      sys.exit('--bazel-mode-dev or --bazel-mode are not applicable for b')
    build_type = BuildType.B
  elif options.bazel_mode_dev:
    build_type = BuildType.MIXED_DEV
  elif options.bazel_mode:
    build_type = BuildType.MIXED_PROD
  else:
    build_type = BuildType.LEGACY

  if not options.skip_repo_status and has_uncommitted_changed():
    response = input('There are uncommitted changes (TIP: repo status).\n'
                     'Continue?[Y/n]')
    if response.upper() != 'Y':
      sys.exit(0)

  return UserInput(
      build_type=build_type,
      chosen_cujs=chosen_cujs,
      log_dir=Path(
          options.log_dir) if options.log_dir else get_out_dir().joinpath(
          'timing_logs'),
      repeat_count=options.repeat,
      targets=options.targets)


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
    time build <target> with m or b
    collect metrics
    for each cuj:
        make relevant changes
        time rebuild
        collect metrics
        revert those changes
        time rebuild
        collect metrics
  """
  user_input = _handle_user_input()

  logging.warning('If you kill this process, make sure to `repo status` and '
                  'revert unwanted changes.\n'
                  'TIP: If you have no local changes of interest you may\n  '
                  'repo forall -p -c git reset --hard\n        and\n  '
                  'repo forall -p -c git clean --force\n        and even\n  '
                  'm clean')

  env = _prepare_env()
  cmd = f'{user_input.build_type.value} {" ".join(user_input.targets)}'

  @functools.cache
  def pretty_printed_env() -> str:
    env_for_logging = [f'{k}={v}' for (k, v) in env.items()]
    env_for_logging.sort()
    return '  ' + '\n  '.join(env_for_logging)

  def evaluate_result(returncode: int) -> BuildResult:
    if returncode != 0:
      return BuildResult.FAILED
    elif step.test():
      return BuildResult.SUCCESS
    else:
      return BuildResult.TEST_FAILURE

  def do_run():
    logfile = _to_file(user_input.log_dir, step.description, run_number, 'log')
    logging.info('TIP: to see the log:\n  tail -f "%s"', logfile)
    with open(logfile, mode='w') as f:
      f.write(f'Command: {cmd}\n')
      f.write(f'Environment Variables:\n{pretty_printed_env()}\n\n\n')
      # not time.perf_counter_ns() as we need wall clock time for stat()
      start_ns = time.time_ns()
      # TODO(usta): shell=False when `source build/envsetup.sh` not needed
      p = subprocess.run(cmd, check=False, cwd=get_top(), env=env,
                         shell=True, stdout=f, stderr=f)
      elapsed_ns = time.time_ns() - start_ns

    build_result = evaluate_result(p.returncode)

    logging.info(
        f'build result: {build_result.name} '
        f'after {datetime.timedelta(microseconds=elapsed_ns / 1000)}')
    _write_summary(
        user_input.log_dir.joinpath(SUMMARY_CSV),
        start_ns,
        description=step.description,
        run=run_number,
        build_type=user_input.build_type.name.lower(),
        build_result=build_result.name,
        targets=' '.join(user_input.targets),
        time=datetime.timedelta(microseconds=elapsed_ns / 1000),
        ninja_explains=_count_explanations(logfile))

  for i in user_input.chosen_cujs:
    cuj = _get_cujs()[i]
    for step in cuj.steps:
      logging.info('START %d "%s: %s"', i, cuj.description, step.description)
      step.action()
      for run_number in range(0, user_input.repeat_count + 1):
        do_run()
      logging.info(' DONE %d "%s: %s"\n', i, cuj.description, step.description)

  logging.info(_get_tip(user_input.log_dir))


if __name__ == '__main__':
  main()
