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
import argparse
import dataclasses
import datetime
import glob
import json
import logging
import re
import shutil
import subprocess
import textwrap
from pathlib import Path
from typing import Optional

import util
import pretty


@dataclasses.dataclass
class PerfInfoOrEvent:
  """
  A duck-typed union of `soong_build_metrics.PerfInfo` and
  `soong_build_bp2build_metrics.Event` protobuf message types
  """
  name: str
  real_time: datetime.timedelta
  start_time: datetime.datetime
  description: str = ''  # Bp2BuildMetrics#Event doesn't have description

  def __post_init__(self):
    if isinstance(self.real_time, int):
      self.real_time = datetime.timedelta(microseconds=self.real_time / 1000)
    if isinstance(self.start_time, int):
      epoch = datetime.datetime(1970, 1, 1, tzinfo=datetime.timezone.utc)
      self.start_time = epoch + datetime.timedelta(
          microseconds=self.start_time / 1000)


SOONG_PB = 'soong_metrics'
SOONG_BUILD_PB = 'soong_build_metrics.pb'
BP2BUILD_PB = 'bp2build_metrics.pb'

SOONG_PROTO = 'build/soong/ui/metrics/' \
              'metrics_proto/metrics.proto'
SOONG_BUILD_PROTO = SOONG_PROTO
BP2BUILD_PROTO = 'build/soong/ui/metrics/' \
                 'bp2build_metrics_proto/bp2build_metrics.proto'

SOONG_MSG = 'soong_build_metrics.MetricsBase'
SOONG_BUILD_MSG = 'soong_build_metrics.SoongBuildMetrics'
BP2BUILD_MSG = 'soong_build_bp2build_metrics.Bp2BuildMetrics'


def _move_pbs_to(d: Path):
  soong_pb = util.get_out_dir().joinpath(SOONG_PB)
  soong_build_pb = util.get_out_dir().joinpath(SOONG_BUILD_PB)
  bp2build_pb = util.get_out_dir().joinpath(BP2BUILD_PB)
  if soong_pb.exists():
    shutil.move(soong_pb, d.joinpath(SOONG_PB))
  if soong_build_pb.exists():
    shutil.move(soong_build_pb, d.joinpath(SOONG_BUILD_PB))
  if bp2build_pb.exists():
    shutil.move(bp2build_pb, d.joinpath(BP2BUILD_PB))


def archive_run(d: Path, build_info: dict[str, any]):
  _move_pbs_to(d)
  with open(d.joinpath(util.BUILD_INFO_JSON), 'w') as f:
    json.dump(build_info, f, indent=True)


def read_pbs(d: Path) -> dict[str, str]:
  """
  Reads metrics data from pb files and archives the file by copying
  them under the log_dir.
  Soong_build event names may contain "mixed_build" event. To normalize the
  event names between mixed builds and soong-only build, convert
    `soong_build/soong_build.xyz` and `soong_build/soong_build.mixed_build.xyz`
  both to simply `soong_build/_.xyz`
  """
  soong_pb = d.joinpath(SOONG_PB)
  soong_build_pb = d.joinpath(SOONG_BUILD_PB)
  bp2build_pb = d.joinpath(BP2BUILD_PB)
  soong_proto = util.get_top_dir().joinpath(SOONG_PROTO)
  soong_build_proto = soong_proto
  bp2build_proto = util.get_top_dir().joinpath(BP2BUILD_PROTO)

  events: list[PerfInfoOrEvent] = []
  if soong_pb.exists():
    events.extend(_read_pb(soong_pb, soong_proto, SOONG_MSG))
  if soong_build_pb.exists():
    events.extend(_read_pb(soong_build_pb, soong_build_proto, SOONG_BUILD_MSG))
  if bp2build_pb.exists():
    events.extend(_read_pb(bp2build_pb, bp2build_proto, BP2BUILD_MSG))

  events.sort(key=lambda e: e.start_time)

  def normalize(desc: str) -> str:
    return re.sub(r'^(?:soong_build|mixed_build)', '*', desc)

  return {f'{m.name}/{normalize(m.description)}': util.hhmmss(m.real_time) for m
          in events}


def _read_pb(
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
  result = subprocess.check_output(cmd, shell=True, cwd=util.get_top_dir(),
                                   text=True)

  fields: set[str] = {f.name for f in dataclasses.fields(PerfInfoOrEvent)}

  def parse(d: dict) -> Optional[PerfInfoOrEvent]:
    filtered = {k: v for (k, v) in d.items() if k in fields}
    return PerfInfoOrEvent(**filtered)

  events: list[PerfInfoOrEvent] = [parse(d) for d in json.loads(result)]
  return events


Row = dict[str, any]


def _get_column_headers(rows: list[Row], allow_cycles: bool) -> list[str]:
  """
  Basically a topological sort or column headers. For each Row, the column order
  can be thought of as a partial view of a chain of events in chronological
  order. It's a partial view because not all events may have needed to occur for
  a build.
  """

  @dataclasses.dataclass
  class Column:
    header: str
    indegree: int
    nexts: set[str]

    def __str__(self):
      return f'#{self.indegree}->{self.header}->{self.nexts}'

  all_cols: dict[str, Column] = {}
  for row in rows:
    prev_col = None
    for col in row:
      if col not in all_cols:
        column = Column(col, 0, set())
        all_cols[col] = column
      if prev_col is not None and col not in prev_col.nexts:
        all_cols[col].indegree += 1
        prev_col.nexts.add(col)
      prev_col = all_cols[col]

  acc = []
  while len(all_cols) > 0:
    entries = [c for c in all_cols.values()]
    entries.sort(key=lambda c: f'{c.indegree:03d}{c.header}')
    entry = entries[0]
    # take only one to maintain alphabetical sort
    if entry.indegree != 0:
      s = 'event ordering has cycles'
      logging.warning(s)
      s += ":\n\t"
      s += "\n\t".join(str(c) for c in all_cols.values())
      logging.debug(s)
      if not allow_cycles:
        raise ValueError(s)
    acc.append(entry.header)
    for n in entry.nexts:
      n = all_cols.get(n)
      if n is not None:
        n.indegree -= 1
      else:
        if not allow_cycles:
          raise ValueError(f'unexpected error for: {n}')
    all_cols.pop(entry.header)
  return acc


def get_build_info_and_perf(d: Path) -> dict[str, any]:
  perf = read_pbs(d)
  build_info_json = d.joinpath(util.BUILD_INFO_JSON)
  if not build_info_json.exists():
    return perf
  with open(build_info_json, 'r') as f:
    build_info = json.load(f)
    return build_info | perf


def tabulate_metrics_csv(log_dir: Path):
  rows: list[dict[str, any]] = []
  dirs = glob.glob(f'{util.RUN_DIR_PREFIX}*', root_dir=log_dir)
  dirs.sort(key=lambda x: int(x[1 + len(util.RUN_DIR_PREFIX):]))
  for d in dirs:
    d = log_dir.joinpath(d)
    row = get_build_info_and_perf(d)
    rows.append(row)

  headers: list[str] = _get_column_headers(rows, allow_cycles=False)

  def row2line(r):
    return ','.join([str(r.get(col) or '') for col in headers])

  lines = [','.join(headers)]
  lines.extend(row2line(r) for r in rows)

  with open(log_dir.joinpath(util.METRICS_TABLE), mode='wt') as f:
    f.writelines(f'{line}\n' for line in lines)


def display_tabulated_metrics(log_dir: Path):
  cmd_str = util.get_cmd_to_display_tabulated_metrics(log_dir)
  output = subprocess.check_output(cmd_str, shell=True, text=True)
  logging.info(textwrap.dedent(f'''
  %s
  TIPS:
  1 To view key metrics in metrics.csv:
    %s
  2 To view column headers:
    %s
    '''), output, cmd_str, util.get_csv_columns_cmd(log_dir))


def main():
  p = argparse.ArgumentParser(
      formatter_class=argparse.RawTextHelpFormatter,
      description='read archived perf metrics from [LOG_DIR] and '
                  f'summarize them into {util.METRICS_TABLE}')
  default_log_dir = util.get_default_log_dir()
  p.add_argument('-l', '--log-dir', type=Path, default=default_log_dir,
                 help=textwrap.dedent('''
                 Directory for timing logs. Defaults to %(default)s
                 TIPS: Specify a directory outside of the source tree
                 ''').strip())
  p.add_argument('-m', '--add-manual-build',
                 help='If you want to add the metrics from the last manual '
                      f'build to {util.METRICS_TABLE}, provide a description')
  options = p.parse_args()

  if options.add_manual_build:
    build_info = {'build_type': 'MANUAL',
                  'description': options.add_manual_build}
    run_dir = next(util.next_path(options.log_dir.joinpath('run')))
    run_dir.mkdir(parents=True, exist_ok=False)
    archive_run(run_dir, build_info)

  tabulate_metrics_csv(options.log_dir)
  display_tabulated_metrics(options.log_dir)
  pretty.summarize_metrics(options.log_dir)
  pretty.display_summarized_metrics(options.log_dir, False)


if __name__ == '__main__':
  logging.root.setLevel(logging.INFO)
  main()
