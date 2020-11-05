#!/usr/bin/env bash

BENCHMARK_DIR=$1
BASE_DIR=$(dirname "$0")
THIS_FILE=${0##*/}
OUTPUT_FILE='facts.txt'

if [ $# -ne 1 ]; then
    echo "Usage: ./$THIS_FILE [ PATH_TO_BENCHMARKS ]"
    exit 1
fi

if [ -d $BENCHMARK_DIR ]; then
    ABSPATH=$(cd "$BENCHMARK_DIR"; printf %s "$PWD")
    # Create facts.txt
    echo $ABSPATH >$BASE_DIR/$OUTPUT_FILE
    echo -e "Generating $OUTPUT_FILE.."
    # Create images directory
    if [ -d $BASE_DIR/images ]; then 
        echo "images directory already exists"
    else
        mkdir $BASE_DIR/images
        echo "Creating images directory .."
    fi
else
    echo "Error: $BENCHMARK_DIR is not available directory"
    exit 1
fi

echo "Configuration success"
