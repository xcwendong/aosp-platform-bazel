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

By default, the consumed file will be $OUT_DIR/soong_build_metrics.pb. You may
pass in a different file instead using the metrics_file flag.
"""

import argparse
import json
import os
import subprocess
import sys

from google.protobuf import json_format
from metrics_proto.metrics_pb2 import SoongBuildMetrics

class Event(object):
  """Contains nested event data.

  Fields:
    name: The short name of this event e.g. the 'b' in an event called a.b.
    start_time_relative_ns: Time since the epoch that the event started
    duration_ns: Duration of this event, including time spent in children.
  """

  def __init__(self, name, start_time_relative_ns, duration_ns):
    self.name = name
    self.start_time_relative_ns = start_time_relative_ns
    self.duration_ns = duration_ns


def _get_default_output_file():
  """Returns the filepath for the build output."""
  out_dir = os.getenv("OUT_DIR")
  if not out_dir:
    out_dir = "out"
  build_top = os.getenv("ANDROID_BUILD_TOP")
  if not build_top:
    raise Exception(
        "$ANDROID_BUILD_TOP not found in environment. Have you run lunch?")
  return os.path.join(build_top, out_dir, "soong_build_metrics.pb")


def _write_event(out, event):
  "Writes an event. See _write_events for args."
  out.write(
      "%(start)9s  %(duration)9s  %(name)s\n" % {
          "start": _format_ns(event.start_time_relative_ns),
          "duration": _format_ns(event.duration_ns),
          "name": event.name,
      })


def _format_ns(duration_ns):
  "Pretty print duration in nanoseconds"
  return "%.02fs" % (duration_ns / 1_000_000_000)


def _save_file(data, file):
  f = open(file, "w")
  f.write(data)
  f.close()


def main():
  # Parse args
  parser = argparse.ArgumentParser(description="", prog='analyze_build')
  parser.add_argument(
      "metrics_file",
      nargs="?",
      default=_get_default_output_file(),
      help="The soong_metrics file created as part of the last build. " +
      "Defaults to out/soong_build_metrics.pb")
  parser.add_argument(
      "--save-proto-output-file",
      nargs="?",
      default="",
      help="(Optional) The file to save the output of the printproto command to."
  )
  args = parser.parse_args()

  # Check the metrics file
  metrics_file = args.metrics_file
  if not os.path.exists(metrics_file):
    raise Exception("File " + metrics_file + " not found. Did you run a build?")

  soong_build_metrics = SoongBuildMetrics()
  with open(metrics_file, "rb") as f:
    soong_build_metrics.ParseFromString(f.read())

  if args.save_proto_output_file != "":
    json_out = json_format.MessageToJson(soong_build_metrics)
    _save_file(json_out, args.save_proto_output_file)

  # Bail if there are no events
  raw_events = soong_build_metrics.events
  if not raw_events:
    print("No events to display")
    return

  # Update the start times to be based on the first event
  first_time_ns = min([event.start_time for event in raw_events])
  events = []
  for raw_event in raw_events:
    event = Event(raw_event.description,
                  raw_event.start_time - first_time_ns,
                  raw_event.real_time)
    events += [event]

  # Sort by start time so the nesting also is sorted by time
  events.sort(key=lambda x: x.start_time_relative_ns)

  # Output the results
  print("    start   duration")

  for event in events:
    _write_event(sys.stdout, event)


if __name__ == "__main__":
  main()
