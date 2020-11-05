#!/bin/bash

OUTPUT_DIR=$1
ANALYSIS=$2
BNET=$3
FACT_FILE=$4

cat $OUTPUT_DIR/$ANALYSIS/$BNET/$FACT_FILE |
  sed 's/^/Alarm(/' |
  sed 's/\t/,/' | sed 's/$/)/g' \
  >$OUTPUT_DIR/$ANALYSIS/$BNET/${FACT_FILE%%.*}.txt
