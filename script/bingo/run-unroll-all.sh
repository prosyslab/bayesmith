#!/usr/bin/env bash

PROJECT_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd ../../ && pwd)"
RESULT_DIR=$PROJECT_HOME/result

mkdir -p $RESULT_DIR

taint_benchmarks=(
  "jhead"
  "shntool"
  "autotrace"
  "sam2p"
  "sdop"
  "latex2rtf"
  "urjtag"
  "optipng"
  "a2ps"
)

interval_benchmarks=(
  "gzip"
  "fribidi"
  "bc"
  "cflow"
  "patch"
  "wget"
  "readelf"
  "grep"
  "sed"
  "sort"
  "tar"
)

function run() {
  atyp=$1
  p=$2
  { $PROJECT_HOME/script/bingo/run-unroll.sh $atyp $p; } >&$RESULT_DIR/$p.unroll.log || {
    echo "Bingo_U Failed: $p"
    exit 1
  }
}

function run_all() {
  atyp=$1
  work=("${@:2}")
  for p in "${work[@]}"; do
    run $atyp $p &
  done
}

run_all taint ${taint_benchmarks[@]}
run_all interval ${interval_benchmarks[@]}
wait
