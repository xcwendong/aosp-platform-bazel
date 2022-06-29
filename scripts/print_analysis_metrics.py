#!/usr/bin/env python3
#
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
"""A tool to print human-readable metrics information regarding the last build.

It is assumed that this is run from bazel/scripts. By default, the consumed file
will be out/soong_build_metrics.pb. You may pass in a different file instead
using the build_metrics_file flag.
"""
import argparse
import json
import os
import subprocess

from typing import Dict


def _get_proto_output_file():
  """Returns the location of the proto file used for analyzing out/soong_build_metrics.pb.

  This corresponds to soong/ui/metrics/metrics_proto/metrics.proto.
  """
  return os.getenv('ANDROID_BUILD_TOP') + '/build/soong/ui/metrics/metrics_proto/metrics.proto'


def _get_default_output_file():
  """Returns the filepath for the build output."""
  return os.getenv('ANDROID_BUILD_TOP') + '/out/soong_build_metrics.pb'


def _add_subdicts_to_output(runtime_dict, event):
  """Adds nested events to a dict as appropriate.

  Nested events will receive their own nested dicts inside the passed dict, e.g.:
  'alpha.bravo.charlie = 2' -> runtime_dict['alpha']['bravo']['charlie'] = 2
  """
  sub_events = event['description'].split('.')

  last_dict = None
  last_parent_dict = runtime_dict

  for sub_event in sub_events:
    last_dict = last_parent_dict[sub_event] if sub_event in last_parent_dict else dict()
    last_parent_dict[sub_event] = last_dict
    last_parent_dict = last_dict

  time_in_seconds = event['real_time'] / 1_000_000_000
  last_dict[''] = f'{time_in_seconds}s'


def _get_formatted_output(event, cumulative_output, indent_str, separator):
  """Populates the given list with the output strings relevant for the given event.

  The event parameter contains the (presumably) nested dicts of top-level and
  sub-events that will be organized as such in output. cumulative_output will
  be modified to add in the nested details.
  If calling this with an empty cumulative_output, indent_str and separator
  should both be blank. The indentation will increase by one tab per nested
  level.
  """
  for key, item in event.items():
    if isinstance(item, Dict):
      # Recurse through the sub-level
      event_time = '{:.2f}'.format(float(item[''][0:-1]))
      cumulative_output.append(f'{separator}{indent_str}{key}: {event_time}s')
      _get_formatted_output(item, cumulative_output, indent_str+'\t', '\n')
    elif key != '':
      event_time = '{:.2f}'.format(float(item[0:-1]))
      cumulative_output.append(f'{separator}{indent_str}{key}: {event_time}s\n')
    separator = '\n'


def main():
  parser = argparse.ArgumentParser(description='')
  parser.add_argument('metrics_file', nargs='?',
                      default=_get_default_output_file(),
                      help='The soong_metrics file created as part of the last build. ' +
                      'Defaults to out/soong_build_metrics.pb')
  args = parser.parse_args()

  metrics_file = args.metrics_file
  if not os.path.exists(metrics_file):
    raise Exception('File ' + metrics_file + ' not found. Did you run a build?')

  proto_file = _get_proto_output_file()

  if not os.path.exists(proto_file):
    raise Exception('$ANDROID_BUILD_TOP not found in environment. Have you run lunch?')

  json_out = subprocess.check_output([r"""printproto --proto2 --raw_protocol_buffer --json --json_accuracy_loss_reaction=ignore \
                                      --message=soong_build_metrics.SoongBuildMetrics --multiline \
                                      --proto=""" + proto_file + ' ' + metrics_file
                                      ], shell=True)
  # output is a dict of dicts, containing nested events and eventually their real_time values
  # output["alpha"]["one"]["cat"] is the runtime (in seconds) of event alpha.one.cat.
  output = dict()

  build_output = json.loads(json_out)

  events = build_output['events']
  for event in events:
    _add_subdicts_to_output(output, event)

  total = 0

  formatted_output = []
  _get_formatted_output(output, formatted_output, '', '')
  for _, event_dict in output.items():
    total += float(event_dict[''][0:-1])
  print(''.join(formatted_output))
  print('Total: ', '{:.2f}'.format(total) + 's')


if __name__ == '__main__':
  main()
