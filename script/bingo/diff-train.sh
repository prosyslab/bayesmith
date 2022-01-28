#!/usr/bin/env bash

CSV_FILE=$1

while IFS=',' read -r x y z; do
  echo "[train] $x: $y-$z"
  bingo/learn -reuse -out_dir train-$y-$z -analysis_type $x $y $z >/dev/null &
done <$CSV_FILE
wait

while IFS=',' read -r x y z; do
  echo "[test] $x: $y-$z"
  bingo/learn -test -out_dir test-$y-$z -analysis_type $x -timestamp $y-$z -dl_from train-$y-$z/$y-$z/rule-$y-$z.dl $y >/dev/null &
  bingo/learn -test -out_dir test-$y-$z -analysis_type $x -timestamp $y-$z -dl_from train-$y-$z/$y-$z/rule-$y-$z.dl $z >/dev/null &
done <$CSV_FILE
wait
