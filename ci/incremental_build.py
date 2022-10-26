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
import json
import logging
import os
import re
import subprocess
import sys
import textwrap
import time
from enum import Enum
from pathlib import Path
from typing import Final
from typing import Mapping
from typing import Optional
from typing import TypeVar

from incremental_build_cujs import get_cujgroups
from incremental_build_cujs import get_out_dir
from incremental_build_cujs import get_top_dir

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


class BuildResult(Enum):
  SUCCESS = enum.auto()
  FAILED = enum.auto()
  TEST_FAILURE = enum.auto()


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
  chosen_cujgroups: list[int]
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


def read_perf_metrics(log_dir: Path, description: str, run_number: int) -> dict[
  str, datetime.timedelta]:
  soong_pb: Final[Path] = get_out_dir().joinpath('soong_metrics')
  bp2build_pb: Final[Path] = get_out_dir().joinpath('bp2build_metrics.pb')
  soong_proto: Final[Path] = get_top_dir().joinpath(
      'build/soong/ui/metrics/metrics_proto/metrics.proto')
  bp2build_proto: Final[Path] = get_top_dir().joinpath(
      'build/soong/ui/metrics/bp2build_metrics_proto/bp2build_metrics.proto')
  soong_msg: Final[str] = 'soong_build_metrics.MetricsBase'
  bp2build_msg: Final[str] = 'soong_build_bp2build_metrics.Bp2BuildMetrics'
  events: list[PerfInfoOrEvent] = []
  if soong_pb.exists():
    events.extend(read_perf_metrics_pb(soong_pb, soong_proto, soong_msg))
    soong_pb.rename(
        _to_file(log_dir, f'soong_metrics_{description}', run_number, 'pb'))
  if bp2build_pb.exists():
    events.extend(
        read_perf_metrics_pb(bp2build_pb, bp2build_proto, bp2build_msg))
    bp2build_pb.rename(
        _to_file(log_dir, f'bp2_build_metrics_{description}', run_number, 'pb'))

  events.sort(key=lambda e: e.start_time)
  return {f'{m.name}/{m.description}': m.real_time for m in events}


def read_perf_metrics_pb(
    pb_file: Path,
    proto_file: Path,
    proto_message: str
) -> list[PerfInfoOrEvent]:
  """
  Loads PerfInfo or Event from the file sorted chronologically
  Note we are not using protoc-generated classes for simplicity (e.g. dependency
  on `google.protobuf`)
  Note dict keeps insertion order in python 3.7+
  """
  cmd = (f'''printproto --proto2  --raw_protocol_buffer \
  --message={proto_message} \
  --proto="{proto_file}" \
  --multiline \
  --json --json_accuracy_loss_reaction=ignore \
  "{pb_file}" \
  | jq ".. | objects | select(.real_time) | select(.name)" \
  | jq -s ". | sort_by(.start_time)"''')
  result = subprocess.check_output(cmd, shell=True, cwd=get_top_dir(),
                                   text=True)

  fields: set[str] = {f.name for f in dataclasses.fields(PerfInfoOrEvent)}

  def parse(d: dict) -> Optional[PerfInfoOrEvent]:
    filtered = {k: v for (k, v) in d.items() if k in fields}
    return PerfInfoOrEvent(**filtered)

  events: list[PerfInfoOrEvent] = [parse(d) for d in json.loads(result)]
  return events


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


def _write_csv_row(summary_csv: Path, row: dict[str, any]):
  headers_for_run: list[str] = [k for k in row]
  append_to_file = summary_csv.exists()
  rows: list[dict[str, any]] = []
  if append_to_file:
    with open(summary_csv, mode='r', newline='') as f:
      # let's check if the csv headers are compatible
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
  with open(summary_csv, mode='a' if append_to_file else 'w', newline='') as f:
    writer = csv.DictWriter(f, headers_for_run)
    if not append_to_file:
      writer.writeheader()
    writer.writerows(rows)


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


def _handle_user_input() -> UserInput:
  def validate_cujgroups(input_str: str) -> list[int]:
    if input_str.isnumeric():
      i = int(input_str)
      if 0 <= i < len(get_cujgroups()):
        return [i]
    else:
      matches = [i for i, cujgroup in enumerate(get_cujgroups()) if
                 input_str in cujgroup.description]
      if len(matches):
        return matches
    raise argparse.ArgumentError(
        argument=None,
        message=f'Invalid input, expected {min} <= {input_str} <= {max}')

  p = argparse.ArgumentParser(
      formatter_class=argparse.RawTextHelpFormatter,
      description='' +
                  textwrap.dedent(sys.modules[__name__].__doc__) +
                  textwrap.dedent(main.__doc__))

  cuj_list = '\n'.join(
      [f'{i:2}: {cujgroup}' for i, cujgroup in enumerate(get_cujgroups())])
  p.add_argument('-c', '--cujs', nargs='*',
                 type=validate_cujgroups,
                 help='Index number(s) for the CUJ(s) from the following list. '
                      'Or substring matches for the CUJ description.'
                      f'Note the ordering will be respected:\n{cuj_list}')
  p.add_argument('-C', '--exclude-cujs', nargs='*',
                 type=validate_cujgroups,
                 help='Index number(s) or substring match(es) for the CUJ(s) '
                      'to be excluded')

  p.add_argument('-r', '--repeat', type=int,
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
  chosen_cujgroups: list[int]
  if options.exclude_cujs:
    exclusions: list[int] = [i for sublist in options.exclude_cujs for i in
                             sublist]
    chosen_cujgroups = [i for i in range(0, len(get_cujgroups())) if
                        i not in exclusions]
  elif options.cujs:
    chosen_cujgroups = [i for sublist in options.cujs for i in sublist]
  else:
    chosen_cujgroups = [i for i in range(0, len(get_cujgroups()))]
  chosen_cuj_list = '\n'.join(
      [f'{i:2}: {get_cujgroups()[i]}' for i in chosen_cujgroups])
  logging.info(f'CUJs chosen:\n{chosen_cuj_list}')

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
      chosen_cujgroups=chosen_cujgroups,
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
        cwd=get_top_dir(), text=True,
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
    elif cujstep.test():
      return BuildResult.SUCCESS
    else:
      return BuildResult.TEST_FAILURE

  def build() -> dict[str, any]:
    logfile = _to_file(user_input.log_dir,
                       f'{cujgroup.description} {cujstep.description}',
                       run_number,
                       'log')
    logging.info('TIP: to see the log:\n  tail -f "%s"', logfile)
    with open(logfile, mode='w') as f:
      f.write(f'Command: {cmd}\n')
      f.write(f'Environment Variables:\n{pretty_printed_env()}\n\n\n')
      start_ns = time.perf_counter_ns()
      # TODO(usta): shell=False when `source build/envsetup.sh` not needed
      p = subprocess.run(cmd, check=False, cwd=get_top_dir(), env=env,
                         shell=True, stdout=f, stderr=f)
      elapsed_ns = time.perf_counter_ns() - start_ns

    build_result = evaluate_result(p.returncode)
    build_type = user_input.build_type.name.lower()
    logging.info(
        f'build result: {build_result.name} '
        f'after {datetime.timedelta(microseconds=elapsed_ns / 1000)}')
    return {
        'description': f'{cujgroup.description} {cujstep.description}',
        'run': run_number,
        'build_type': build_type,
        'targets': ' '.join(user_input.targets),
        'build_result': build_result.name,
        'ninja_explains': _count_explanations(logfile),
        'time': datetime.timedelta(microseconds=elapsed_ns / 1000)
    }

  clean = not get_out_dir().joinpath('soong/bootstrap.ninja').exists()
  summary_csv_path: Final[Path] = user_input.log_dir.joinpath(SUMMARY_CSV)
  for i in user_input.chosen_cujgroups:
    cujgroup = get_cujgroups()[i]
    for cujstep in cujgroup.steps:
      logging.info('START %d "%s: %s"', i, cujgroup.description,
                   cujstep.description)
      cujstep.action()
      for run_number in range(0, user_input.repeat_count + 1):
        row = build() | read_perf_metrics(
            user_input.log_dir,
            f'{cujgroup.description} {cujstep.description}',
            run_number)
        if clean:
          row['build_type'] = 'CLEAN ' + row['build_type']
          clean = False  # we don't clean subsequently
        _write_csv_row(summary_csv_path, row)
      logging.info(' DONE %d "%s: %s"\n', i, cujgroup.description,
                   cujstep.description)

  logging.info(_get_tip(user_input.log_dir))


if __name__ == '__main__':
  main()
