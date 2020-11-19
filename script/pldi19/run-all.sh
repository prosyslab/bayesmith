#!/usr/bin/env bash

set -e

PROJECT_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd ../../ && pwd)"
BENCHMARK_DIR=$PROJECT_HOME/benchmarks
RESULT_DIR=$PROJECT_HOME/result

if [[ "$@" =~ "skip-analysis" ]]; then
  SKIP_ANALYSIS="true"
  SKIP_SOUFFLE="false"
elif [[ "$@" =~ "skip-souffle" ]]; then
  SKIP_ANALYSIS="true"
  SKIP_SOUFFLE="true"
else
  SKIP_ANALYSIS="false"
  SKIP_SOUFFLE="false"
fi

mkdir -p $RESULT_DIR

taint_benchmarks=(
  "jhead/3.0.0"
  "shntool/3.0.5"
  "autotrace/0.31.1"
  "sam2p/0.49.4"
  "sdop/0.61"
  "latex2rtf/2.1.1"
  "urjtag/0.8"
  "optipng/0.5.3"
  "a2ps/4.14"
)

interval_benchmarks=(
  "gzip/1.2.4a"
  "fribidi/1.0.7"
  "bc/1.06"
  "cflow/1.5"
  "patch/2.7.1"
  "wget/1.12"
  "readelf/2.24"
  "grep/2.19"
  "sed/4.3"
  "sort/7.2"
  "tar/1.28"
)

function run() {
  p=$1
  echo $p
  mkdir -p $RESULT_DIR/$p
  if [[ $SKIP_ANALYSIS == "false" ]]; then
    { $PROJECT_HOME/bin/run.py analyze $BENCHMARK_DIR/$p; } >&$RESULT_DIR/$p/analyze.log || {
      echo "Analyze Failed: $p"
      exit 1
    }
  fi
  if [[ $SKIP_SOUFFLE == "true" ]]; then
    { $PROJECT_HOME/bin/run.py --skip-souffle rank $BENCHMARK_DIR/$p; } >&$RESULT_DIR/$p/rank.log || {
      echo "Rank Failed: $p"
      exit 1
    }
  else
    { $PROJECT_HOME/bin/run.py rank --timestamp baseline $BENCHMARK_DIR/$p; } >&$RESULT_DIR/$p/rank.log || {
      echo "Rank Failed: $p"
      exit 1
    }
  fi
}

function run_all() {
  work=("$@")
  for p in "${work[@]}"; do
    run $p &
  done
}

run_all ${taint_benchmarks[@]}
run_all ${interval_benchmarks[@]}
wait
