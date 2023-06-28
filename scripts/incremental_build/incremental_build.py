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
import datetime
import functools
import hashlib
import itertools
import json
import logging
import os
import shutil
import subprocess
import sys
import textwrap
import time
from pathlib import Path
from typing import Final
from typing import Mapping
from typing import TextIO

import cuj_catalog
import perf_metrics
import pretty
import ui
import util
from cuj import skip_for
from util import BuildInfo
from util import BuildResult
from util import BuildType

MAX_RUN_COUNT: Final[int] = 5
BAZEL_PROFILES: Final[str] = 'bazel_metrics'
CQUERY_OUT = 'soong/soong_injection/cquery.out'


@functools.cache
def _prepare_env() -> Mapping[str, str]:
  env = os.environ.copy()
  # TODO: Switch to oriole when it works
  default_product: Final[str] = 'cf_x86_64_phone' \
    if util.get_top_dir().joinpath('vendor/google/build').exists() \
    else 'aosp_cf_x86_64_phone'
  target_product = os.environ.get('TARGET_PRODUCT') or default_product
  variant = os.environ.get('TARGET_BUILD_VARIANT') or 'eng'

  if target_product != default_product or variant != 'eng':
    logging.warning(
        f'USING {target_product}-{variant} INSTEAD OF {default_product}-eng')
  env['TARGET_PRODUCT'] = target_product
  env['TARGET_BUILD_VARIANT'] = variant
  return env


def _new_action_count(actions_output: TextIO = None, previous_count=0) -> int:
  """the new actions are written to `actions_output`"""
  ninja_log_file = util.get_out_dir().joinpath('.ninja_log')
  if not ninja_log_file.exists():
    return 0
  action_count: int = 0
  with open(ninja_log_file, 'r') as ninja_log:
    for line in ninja_log:
      # note "# ninja log v5" is the first line in `.nina_log`
      if line.startswith('#'):
        continue
      action_count += 1
      if actions_output and previous_count < action_count:
        # second from last column is the file
        print(line.split()[-2], file=actions_output)
  delta = action_count - previous_count
  return delta


def _recompact_ninja_log(f: TextIO):
  env = _prepare_env()
  target_product = env["TARGET_PRODUCT"]
  subprocess.run([
      util.get_top_dir().joinpath(
          'prebuilts/build-tools/linux-x86/bin/ninja'),
      '-f',
      util.get_out_dir().joinpath(
          f'combined-{target_product}.ninja'),
      '-t', 'recompact'],
      check=False, cwd=util.get_top_dir(), env=env, shell=False,
      stdout=f, stderr=f)


def _build_file_sha(target_product: str) -> str:
  build_file = util.get_out_dir().joinpath(
      f'soong/build.{target_product}.ninja')
  if not build_file.exists():
    return ''
  with open(build_file, mode="rb") as f:
    h = hashlib.sha256()
    for block in iter(lambda: f.read(4096), b''):
      h.update(block)
    return h.hexdigest()[0:8]


def _build_file_size(target_product: str) -> int:
  build_file = util.get_out_dir().joinpath(
      f'soong/build.{target_product}.ninja')
  return os.path.getsize(build_file) if build_file.exists() else 0


@skip_for(BuildType.SOONG_ONLY)
def _query_buildroot_deps() -> int:
  cmd = f'{util.get_top_dir().joinpath("build/bazel/bin/bazel")} ' \
        f'--output_base={util.get_out_dir().joinpath("bazel/output")} ' \
        'cquery "deps(@soong_injection//mixed_builds:buildroot)" ' \
        '| wc -l'
  env = {
      'HOME': util.get_out_dir().joinpath('bazel/bazelhome'),
      'BUILD_DIR': util.get_out_dir().joinpath('soong'),
      'OUT_DIR': util.get_out_dir(),
      'BAZEL_DO_NOT_DETECT_CPP_TOOLCHAIN': '1'
  }
  p = subprocess.run(cmd, check=False,
                     cwd=util.get_out_dir().joinpath('soong/workspace'),
                     env=env, shell=True, capture_output=True)
  if p.returncode:
    if len(p.stderr):
      logging.error('bazel cquery errors: %s', p.stderr)
    return -1

  return int(p.stdout)


def _pretty_env(env: Mapping[str, str]) -> str:
  env_copy = [f'{k}={v}' for (k, v) in env.items()]
  env_copy.sort()
  return '\n'.join(env_copy)


def _build(build_type: BuildType, run_dir: Path) -> BuildInfo:
  logfile = run_dir.joinpath('output.txt')
  run_dir.mkdir(parents=True, exist_ok=False)
  cmd = [*build_type.value, *ui.get_user_input().targets]
  env = _prepare_env()
  target_product = env["TARGET_PRODUCT"]

  with open(logfile, mode='w') as f:
    action_count_before = _new_action_count()
    if action_count_before > 0:
      _recompact_ninja_log(f)
      f.flush()
      action_count_before = _new_action_count()
    f.write(f'Command: {cmd}\n'
            f'Environment Variables:\n'
            f'{textwrap.indent(_pretty_env(env), "  ")}\n\n\n')
    f.flush()  # because we pass f to a subprocess, we want to flush now
    logging.info('Command: %s', cmd)
    logging.info('TIP: To view the log:\n  tail -f "%s"', logfile)
    start_ns = time.perf_counter_ns()
    p = subprocess.run(cmd, check=False, cwd=util.get_top_dir(), env=env,
                       shell=False, stdout=f, stderr=f)
    elapsed_ns = time.perf_counter_ns() - start_ns
    with open(run_dir.joinpath('new_ninja_actions.txt'), 'w') as af:
      action_count_delta = _new_action_count(af, action_count_before)

  return BuildInfo(
      actions=action_count_delta,
      build_root_deps=_query_buildroot_deps(),
      build_type=build_type,
      build_result=BuildResult.FAILED if p.returncode else BuildResult.SUCCESS,
      build_ninja_hash=_build_file_sha(target_product),
      build_ninja_size=_build_file_size(target_product),
      product=f'{target_product}-{env["TARGET_BUILD_VARIANT"]}',
      time=datetime.timedelta(microseconds=elapsed_ns / 1000)
  )


def _run_cuj(run_dir: Path, build_type: ui.BuildType,
    cujstep: cuj_catalog.CujStep) -> BuildInfo:
  cquery_out = util.get_out_dir().joinpath('soong/soong_injection/cquery.out')

  def get_cquery_ts() -> float:
    try:
      return os.stat(cquery_out).st_mtime
    except FileNotFoundError:
      return -1

  @skip_for(BuildType.SOONG_ONLY)
  def get_cquery_size() -> int:
    return os.path.getsize(cquery_out)

  cquery_ts = get_cquery_ts()
  build_info: Final[BuildInfo] = _build(build_type, run_dir)
  # if build was successful, run test
  build_info.targets = ui.get_user_input().targets
  if build_info.build_result == BuildResult.SUCCESS:
    try:
      cujstep.verify()
    except Exception as e:
      logging.error(e)
      build_info.build_result = BuildResult.TEST_FAILURE
  build_info.cquery_out_size = get_cquery_size()
  if get_cquery_ts() > cquery_ts:
    shutil.copy(cquery_out, run_dir.joinpath('cquery.out'))
    bazel_profiles = util.get_out_dir().joinpath(BAZEL_PROFILES)
    if bazel_profiles.exists():
      shutil.copytree(bazel_profiles, run_dir.joinpath(BAZEL_PROFILES))

  return build_info


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
  user_input = ui.get_user_input()

  logging.warning(textwrap.dedent(f'''
  If you kill this process, make sure to revert unwanted changes.
  TIP: If you have no local changes of interest you may
       `repo forall -p -c git reset --hard`  and
       `repo forall -p -c git clean --force` and even
       `m clean && rm -rf {util.get_out_dir()}`
  '''))

  run_dir_gen = util.next_path(user_input.log_dir.joinpath(util.RUN_DIR_PREFIX))
  stop_building = False

  def run_cuj_group(cuj_group: cuj_catalog.CujGroup):
    nonlocal stop_building
    metrics = user_input.log_dir.joinpath(util.METRICS_TABLE)
    summary = user_input.log_dir.joinpath(util.SUMMARY_TABLE)
    for cujstep in cuj_group.steps:
      desc = cujstep.verb
      desc = f'{desc} {cuj_group.description}'.strip()
      desc = f'{desc} {user_input.description}'.strip()
      logging.info('********* %s %s [%s] **********', build_type.name,
                   ' '.join(user_input.targets), desc)
      cujstep.apply_change()

      for run in itertools.count():
        if stop_building:
          logging.warning('SKIPPING BUILD')
          break
        run_dir = next(run_dir_gen)

        build_info = _run_cuj(run_dir, build_type, cujstep)
        build_info.description = desc if run == 0 else \
          f'rebuild-{run} after {desc}'
        build_info.warmup = cuj_group == cuj_catalog.Warmup
        build_info.rebuild = run != 0

        logging.info(json.dumps(build_info, indent=2, cls=util.CustomEncoder))

        if user_input.ci_mode:
          if build_info.build_result == BuildResult.FAILED:
            logging.critical(
                f'Failed CI build runs detected! Please see logs in: {run_dir}')
            sys.exit(1)
          if cuj_group != cuj_catalog.Warmup:
            stop_building = True
            logs_dir_for_ci = user_input.log_dir.parent.joinpath('logs')
            if logs_dir_for_ci.exists():
              perf_metrics.archive_run(logs_dir_for_ci, build_info)

        perf_metrics.archive_run(run_dir, build_info)
        # we are doing tabulation and summary after each run
        # so that we can look at intermediate results
        perf_metrics.tabulate_metrics_csv(user_input.log_dir)
        with open(metrics, mode='rt') as mf, open(summary, mode='wt') as sf:
          pretty.summarize_metrics(mf, sf)
        if run == 0:
          perf_metrics.display_tabulated_metrics(user_input.log_dir,
                                                 user_input.ci_mode)
          pretty.display_summarized_metrics(user_input.log_dir)
        if build_info.actions == 0:
          # build has stabilized
          break
        if run == MAX_RUN_COUNT - 1:
          sys.exit(f'Build did not stabilize in {run} attempts')

  for build_type in user_input.build_types:
    util.CURRENT_BUILD_TYPE = build_type
    # warm-up run reduces variations attributable to OS caches
    run_cuj_group(cuj_catalog.Warmup)
    for i in user_input.chosen_cujgroups:
      run_cuj_group(cuj_catalog.get_cujgroups()[i])


class InfoAndBelow(logging.Filter):
  def filter(self, record):
    return record.levelno < logging.WARNING


class ColoredLoggingFormatter(logging.Formatter):
  GREEN = '\x1b[32m'
  PURPLE = '\x1b[35m'
  RED = '\x1b[31m'
  YELLOW = '\x1b[33m'
  RESET = '\x1b[0m'
  BASIC = '%(asctime)s %(levelname)s: %(message)s'

  FORMATS = {
      logging.DEBUG: f'{YELLOW}%(asctime)s %(levelname)s:{RESET} %(message)s',
      logging.INFO: f'{GREEN}%(asctime)s %(levelname)s:{RESET} %(message)s',
      logging.WARNING: f'{PURPLE}{BASIC}{RESET}',
      logging.ERROR: f'{RED}{BASIC}{RESET}',
      logging.CRITICAL: f'{RED}{BASIC}{RESET}'
  }

  def format(self, record):
    f = self.FORMATS.get(record.levelno, ColoredLoggingFormatter.BASIC)
    formatter = logging.Formatter(fmt=f, datefmt='%H:%M:%S')
    return formatter.format(record)


def configure_logger():
  eh = logging.StreamHandler(stream=sys.stderr)
  eh.setLevel(logging.WARNING)
  eh.setFormatter(ColoredLoggingFormatter())
  logging.getLogger().addHandler(eh)

  oh = logging.StreamHandler(stream=sys.stdout)
  oh.addFilter(InfoAndBelow())
  oh.setFormatter(ColoredLoggingFormatter())
  logging.getLogger().addHandler(oh)


if __name__ == '__main__':
  configure_logger()
  main()
