#!/usr/bin/env python3

from numpy.core.fromnumeric import prod
import pandas as pd
import argparse
import os
import json

BASE_DIR = os.path.abspath(os.path.dirname(__file__))
PROJECT_HOME_DIR = os.path.dirname(os.path.dirname(BASE_DIR))
BENCHMARKS_DIR = os.path.join(PROJECT_HOME_DIR, "benchmarks")
BENCH_TXT = os.path.join(PROJECT_HOME_DIR, "benchmarks.txt")
MIN_V = 0.0


def get_benchmark_info(benchmark):
    """Return version of the benchmark and analysis type by sparrow.
    """
    benchmark_df = pd.read_csv(BENCH_TXT, header=0)
    version = ""
    for _, row in benchmark_df.iterrows():
        if row['Name'] == benchmark:
            version = row['Version']
    if not version:
        print('Error: ' + benchmark + ' is not known. Check benchmarks.txt')
        exit(1)

    # Read sparrow-config.json
    sparrow_config = os.path.join(BENCHMARKS_DIR, benchmark,
                                  'sparrow-config.json')
    with open(sparrow_config, 'r') as g:
        data = json.load(g)
        analysis_type = data['analysis_type']

    return version, analysis_type


def get_data_path(benchmark, timestamp):
    version, atyp = get_benchmark_info(benchmark)
    data_path = os.path.join(BENCHMARKS_DIR, benchmark, version, 'sparrow-out',
                             atyp, 'bingo_combined-' + timestamp)
    return data_path


def get_data_path_dict(benchmark, timestamps):
    data_path_dict = {}
    for t in timestamps:
        data_path = get_data_path(benchmark, t)
        data_path_dict[t] = data_path
    return data_path_dict


def get_alarm_path(benchmark):
    version, atyp = get_benchmark_info(benchmark)
    alarm_path = os.path.join(BENCHMARKS_DIR, benchmark, version,
                              'sparrow-out', atyp, 'bnet-baseline',
                              'Alarm.txt')
    return alarm_path


def get_cons_all2bnet_path(benchmark, timestamp):
    version, atyp = get_benchmark_info(benchmark)
    alarm_path = os.path.join(BENCHMARKS_DIR, benchmark, version,
                              'sparrow-out', atyp, 'bnet-' + timestamp,
                              'cons_all2bnet.log')
    return alarm_path


def get_bingo_stat_path(benchmark, timestamp):
    version, atyp = get_benchmark_info(benchmark)
    alarm_path = os.path.join(BENCHMARKS_DIR, benchmark, version,
                              'sparrow-out', atyp,
                              'bingo_stats-' + timestamp + '.txt')
    return alarm_path


def get_num_alarms(benchmark):
    txt_path = get_alarm_path(benchmark)
    with open(txt_path, 'r') as f:
        return len(f.readlines())


def get_benchmarks():
    """Get list of benchmarks which are candidate benchmark.
    """
    df = pd.read_csv(BENCH_TXT, header=0, usecols=['Name'])
    return df['Name'].to_list()


class Bnet:
    def __init__(self, benchmark, timestamps):
        self.benchmark = benchmark
        self.timestamps = timestamps
        self.rank_history = {}
        self.data_path_dict = get_data_path_dict(benchmark, timestamps)
        self.num_alarms = get_num_alarms(benchmark)

    def transform_data(self):
        for timestamp, data_path in self.data_path_dict.items():
            try:
                df = pd.read_csv(os.path.join(data_path, 'init.out'),
                                 sep='\t',
                                 header=0,
                                 usecols=['Rank', 'Ground', 'Tuple'])
            except IOError as e:
                print('Error: ', e)
                print('Error: Check if init.out exists in ' + data_path)
                exit(1)

            filtered_df = df[df.Ground == 'TrueGround'].reset_index(
                drop=True)[['Rank', 'Tuple']]
            for _, true_alarm in filtered_df.iterrows():
                self.rank_history[true_alarm['Tuple'] + '@' +
                                  timestamp] = [true_alarm['Rank']]

            worklist = os.listdir(data_path)
            num_work = len(worklist) - 2
            for work in range(num_work):
                try:
                    df = pd.read_csv(os.path.join(data_path,
                                                  str(work) + '.out'),
                                     sep='\t',
                                     header=0,
                                     usecols=['Rank', 'Ground', 'Tuple'])
                except IOError as e:
                    print('Error: ', e)
                    print('Error: Check if ' + str(work) + '.out exists in' +
                          data_path)
                    exit(1)

                filtered_df = df[df.Ground == 'TrueGround'].reset_index(
                    drop=True)[['Rank', 'Tuple']]
                for _, true_alarm in filtered_df.iterrows():
                    self.rank_history[true_alarm['Tuple'] + '@' +
                                      timestamp] += [true_alarm['Rank']]

    def compute_avg_feedbk_time(self):
        l = []
        for timestamp in self.timestamps:
            bingo_stat_path = get_bingo_stat_path(self.benchmark, timestamp)
            df = pd.read_csv(bingo_stat_path,
                             sep='\t',
                             header=0,
                             usecols=['Time(s)'])
            l.append(round(df.mean().values[0], 2))
        return l

    def measure_bnet_size(self):
        l = []
        for timestamp in self.timestamps:
            cons_all2bnet_path = get_cons_all2bnet_path(
                self.benchmark, timestamp)
            with open(cons_all2bnet_path, 'r') as f:
                lines = f.readlines()
                num_clauses = lines[0].split(' ')[-2]
                num_tuples = lines[1].split(' ')[-2]
            l.append(int(num_tuples))
            l.append(int(num_clauses))
        return l

    def count_vc(self):
        vc_dict = {}
        for alarm, _ in self.rank_history.items():
            ts = alarm.split('@')[-1]
            vc_dict[ts] = []
        for alarm, rank in self.rank_history.items():
            ts = alarm.split('@')[-1]
            for i in range(len(rank) - 1):
                diff = rank[i + 1] - rank[i]
                vc_size = diff / float(self.num_alarms)
                if vc_size > MIN_V:
                    vc_dict[ts] += [diff]
        l = []
        for ts, vc_lst in vc_dict.items():
            if len(vc_lst) == 0:
                avg = 0.0
            else:
                avg = sum(vc_lst) / len(vc_lst)
            l.append(len(vc_lst))
            l.append(round(avg, 2))
        return l

    def make_fg_row(self):
        fg_lst = self.count_vc()
        new_lst = []
        for i, v in enumerate(fg_lst):
            if i % 2 == 1:
                n = fg_lst[i - 1]
                product = n * round(v, 2)
                new_lst.append(v)
                new_lst.append(round(product, 1))
            else:
                new_lst.append(v)
        return [self.benchmark] + new_lst

    def make_size_row(self):
        tc_lst = self.measure_bnet_size()
        time_lst = self.compute_avg_feedbk_time()
        size_lst = []
        for i, v in enumerate(tc_lst):
            size_lst.append(v)
            if i % 2 == 1:
                time = time_lst[int(i / 2)]
                size_lst.append(time)
        return [self.benchmark] + size_lst

    def add_row(self, typ, table):
        self.transform_data()
        if typ == 'fg':
            table.append(self.make_fg_row())
        elif typ == 'size':
            table.append(self.make_size_row())
        else:
            print("Error: unknown table type: " + typ)


headers = {
    'fg': [
        'Program', 'Bingo:Freq', 'Bingo:Mag', 'Bingo:FxM', 'Bayes:Freq',
        'Bayes:Mag', 'Bayes:FxM'
    ],
    'size': [
        'Program', 'Bingo:#T', 'Bingo:#C', 'Bingo:Time', 'Bayes:#T',
        'Bayes:#C', 'Bayes:Time'
    ]
}


def add_table(table, typ, sub_table):
    if len(sub_table) != 0:
        if typ == 'fg':
            table += sub_table
        value_only = [r[1:] for r in sub_table]
        table += [['Average' if typ == 'fg' else 'Taint'] +
                  [sum(i) / len(sub_table) for i in zip(*value_only)]]


def round_val(typ, ind, val):
    if ind > 0:
        nth = (ind - 1) % 3
        if typ == 'fg':
            if nth == 0:
                return int(round(val, 0))
            else:
                return round(val, 1)
        else:
            if nth == 2:
                return round(val, 1)
            else:
                return int(round(val, 0))
    else:
        return val


def table_to_csv(table, typ):
    rows = [
        ",".join([
            str(v if isinstance(v, str) else round_val(typ, i, v))
            for i, v in enumerate(row)
        ]) for row in table
    ]
    return "\n".join(rows)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Measuring Bayesian networks')
    parser.add_argument('benchmark',
                        metavar='BENCHMARK',
                        help="name of target benchmark",
                        choices=get_benchmarks() + ["all"])
    parser.add_argument('timestamp',
                        metavar='TIMESTAMP',
                        nargs='+',
                        help="timestamp(s) of ranking execution")
    parser.add_argument('--table',
                        type=str,
                        choices=['fg', 'size'],
                        required=True)

    args = parser.parse_args()

    header = headers[args.table]
    table = [header]
    sub_tables = {'interval': [], 'taint': []}
    if args.benchmark == "all":
        for benchmark in get_benchmarks():
            analysis_type = get_benchmark_info(benchmark)[1]
            bnet = Bnet(benchmark, args.timestamp)
            bnet.add_row(args.table, sub_tables[analysis_type])
        itv_table = sub_tables['interval']
        add_table(table, args.table, itv_table)
        tnt_table = sub_tables['taint']
        add_table(table, args.table, tnt_table)
    else:
        bnet = Bnet(args.benchmark, args.timestamp)
        bnet.add_row(args.table, table)

    file_name = 'bnet-fg.csv' if args.table == 'fg' else 'bnet-size.csv'
    with open(file_name, 'w') as f:
        csv = table_to_csv(table, args.table)
        f.write(csv)
