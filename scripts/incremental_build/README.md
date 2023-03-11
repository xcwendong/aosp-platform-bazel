# How to Use

For automated use (e.g. in CI), use `main.py`. See its help
with `main.py --help`. Note that metrics collection relies on `printproto`
and `jq` tools being on $PATH.

The most basic invocation, e.g. `./incremental_build.py libc`, is logically
equivalent to

1. running `m --skip-soong-tests libc` and then
2. parsing `$OUTDIR/soong_metrics` and `$OUTDIR/bp2build_metrics.pb` files
3. Adding timing-related metrics from those files
   into `out/timing_logs/metrics.csv`

There are a number of CUJs set up in `cuj_catalog.py` and they are run
sequentially, such that each row in `metrics.csv` are the timings of various "
events" during an incremental build.

You may also add rows to `metrics.csv` after a manual run,
using `perf_metrics.py`
script. This is particularly useful when you don't want to
modify `cuj_catalog.py`
for one-off tests.

Currently:

1. run a build (conceptually, m droid)
2. printproto to parse metrics related pb files
3. use jq to filter data
4. collate data into a csv file
5. goto 1 until various CUJs are exhausted

For CI, we should:

1. run a build with some identifiable tag (not sure what mechanisms are
   available)
2. goto 1 until various CUJs are exhausted
3. rely on plx to collate data from all builds and provide a filtering mechanism
   based on that tag from step 1
