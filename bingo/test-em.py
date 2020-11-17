#!/usr/bin/env python3

import os
import sys


PROJECT_HOME = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
BENCHMARK_DIR = os.path.join(PROJECT_HOME, 'benchmarks')
BINGO_DIR = os.path.join(PROJECT_HOME, 'bingo')
BNET2FG_BIN = os.path.join(BINGO_DIR, "bnet2fg.py")


interval_benchmarks = [
    "wget/1.12", "readelf/2.24", "grep/2.19", "sed/4.3", "sort/7.2",
    "tar/1.28", "cflow/1.5", "bc/1.06", "fribidi/1.0.7",
    "patch/2.7.1", "gzip/1.2.4a"
]

taint_benchmarks = [
    "a2ps/4.14", "optipng/0.5.3", "shntool/3.0.5", "urjtag/0.8",
    "autotrace/0.31.1", "sam2p/0.49.4", "latex2rtf/2.1.1", "jhead/3.0.0",
    "sdop/0.61"
]

analysis_type = sys.argv[1]
target_program = sys.argv[2]
src_dir = sys.argv[3]

if analysis_type == "interval":
    benchmarks = interval_benchmarks
elif analysis_type == "taint":
    benchmarks = taint_benchmarks
else:
    print("Unsupported analysis type: " + analysis_type)
    exit(1)

train_benchmarks = [ target_program not in b for b in benchmarks ]
test_benchmark = [ target_program in b for b in benchmarks ]



