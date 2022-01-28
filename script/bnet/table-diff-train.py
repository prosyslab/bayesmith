#!/usr/bin/env python3

import os
import pandas as pd
import statistics

BASE_DIR = os.path.abspath(os.path.dirname(__file__))
PROJECT_HOME_DIR = os.path.dirname(os.path.dirname(BASE_DIR))
BENCHMARKS_DIR = os.path.join(PROJECT_HOME_DIR, "benchmarks")
BENCH_TXT = os.path.join(PROJECT_HOME_DIR, "benchmarks.txt")
COMBI_TXT = os.path.join(PROJECT_HOME_DIR, "bayesmith-80-combi.txt")


def get_benchmark_version(benchmark):
    """Return version of the benchmark."""
    benchmark_df = pd.read_csv(BENCH_TXT, header=0)
    version = ""
    for _, row in benchmark_df.iterrows():
        if row['Name'] == benchmark:
            version = row['Version']
    if not version:
        print('Error: ' + benchmark + ' is not known. Check benchmarks.txt')
        exit(1)

    return version


def get_combinations():
    with open(COMBI_TXT) as f:
        return [l.strip().split(",") for l in f.readlines()]


def get_num_iter(analsyis_typ, bench, timestamp):
    version = get_benchmark_version(bench)
    stats_file = os.path.join(BENCHMARKS_DIR, bench, version, "sparrow-out",
                              analsyis_typ, f"bingo_stats-{timestamp}.txt")
    with open(stats_file) as f:
        return len(f.readlines()) - 1


def print_table(plain_dict, combi_dict):
    header = [
        "Program", "BayeSmith_90:AVG", "BayeSmith_90:STDDEV",
        "BayeSmith_80:AVG", "BayeSmith_80:STDDEV"
    ]
    print(",".join(header))
    print(",".join([
        "Interval",
        str(statistics.mean(plain_dict["interval"])),
        str(statistics.pstdev(plain_dict["interval"])),
        str(statistics.mean(combi_dict["interval"])),
        str(statistics.pstdev(combi_dict["interval"]))
    ]))
    print(",".join([
        "Taint",
        str(statistics.mean(plain_dict["taint"])),
        str(statistics.pstdev(plain_dict["taint"])),
        str(statistics.mean(combi_dict["taint"])),
        str(statistics.pstdev(combi_dict["taint"]))
    ]))


if __name__ == "__main__":
    combis = get_combinations()
    plain_dict = {"interval": [], "taint": []}
    combi_dict = {"interval": [], "taint": []}
    for combi in combis:
        analysis_type = combi[0]
        bench1 = combi[1]
        bench2 = combi[2]
        plain_num_iter1 = get_num_iter(analysis_type, bench1, "final")
        plain_num_iter2 = get_num_iter(analysis_type, bench2, "final")
        plain_sum = plain_num_iter1 + plain_num_iter2
        plain_dict[analysis_type].append(plain_sum)

        combi_num_iter1 = get_num_iter(analysis_type, bench1,
                                       f"{bench1}-{bench2}")
        combi_sum_iter2 = get_num_iter(analysis_type, bench2,
                                       f"{bench1}-{bench2}")
        combi_sum = combi_num_iter1 + combi_sum_iter2
        combi_dict[analysis_type].append(combi_sum)

    print_table(plain_dict, combi_dict)
