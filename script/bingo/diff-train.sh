#!/usr/bin/env bash

CSV_FILE=$1

while IFS=',' read -r x y z; do
  echo "$x: $y-$z"
  bingo/learn -reuse -analysis_type $x $y $z &
done <$CSV_FILE

wait
