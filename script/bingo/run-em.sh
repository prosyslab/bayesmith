#!/usr/bin/env bash

PROJECT_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd ../../ && pwd)"
BENCHMARK_DIR=$PROJECT_HOME/benchmarks

ANALYSIS_TYPE=$1
PROGRAM=$2
NTH=0

benchmarks=(
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

for bench in ${benchmarks[@]}; do
  prog=${bench%%/*}
  ver=${bench#*/}
  if [[ $prog = $PROGRAM ]]; then
    VERSION=$ver
  fi
done

if [[ $VERSION = "" ]]; then
  echo "Unknown benchmark: $PROGRAM"
  exit 1
fi

# Run EM algorithm with 12h timeout
echo "[$PROGRAM] EM TRAIN START"
$PROJECT_HOME/bingo/em.py $ANALYSIS_TYPE $PROGRAM $NTH &
TP=$!
sleep 12h
kill -9 $TP
echo "[$PROGRAM] EM TRAIN END"

# Find the last rule-prob.txt
LEARN_OUT_DIR=weight-learn-out-$PROGRAM-$NTH
LAST=$(ls -al $LEARN_OUT_DIR/rule-prob-* | wc -l)
RULE_PROB_TXT=$LEARN_OUT_DIR/rule-prob-$LAST.txt

# Run test
echo "[$PROGRAM] EM TEST START"
$PROJECT_HOME/bin/run.py em-test --timestamp em $BENCHMARK_DIR/$PROGRAM/$VERSION $RULE_PROB_TXT