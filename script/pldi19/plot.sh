#!/usr/bin/env bash

PROJECT_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd ../../ && pwd)"
PLOT_DIR=$PROJECT_HOME/script/rank-history-plot
PLOT_BIN=$PLOT_DIR/plot.py
T1=$1
T2=$2

source $(dirname "${BASH_SOURCE[0]}")/benchmark.sh
source $PLOT_DIR/env/bin/activate

function plot() {
  T1=$1
  T2=$2
  shift
  shift
  work=("$@")
  for p in "${work[@]}"; do
    readarray -d / -t temparr <<< $p
    progname=${temparr[0]}
    echo "============ $progname ============"
    $PLOT_BIN $progname $T1 $T2 -p
  done
}

echo "PLOT START"
plot $T1 $T2 "${interval_benchmarks[@]}"
plot $T1 $T2 "${taint_benchmarks[@]}"
deactivate
