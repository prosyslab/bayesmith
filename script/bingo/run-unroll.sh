#!/usr/bin/env bash

PROJECT_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd ../../ && pwd)"

ANALYSIS_TYPE=$1
PROGRAM=$2

benchmarks=(
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

for bench in ${benchmarks[@]}; do
  if [[ $bench = $PROGRAM ]]; then
    FOUND="FOUND"
  fi
done

if [[ $FOUND = "" ]]; then
  echo "Unknown benchmark: $PROGRAM"
  exit 1
fi

if [[ $ANALYSIS_TYPE = "interval" ]]; then
  ATYP="BufferOverflow"
elif [[ $ANALYSIS_TYPE = "taint" ]]; then
  ATYP="IntegerOverflow"
else
  echo "Unknown analysis: $ANALYSIS_TYPE"
  exit 1
fi

echo "[$PROGRAM] Bingo_U START"

# Run Bingo with uniformly refined (unrolled) rule
$PROJECT_HOME/bingo/learn -test -timestamp unroll -analysis_type $ANALYSIS_TYPE -dl_from $PROJECT_HOME/datalog/$ATYP.unroll.dl $PROGRAM

echo "[$PROGRAM] Bingo_U END"
