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

import argparse
import dataclasses
import logging
import re
import textwrap
from enum import Enum
from pathlib import Path

from future.moves import sys

import cuj_catalog
import util


class BuildType(Enum):
  _ignore_ = '_soong_cmd'
  _soong_cmd = ['build/soong/soong_ui.bash',
                '--make-mode',
                '--skip-soong-tests']
  SOONG_ONLY = _soong_cmd
  MIXED_PROD = [*_soong_cmd, '--bazel-mode']
  MIXED_STAGING = [*_soong_cmd, '--bazel-mode-staging']
  MIXED_DEV = [*_soong_cmd, '--bazel-mode-dev']
  B = ['build/bazel/bin/b', 'build']
  B_ANDROID = [*B, '--config=android']


@dataclasses.dataclass(frozen=True)
class UserInput:
  build_type: BuildType
  chosen_cujgroups: list[int]
  log_dir: Path
  targets: list[str]


def handle_user_input() -> UserInput:
  cujgroups = cuj_catalog.get_cujgroups()

  def validate_cujgroups(input_str: str) -> list[int]:
    if input_str.isnumeric():
      i = int(input_str)
      if 0 <= i < len(cujgroups):
        return [i]
    else:
      pattern = re.compile(input_str)

      def matches(cujgroup: cuj_catalog.CujGroup) -> bool:
        for cujstep in cujgroup.steps:
          # because we should run all cujsteps in a group we will select
          # a group if any of its steps match the pattern
          if pattern.search(f'{cujstep.verb} {cujgroup.description}'):
            return True
        return False

      matching_cuj_groups = [i for i, cujgroup in enumerate(cujgroups) if
                             matches(cujgroup)]
      if len(matching_cuj_groups):
        return matching_cuj_groups
    raise argparse.ArgumentError(
        argument=None,
        message=f'Invalid input: "{input_str}" '
                f'expected an index <= {len(cujgroups)} '
                'or a regex pattern for a CUJ descriptions')

  # importing locally here to avoid chances of cyclic import
  import incremental_build
  p = argparse.ArgumentParser(
      formatter_class=argparse.RawTextHelpFormatter,
      description='' +
                  textwrap.dedent(incremental_build.__doc__) +
                  textwrap.dedent(incremental_build.main.__doc__))

  cuj_list = '\n'.join(
      [f'{i:2}: {cujgroup}' for i, cujgroup in enumerate(cujgroups)])
  p.add_argument('-c', '--cujs', nargs='*',
                 type=validate_cujgroups,
                 help='Index number(s) for the CUJ(s) from the following list. '
                      'Or substring matches for the CUJ description.'
                      f'Note the ordering will be respected:\n{cuj_list}')
  p.add_argument('-C', '--exclude-cujs', nargs='*',
                 type=validate_cujgroups,
                 help='Index number(s) or substring match(es) for the CUJ(s) '
                      'to be excluded')

  log_levels = dict(getattr(logging, '_levelToName')).values()
  p.add_argument('-v', '--verbosity', choices=log_levels, default='INFO',
                 help='Log level. Defaults to %(default)s')
  default_log_dir = util.get_out_dir().joinpath(util.DEFAULT_TIMING_LOGS_DIR)
  p.add_argument('-l', '--log-dir', type=Path, default=default_log_dir,
                 help='Directory for timing logs. Defaults to %(default)s\n'
                      'TIPS:\n'
                      '  Specify a directory outside of the source tree\n'
                      '  For a quick look at key metrics:\n'
                      f'    {util.get_summary_cmd(default_log_dir)}')

  p.add_argument('--bazel-mode-staging', default=False, action='store_true')
  p.add_argument('--bazel-mode-dev', default=False, action='store_true')
  p.add_argument('--bazel-mode', default=False, action='store_true')
  p.add_argument('--ignore-repo-diff', default=False, action='store_true',
                 help='Skip "repo status" check')

  p.add_argument('targets', nargs='+', help='Targets to run')

  options = p.parse_args()
  if options.verbosity:
    logging.root.setLevel(options.verbosity)

  if options.cujs and options.exclude_cujs:
    sys.exit('specify either --cujs or --exclude-cujs not both')
  chosen_cujgroups: list[int]
  if options.exclude_cujs:
    exclusions: list[int] = [i for sublist in options.exclude_cujs for i in
                             sublist]
    chosen_cujgroups = [i for i in range(0, len(cujgroups)) if
                        i not in exclusions]
  elif options.cujs:
    chosen_cujgroups = [i for sublist in options.cujs for i in sublist]
  else:
    chosen_cujgroups = [i for i in range(0, len(cujgroups))]

  chosen_bazel_modes = [bazel_mode for bazel_mode in [
      options.bazel_mode_dev,
      options.bazel_mode_staging,
      options.bazel_mode] if bazel_mode]
  if len(chosen_bazel_modes) > 1:
    sys.exit('choose only one --bazel-mode option')
  bazel_labels = [target for target in options.targets if
                  target.startswith('//')]
  if 0 < len(bazel_labels) < len(options.targets):
    sys.exit(f'Don\'t mix bazel labels {bazel_labels} with soong targets '
             f'{[t for t in options.targets if t not in bazel_labels]}')
  build_type: BuildType
  if len(bazel_labels):
    if len(chosen_bazel_modes) > 0:
      sys.exit(f'{chosen_bazel_modes} not applicable for b')
    build_type = BuildType.B
  elif options.bazel_mode_dev:
    build_type = BuildType.MIXED_DEV
  elif options.bazel_mode:
    build_type = BuildType.MIXED_PROD
  else:
    build_type = BuildType.SOONG_ONLY

  chosen_cuj_list = '\n'.join(
      [f'{i:2}: {cujgroups[i]}' for i in chosen_cujgroups])
  logging.info(f'CUJs chosen:\n{chosen_cuj_list}')

  if not options.ignore_repo_diff and util.has_uncommitted_changes():
    error_message = 'THERE ARE UNCOMMITTED CHANGES (TIP: repo status).' \
                    'You may consider using --ignore-repo-diff'
    if not util.is_interactive_shell():
      sys.exit(error_message)
    response = input(f'{error_message}\nContinue?[Y/n]')
    if response.upper() != 'Y':
      sys.exit(0)

  return UserInput(
      build_type=build_type,
      chosen_cujgroups=chosen_cujgroups,
      log_dir=Path(options.log_dir),
      targets=options.targets)
