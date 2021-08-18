#!/usr/bin/env bash

PROJECT_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd ../../ && pwd)"
BENCHMARK_DIR="$PROJECT_HOME/benchmarks"
TIMESTAMP=$1

source $(dirname "${BASH_SOURCE[0]}")/benchmark.sh

function report() {
  analysis=$1
  timestamp=$2
  shift
  shift
  work=("$@")
  for p in "${work[@]}"; do
    if [ -z $timestamp ]; then
      latest_stat=$(ls $BENCHMARK_DIR/$p/sparrow-out/$analysis | grep bingo_stats- | sort | tail -n1)
      prefix="bingo_stats-"
      suffix=".txt"
      time=${latest_stat#"$prefix"}
      time=${time%"$suffix"}
      line=$(wc -l $BENCHMARK_DIR/$p/sparrow-out/$analysis/$latest_stat | cut -f 1 -d ' ')
      cons=$(wc -l $BENCHMARK_DIR/$p/sparrow-out/$analysis/bnet-$time/named_cons_all.txt | cut -f 1 -d ' ')
      time=${time#"2020"}
    else
      line=$(wc -l $BENCHMARK_DIR/$p/sparrow-out/$analysis/bingo_stats-$timestamp.txt | cut -f 1 -d ' ')
      cons=$(wc -l $BENCHMARK_DIR/$p/sparrow-out/$analysis/bnet-$timestamp/named_cons_all.txt | cut -f 1 -d ' ')
      time=$timestamp
      time=${time#"2020"}
    fi
    last=$(($line - 1))
    printf "%-20s%-20s%10s%15s\n" $p $time $cons $last
  done
}

printf "%-20s%-20s%10s%15s\n" "Program" "Timestamp" "NumCons" "Iter"
report "interval" "$TIMESTAMP" "${interval_benchmarks[@]}"
report "taint" "$TIMESTAMP" "${taint_benchmarks[@]}"
