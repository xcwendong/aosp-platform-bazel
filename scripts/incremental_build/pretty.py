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
import csv
import datetime
import itertools
import logging
import re
import statistics
import subprocess
import textwrap
from pathlib import Path

from typing.io import TextIO

import util

Row = dict[str, str]


# note we are modify the row in-place and not making a copy
def _normalize_rebuild(row: Row) -> Row:
  row['description'] = re.sub(r'^(rebuild)-[\d+](.*)$', '\\1\\2',
                              row.get('description'))
  return row


def _build_types(rows: list[Row]) -> list[str]:
  return list(dict.fromkeys(r.get('build_type') for r in rows).keys())


def _write_table(lines: list[list[str]]) -> str:
  def join_cells(line: list[str]) -> str:
    return ','.join(str(cell) for cell in line)

  return '\n'.join(join_cells(line) for line in lines)


def _acceptable(row: Row) -> bool:
  failure = row.get("build_result") == "FAILED"
  if failure:
    logging.error(
        f"Skipping {row.get('description')}/{row.get('build_type')}")
  return not failure


def _median_value(prop: str, rows: list[Row]) -> str:
  if not rows:
    return ''
  vals = [x.get(prop) for x in rows]
  vals = [x for x in vals if bool(x)]
  if len(vals) == 0:
    return ''

  isnum = sum(1 for x in vals if x.isnumeric()) == len(vals)
  if isnum:
    vals = [int(x) for x in vals]
    cell = f'{(statistics.median(vals)):.0f}'
  else:
    vals = [util.period_to_seconds(x) for x in vals]
    cell = util.hhmmss(datetime.timedelta(seconds=statistics.median(vals)),
                       decimal_precision=False)

  if len(vals) > 1:
    cell = f'{cell}[N={len(vals)}]'
  return cell


def summarize_metrics(metrics: TextIO, summary: TextIO):
  """
  Args:
    metrics: csv detailed input, each row corresponding to a build
    summary: csv summarized output
  """
  summary.write(summarize(metrics, '^time$').get('time'))


def summarize(metrics: TextIO, *regexes: str) -> dict[str, str]:
  assert len(regexes) > 0
  reader = csv.DictReader(metrics)

  # get all matching properties
  def expand(regex: str):
    p = re.compile(regex)
    return (f for f in reader.fieldnames if p.search(f))

  all_rows: list[Row] = [_normalize_rebuild(row) for row in reader if
                         _acceptable(row)]
  build_types: list[str] = _build_types(all_rows)
  by_cuj: dict[str, list[Row]] = util.groupby(all_rows,
                                              lambda l: l.get("description"))

  def extract_lines_for_cuj(prop, cuj, cuj_rows) -> list[list[str]]:
    by_targets = util.groupby(cuj_rows, lambda l: l.get("targets"))
    lines = []
    for (targets, target_rows) in by_targets.items():
      by_build_type = util.groupby(target_rows, lambda l: l.get("build_type"))
      vals = [_median_value(prop, by_build_type.get(build_type)) for
              build_type in build_types]
      lines.append([cuj, targets, *vals])
    return lines

  def tabulate(prop) -> str:
    headers = ["cuj", "targets"] + build_types
    lines: list[list[str]] = [headers]
    for cuj, cuj_rows in by_cuj.items():
      lines.extend(extract_lines_for_cuj(prop, cuj, cuj_rows))
    return _write_table(lines)

  # flatten all expansions
  properties = itertools.chain.from_iterable(expand(r) for r in regexes)
  # remove duplicates while preserving insertion order
  properties = dict.fromkeys(list(properties)).keys()
  if len(properties) == 0:
    raise Exception('no matching properties found')
  return {prop: tabulate(prop) for prop in properties}


def display_summarized_metrics(log_dir: Path):
  f = log_dir.joinpath(util.SUMMARY_TABLE)
  cmd = f'grep -v "WARMUP\\|rebuild\\|revert\\|delete" {f}' \
        f' | column -t -s,'
  output = subprocess.check_output(cmd, shell=True, text=True)
  logging.info(textwrap.dedent(f'''
  %s
  TIPS:
    To view condensed summary:
    %s
    --OR--
    pretty.sh {log_dir.joinpath(util.METRICS_TABLE)}
  '''), output, cmd)


def main():
  p = argparse.ArgumentParser()
  p.add_argument(
      '-p', '--properties',
      default=['^time$'],
      nargs='*',
      help='properties to extract, should be time period based')
  p.add_argument(
      'metrics',
      nargs='?',
      default=util.get_default_log_dir().joinpath(util.METRICS_TABLE),
      help='metrics.csv file to parse')
  p.add_argument(
      '--csv',
      action='store_true'
  )
  options = p.parse_args()
  input_file = Path(options.metrics)
  if input_file.exists() and input_file.is_dir():
    input_file = input_file.joinpath(util.METRICS_TABLE)
  if not input_file.exists():
    raise RuntimeError(f'{input_file} does not exit')
  with open(input_file, mode='rt') as mf:
    for prop, s in summarize(mf, *options.properties).items():
      logging.info('Displaying %s', prop)
      if options.csv:
        logging.info(s)
      else:
        p = subprocess.run(
            f'echo "{s}"  | grep -v "rebuild" | column -t -s,',
            shell=True, text=True, check=True, capture_output=True)
        logging.info('\n%s', p.stdout)
        if p.returncode:
          logging.error(p.stderr)


if __name__ == '__main__':
  logging.root.setLevel(logging.INFO)
  main()
