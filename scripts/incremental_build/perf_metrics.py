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
import csv
import dataclasses
import datetime
import json
import logging
import subprocess
from pathlib import Path
from typing import Final
from typing import Optional
from typing import TypeVar

import util


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


SOONG_PB = 'soong_metrics'
BP2BUILD_PB = 'bp2build_metrics.pb'
SOONG_PROTO = 'build/soong/ui/metrics/' \
              'metrics_proto/metrics.proto'
BP2BUILD_PROTO = 'build/soong/ui/metrics/' \
                 'bp2build_metrics_proto/bp2build_metrics.proto'
SOONG_MSG = 'soong_build_metrics.MetricsBase'
BP2BUILD_MSG = 'soong_build_bp2build_metrics.Bp2BuildMetrics'


def read(log_dir: Path) -> dict[str, datetime.timedelta]:
  """
  Reads metrics data from pb files and archives the file by copying
  them under the log_dir.
  Soong_build event names may contain "mixed_build" event. To normalize the
  event names between mixed builds and soong-only build, convert
    `soong_build/soong_build.xyz` and `soong_build/soong_build.mixed_build.xyz`
  both to simply `soong_build/_.xyz`
  """
  # using generators for indexed target filenames to archive pb files
  if not hasattr(read, 'bp2build_pb'):
    read.bp2build_pb = util.next_file(log_dir.joinpath(BP2BUILD_PB))
  if not hasattr(read, 'soong_pb'):
    read.soong_pb = util.next_file(log_dir.joinpath(SOONG_PB))

  soong_pb = util.get_out_dir().joinpath(SOONG_PB)
  bp2build_pb = util.get_out_dir().joinpath(BP2BUILD_PB)
  soong_proto = util.get_top_dir().joinpath(SOONG_PROTO)
  bp2build_proto = util.get_top_dir().joinpath(BP2BUILD_PROTO)

  events: list[PerfInfoOrEvent] = []
  if soong_pb.exists():
    events.extend(read_pb(soong_pb, soong_proto, SOONG_MSG))
    soong_pb.rename(next(read.soong_pb))
  if bp2build_pb.exists():
    events.extend(read_pb(bp2build_pb, bp2build_proto, BP2BUILD_MSG))
    bp2build_pb.rename(next(read.bp2build_pb))

  events.sort(key=lambda e: e.start_time)

  def unwrap(desc: str) -> str:
    return desc.replace('soong_build/soong_build', 'soong_build/_').replace(
        '.mixed_build.', '.')

  return {unwrap(f'{m.name}/{m.description}'): m.real_time for m in events}


def read_pb(
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


T = TypeVar('T')


# see test_union() for examples
def _union(list_a: list[T], list_b: list[T]) -> list[T]:
  """set union or list_a and list_b, ordering of elements in list_a takes
  precedence over ordering in list_b
  """
  acc = []
  seen = set()

  def helper(xs):
    for x in xs:
      if x not in seen:
        seen.add(x)
        acc.append(x)

  helper(list_a)
  helper(list_b)
  return acc


def write_csv_row(summary_csv: Path, row: dict[str, any]):
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
        # a soong-only build wouldn't have bp2build metrics
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


def main():
  p = argparse.ArgumentParser(
      formatter_class=argparse.RawTextHelpFormatter,
      description='read perf metrics and archive them at [LOG_DIR]')
  default_log_dir = util.get_out_dir().joinpath(util.DEFAULT_TIMING_LOGS_DIR)
  p.add_argument('-l', '--log-dir', type=Path, default=default_log_dir,
                 help='Directory for timing logs. Defaults to %(default)s\n'
                      'TIPS:\n'
                      '  Specify a directory outside of the source tree\n'
                      '  For a quick look at key metrics:\n'
                      f'    {util.get_summary_cmd(default_log_dir)}')
  p.add_argument('description')
  options = p.parse_args()

  summary_csv_path: Final[Path] = options.log_dir.joinpath(util.SUMMARY_CSV)
  perf = read(options.log_dir)
  row = {'build_type': 'MANUAL', 'description': options.description}
  write_csv_row(summary_csv_path, row | perf)


if __name__ == '__main__':
  main()
