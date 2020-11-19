#!/usr/bin/env python3

import os
import sys
import subprocess


PROJECT_HOME = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
BENCHMARK_DIR = os.path.join(PROJECT_HOME, 'benchmarks')
BINGO_DIR = os.path.join(PROJECT_HOME, 'bingo')
BINGO_STATS_TOK = 'bingo_stats-'
SPARROW_OUT = 'sparrow-out'
ANALYSES = [ "interval", "taint" ]

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

def get_benchmarks(analysis_type):
    if analysis_type == "interval":
        return interval_benchmarks
    elif analysis_type == "taint":
        return taint_benchmarks
    else:
        print("Unsupported analysis type: " + analysis_type)
        exit(1)

def get_train_and_test_bench(benchmarks, target_program):
    training_benchs = list(filter(lambda b: target_program not in b, benchmarks))
    test_bench = list(filter(lambda b: target_program in b, benchmarks))[0]
    return training_benchs, test_bench

def make_timestamp(mode, target_program, bench_name):
    if mode == 'test':
        return "-".join([mode, target_program])
    else:
        return "-".join([mode, target_program, bench_name])

def get_bench_dir(bench_name_ver):
    return os.path.join(BENCHMARK_DIR, bench_name_ver)

def get_bingo_stats_path(bench_dir, timestamp, analysis_type):
    return os.path.join(bench_dir, SPARROW_OUT, analysis_type, BINGO_STATS_TOK + timestamp + '.txt')

def get_bingo_base_stats_path(bench_dir, analysis_type):
    return os.path.join(bench_dir, SPARROW_OUT, analysis_type, BINGO_STATS_TOK + 'baseline' + '.txt')

def parse_inv_count(f):
    line = f.readlines()[1]
    inv_count = line.split('\t')[-3]
    return inv_count

def stat_train(benchmarks, test_program, analysis_type):
    print("Computing TRAIN results begins..")
    train_score = 0
    training_benchs, _ = get_train_and_test_bench(benchmarks, test_program)
    for tb in training_benchs:
        tb_name = tb.split('/')[0]
        ts = make_timestamp('train', test_program, tb_name)
        train_bench_dir = get_bench_dir(tb)
        bingo_stats_path = get_bingo_stats_path(train_bench_dir, ts, analysis_type)
        bingo_base_stats_path = get_bingo_base_stats_path(train_bench_dir, analysis_type)
        with open(bingo_stats_path, 'r') as f:
            with open(bingo_base_stats_path, 'r') as g:
                cnt1 = parse_inv_count(f)
                cnt2 = parse_inv_count(g)
                print(tb_name, ':', cnt2, '->', cnt1)

if __name__ == "__main__":
    for atyp in ANALYSES:
        print("=== Stat. of", atyp, "===")
        benchmarks = get_benchmarks(atyp)
        for test_program in benchmarks:
            print('[', test_program, ']')
            tp_name = test_program.split('/')[0]
            stat_train(benchmarks, tp_name, atyp)
