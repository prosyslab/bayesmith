#!/usr/bin/env python3

import os
import sys
import subprocess


PROJECT_HOME = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
BENCHMARK_DIR = os.path.join(PROJECT_HOME, 'benchmarks')
BINGO_DIR = os.path.join(PROJECT_HOME, 'bingo')
RUN_BIN = os.path.join(PROJECT_HOME, 'bin', 'run.py')
RULE_PROB_TOK = 'rule-prob-'
FG_TOK = 'factor-graph-'
BINGO_STATS_TOK = 'bingo_stats-'
SPARROW_OUT = 'sparrow-out'


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
src_dir = os.path.join(PROJECT_HOME, sys.argv[3])
nth = sys.argv[4]

if analysis_type == "interval":
    benchmarks = interval_benchmarks
elif analysis_type == "taint":
    benchmarks = taint_benchmarks
else:
    print("Unsupported analysis type: " + analysis_type)
    exit(1)

training_benchs = list(filter(lambda b: target_program not in b, benchmarks))
test_bench = list(filter(lambda b: target_program in b, benchmarks))[0]

def make_timestamp(bench_name, mode):
    if mode == 'test':
        return "-".join([mode, target_program, nth])
    else:
        return "-".join([mode, target_program, bench_name, nth])

def count_iters(bnet_dir):
    return 

def find_last_fg(bench_name):
    last = len(list(filter(lambda name: FG_TOK + bench_name in name, os.listdir(src_dir))))
    return os.path.join(src_dir, FG_TOK + bench_name + '-' + str(last) + '.fg')

def find_last_rule_prob(bench_name):
    last = len(list(filter(lambda name: RULE_PROB_TOK in name, os.listdir(src_dir))))
    return os.path.join(src_dir, RULE_PROB_TOK + str(last) + '.txt')


def get_bench_dir(bench_name_ver):
    return os.path.join(BENCHMARK_DIR, bench_name_ver)

def get_bingo_stats_path(bench_dir, timestamp):
    return os.path.join(bench_dir, SPARROW_OUT, analysis_type, BINGO_STATS_TOK + timestamp + '.txt')

def run_em_train():
    print("Computing TRAIN results begins..")
    train_score = 0
    for tb in training_benchs:
        tb_name = tb.split('/')[0]
        ts = make_timestamp(tb_name, 'train')
        last_rule_prob_file = find_last_rule_prob(target_program)
        train_bench_dir = get_bench_dir(tb)
        em_train_cmd = [ RUN_BIN, "em-test", train_bench_dir, last_rule_prob_file, '--timestamp', ts ]
        p = subprocess.Popen(em_train_cmd)
        p.communicate()
        bingo_stats_path = get_bingo_stats_path(train_bench_dir, ts)
        with open(bingo_stats_path, 'r') as f:
            score = len(f.readlines()) - 1
            print(tb_name, score)
            train_score += score
    print("- Train score:", train_score)

def run_em_test():
    print("Computing TEST results begins..")
    ts = make_timestamp(None, 'test')
    last_rule_prob_file = find_last_rule_prob(target_program)
    test_bench_dir = get_bench_dir(test_bench)
    em_test_cmd = [ RUN_BIN, "em-test", test_bench_dir, last_rule_prob_file, '--timestamp', ts ]
    p = subprocess.Popen(em_test_cmd)
    p.communicate()
    bingo_stats_path = get_bingo_stats_path(test_bench_dir, ts)
    with open(bingo_stats_path, 'r') as f:
        test_score = len(f.readlines()) - 1
        print("- Test score:", test_score)


if __name__ == "__main__":
    print("EM results for", target_program)
    run_em_test()
    run_em_train()
