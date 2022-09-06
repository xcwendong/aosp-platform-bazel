# bp2build progress graphs

This directory contains tools to generate reports and .png graphs of the
bp2build conversion progress, for any module.

This tool relies on `json-module-graph` and `bp2build` to be buildable targets
for this branch.

## Prerequisites

* `/usr/bin/dot`: turning dot graphviz files into .pngs

Tip: `--use_queryview=true` runs `bp2build-progress.py` with queryview.

## Instructions

# Generate the report for a module, e.g. adbd

```sh
bazel run --config=bp2build --config=linux_x86_64 \
  //build/bazel/scripts/bp2build-progress:bp2build-progress \
  -- report -m <module-name>
```

or:

```sh
bazel run --config=bp2build --config=linux_x86_64 \
  //build/bazel/scripts/bp2build-progress:bp2build-progress \
  -- report -m <module-name> --use-queryview
```

When running in report mode, you can also write results to a proto with the flag
`--proto-file`

# Generate the report for a module, e.g. adbd

```sh
bazel run --config=bp2build --config=linux_x86_64 \
  //build/bazel/scripts/bp2build-progress:bp2build-progress \
  -- graph -m adbd > /tmp/graph.in && \
  dot -Tpng -o /tmp/graph.png /tmp/graph.in
```

or:

```sh
bazel run --config=bp2build --config=linux_x86_64 \
  //build/bazel/scripts/bp2build-progress:bp2build-progress \
  -- graph -m adbd --use-queryview > /tmp/graph.in && \
  dot -Tpng -o /tmp/graph.png /tmp/graph.in
```
