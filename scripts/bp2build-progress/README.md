# bp2build progress graphs

This directory contains tools to generate reports and .png graphs of the
bp2build conversion progress, for any module.

## Prerequisites

* `/usr/bin/dot`: turning dot graphviz files into .pngs
* `/usr/bin/jq`: running the query scripts over the json-module-graph.
* `converted.txt`: a static file list of module names converted by bp2build.
  This is created manually, but we could make bp2build emit such a file
  automatically in @soong_injection. Tracked in b/199837056.

## Instructions

# Generate the report for a module, e.g. adbd

```
./bp2build-progress.py report adbd
```

# Generate the report for a module, e.g. adbd

```
./bp2build-progress.py graph adbd > graph.in && dot -Tpng -o graph.png graph.in
```
