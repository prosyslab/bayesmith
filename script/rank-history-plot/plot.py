#!/usr/bin/env python3

import matplotlib
import matplotlib.pyplot as plt
import pandas as pd
import argparse
import os
import errno
import json
import numpy as np

BASE_DIR = os.path.dirname(__file__)
FACTS_TXT = os.path.join(BASE_DIR, "facts.txt")
BENCH_TXT = os.path.join(BASE_DIR, "benchmarks.txt")
MIN_V = 0.01
PRETTY_DST = "images-final"


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

    # Read info.json
    with open(FACTS_TXT, 'r') as f:
        benchmarks_dir = f.read().strip()
        info_json = os.path.join(benchmarks_dir, benchmark, version, 'sparrow',
                                 'info.json')
        with open(info_json, 'r') as g:
            data = json.load(g)
            analysis_type = data['type']

    return version, analysis_type


def get_data_path(benchmark, timestamp):
    version, atyp = get_benchmark_info(benchmark)
    try:
        with open(FACTS_TXT, 'r') as f:
            benchmarks_dir = f.read().strip()
            data_path = os.path.join(benchmarks_dir, benchmark, version,
                                     'sparrow-out', atyp,
                                     'bingo_combined-' + timestamp)
            return data_path
    except FileNotFoundError as e:
        print('Error: ', e)
        print('Error: Check if facts.txt exists')
        print('Error: Make sure your configuration succeeds')
        exit(1)


def get_data_path_dict(benchmark, timestamps):
    data_path_dict = {}
    for t in timestamps:
        data_path = get_data_path(benchmark, t)
        data_path_dict[t] = data_path
    return data_path_dict


def get_alarm_path(benchmark):
    version, atyp = get_benchmark_info(benchmark)
    try:
        with open(FACTS_TXT, 'r') as f:
            benchmarks_dir = f.read().strip()
            alarm_path = os.path.join(benchmarks_dir, benchmark, version,
                                     'sparrow-out', atyp,
                                     'bnet-baseline', 'Alarm.txt')
            return alarm_path
    except FileNotFoundError as e:
        print('Error: ', e)
        print('Error: Check if facts.txt exists')
        print('Error: Make sure your configuration succeeds')
        exit(1)

def get_cons_all2bnet_path(benchmark, timestamp):
    version, atyp = get_benchmark_info(benchmark)
    try:
        with open(FACTS_TXT, 'r') as f:
            benchmarks_dir = f.read().strip()
            alarm_path = os.path.join(benchmarks_dir, benchmark, version,
                                     'sparrow-out', atyp,
                                     'bnet-' + timestamp, 'cons_all2bnet.log')
            return alarm_path
    except FileNotFoundError as e:
        print('Error: ', e)
        print('Error: Check if facts.txt exists')
        print('Error: Make sure your configuration succeeds')
        exit(1)

def get_bingo_stat_path(benchmark, timestamp):
    version, atyp = get_benchmark_info(benchmark)
    try:
        with open(FACTS_TXT, 'r') as f:
            benchmarks_dir = f.read().strip()
            alarm_path = os.path.join(benchmarks_dir, benchmark, version,
                                     'sparrow-out', atyp,
                                     'bingo_stats-' + timestamp + '.txt')
            return alarm_path
    except FileNotFoundError as e:
        print('Error: ', e)
        print('Error: Check if facts.txt exists')
        print('Error: Make sure your configuration succeeds')
        exit(1)


def get_num_alarms(benchmark):
    txt_path = get_alarm_path(benchmark)
    with open(txt_path, 'r') as f:
        return len(f.readlines())

def get_img_path(timestamps, is_pretty):
    if is_pretty:
        return os.path.join(BASE_DIR, PRETTY_DST)
    else:
        stamp = "+".join(timestamps)
        return os.path.join(BASE_DIR, "images-" + stamp)


def get_benchmarks():
    """Get list of benchmarks which are candidate benchmark.
    """
    df = pd.read_csv(BENCH_TXT, header=0, usecols=['Name'])
    return df['Name'].to_list()

def get_label(alarm, is_pretty):
    if not is_pretty:
        return "", "", alarm
    elif 'baseline' in alarm:
        return "solid", ".", 5, "Vanilla Bingo"
    else:
        return "dashed", "*", 7, "BayeSmith"


class Plotter:
    def __init__(self, benchmark, timestamps, is_pretty):
        self.benchmark = benchmark
        self.timestamps = timestamps
        self.rank_history = {}
        self.data_path_dict = get_data_path_dict(benchmark, timestamps)
        self.num_alarms = get_num_alarms(benchmark)
        self.img_path = get_img_path(timestamps, is_pretty)
        self.is_pretty = is_pretty
        print('[Info] ' + benchmark + ' is specified')
        print('[Info] # Alarms: ' + str(self.num_alarms))

    def try_import_render_console(self):
        try:
            import tkinter
            matplotlib.use('TkAgg')
        except ImportError:
            print(
                'Warning: One should install tkinter to render plot in local console'
            )
            return False
        return True

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

    def compute_avg_bingo_feedbk_time(self):
        for timestamp in self.timestamps:
            bingo_stat_path = get_bingo_stat_path(self.benchmark, timestamp)
            df = pd.read_csv(bingo_stat_path, sep='\t', header=0, usecols=['Time(s)'])
            print("[Info] Avg Bingo feedback time at " + timestamp + ":")
            print(df.mean())

    def measure_bnet_size(self):
        for timestamp in self.timestamps:
            cons_all2bnet_path = get_cons_all2bnet_path(self.benchmark, timestamp)
            with open(cons_all2bnet_path, 'r') as f:
                lines = f.readlines()
                num_clause = lines[0].split(' ')[-2]
                num_tuples = lines[1].split(' ')[-2]
            print("[Info] # Clauses at " + timestamp + " : " + num_clause)
            print("[Info] # Tuples at " + timestamp + " : " + num_tuples)


    def make_dir(self):
        """Make a directory where plots are being saved.
        """
        try:
            os.mkdir(self.img_path)
        except OSError as e:
            if e.errno != errno.EEXIST:
                print('Error: ', e)
                exit(1)


    def count_vc(self):
        dic = {}
        for alarm, _ in self.rank_history.items():
            ts = alarm.split('@')[-1]
            dic[ts] = []
        for alarm, rank in self.rank_history.items():
            temp = 0
            for i in range(len(rank) - 1):
                diff = rank[i + 1] - rank[i]
                # if diff > 0:
                vc_size = diff / float(self.num_alarms)
                if vc_size > MIN_V:
                    ts = alarm.split('@')[-1]
                    dic[ts] += [ diff ]
        for ts, vc_lst in dic.items():
            print("[Info] # VC in " + ts + ": " + str(len(vc_lst)))
            if len(vc_lst) == 0:
                avg = "NO VCs"
            else:
                avg = sum(vc_lst) / len(vc_lst)
            print("[Info] Avg. VC size in " + ts + ": " + str(avg))

    def render_or(self, is_saving=True, fname=None):
        """Render plot by traversing over history of each alarm.

        It takes save option into account on demand.
        """
        plt.figure(figsize=(10, 10))
        if self.is_pretty:
            new_dict = {}
            for alarm, rank in self.rank_history.items():
                ts = alarm.split('@')[-1]
                if ts in new_dict:
                    new_dict[ts] = np.add(new_dict[ts], rank)
                else:
                    new_dict[ts] = rank
            for timestamp, rank in new_dict.items():
                linestyle, marker, markersize, label = get_label(timestamp, self.is_pretty)
                plt.plot(rank, linestyle=linestyle, marker=marker, markersize=markersize, label=label)
        else:
            for alarm, rank in self.rank_history.items():
                linestyle, marker, markersize, label = get_label(alarm, self.is_pretty)
                plt.plot(rank, linestyle=linestyle, marker=marker, markersize=markersize, label=label)
        plt.ylabel('Rank', size=20)
        plt.xlabel('User interaction', size=20)
        plt.xticks(size=20)
        plt.yticks(size=20)
        plt.legend(loc='upper right', borderaxespad=1, fancybox=True, fontsize=20)
        plt.suptitle(self.benchmark, fontsize=16, y=0.97)
        plt.tight_layout()
        if is_saving:
            if not fname:
                fname = self.benchmark + '.png'
            save_path = os.path.join(self.img_path, fname)
            plt.savefig(save_path)

    def show(self):
        if self.try_import_render_console():
            plt.show()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Plotting rank history')
    parser.add_argument('benchmark',
                        metavar='BENCHMARK',
                        help="name of target benchmark",
                        choices=get_benchmarks())
    parser.add_argument('timestamp',
                        metavar='TIMESTAMP',
                        nargs='+',
                        help="timestamp(s) of ranking execution")
    parser.add_argument('-s',
                        '--show',
                        action='store_true',
                        help="render plot in local console")
    parser.add_argument('-p',
                        '--pretty',
                        action='store_true',
                        help="render pretty plot")
    parser.add_argument('--no-save',
                        action='store_true',
                        help="do not save the plot")
    parser.add_argument('-o',
                        '--output',
                        metavar="OUTPUT_FILE",
                        help="name of output file")
    args = parser.parse_args()

    plotter = Plotter(args.benchmark, args.timestamp, args.pretty)
    plotter.transform_data()
    save = not args.no_save
    if save:
        plotter.make_dir()
    else:
        print('[Info] no-save option is set')
    plotter.count_vc()
    plotter.compute_avg_bingo_feedbk_time()
    plotter.measure_bnet_size()
    plotter.render_or(save, args.output)
    if args.show:
        print('[Info] show option is set')
        plotter.show()
