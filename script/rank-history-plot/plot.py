#!/usr/bin/env python3

import matplotlib
import matplotlib.pyplot as plt
import pandas as pd
import argparse
import os
import json
import numpy as np

BASE_DIR = os.path.abspath(os.path.dirname(__file__))
PROJECT_HOME_DIR = os.path.dirname(os.path.dirname(BASE_DIR))
BENCHMARKS_DIR = os.path.join(PROJECT_HOME_DIR, "benchmarks")
BENCH_TXT = os.path.join(PROJECT_HOME_DIR, "benchmarks.txt")
MIN_V = 0.0
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
        return "", "", 6, alarm
    elif 'baseline' in alarm:
        return "dashed", "o", 6, "Bingo"
    else:
        return "solid", "*", 8, "BayeSmith"


def give_step_size(max_val):
    approx_interval_size = int(max_val / 5)
    if approx_interval_size <= 3:
        return 2
    if approx_interval_size <= 5:
        return 5
    elif approx_interval_size <= 10:
        return 10
    elif approx_interval_size <= 20:
        return 20
    elif approx_interval_size <= 50:
        return 50
    elif approx_interval_size <= 100:
        return 100
    elif approx_interval_size <= 200:
        return 200
    else:
        return 500


class Plotter:
    def __init__(self, benchmark, timestamps, is_pretty):
        self.benchmark = benchmark
        self.timestamps = timestamps
        self.rank_history = {}
        self.data_path_dict = get_data_path_dict(benchmark, timestamps)
        self.num_alarms = get_num_alarms(benchmark)
        self.img_path = get_img_path(timestamps, is_pretty)
        self.is_pretty = is_pretty

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

    def render_or(self, fname=None):
        """Render plot by traversing over history of each alarm.

        It takes save option into account on demand.
        """
        plt.rcParams['axes.titlepad'] = 10
        plt.rcParams['xtick.major.pad'] = 15
        plt.rcParams['ytick.major.pad'] = 15
        plt.rcParams['xtick.labelsize'] = 20
        plt.rcParams['ytick.labelsize'] = 20
        #plt.rcParams['xtick.major.width'] = 5
        #plt.rcParams['ytick.major.width'] = 5
        plt.rcParams['legend.fontsize'] = 25
        plt.figure(figsize=(21.8, 18))
        pos = '111'
        plt.subplot(pos)
        x_max = 0
        y_max = 0
        if self.is_pretty:
            new_dict = {}
            for alarm in reversed(list(self.rank_history.keys())):
                rank = self.rank_history[alarm]
                ts = alarm.split('@')[-1]
                if ts in new_dict:
                    new_dict[ts] = np.add(new_dict[ts], rank)
                else:
                    new_dict[ts] = rank
            for timestamp, rank in new_dict.items():
                if x_max < len(rank):
                    x_max = len(rank)
                if y_max < max(rank):
                    y_max = max(rank)
                linestyle, marker, markersize, label = get_label(
                    timestamp, self.is_pretty)
                plt.plot(rank,
                         linestyle=linestyle,
                         marker=marker,
                         markersize=markersize,
                         markevery=5,
                         label=label,
                         linewidth=5)
        else:
            for alarm in reversed(list(self.rank_history.keys())):
                rank = self.rank_history[alarm]
                if x_max < len(rank):
                    x_max = len(rank)
                if y_max < max(rank):
                    y_max = max(rank)
                linestyle, marker, markersize, label = get_label(
                    alarm, self.is_pretty)
                plt.plot(rank,
                         linestyle=linestyle,
                         marker=marker,
                         markersize=markersize,
                         markevery=5,
                         label=label,
                         linewidth=5)
        #plt.ylabel('Rank', size=100, labelpad=20)
        plt.ylabel('Rank', size=80, labelpad=20)
        #plt.xlabel('# Interactions', size=100, labelpad=20)
        plt.xlabel('# Interactions', size=80, labelpad=20)
        plt.xticks(np.arange(0, x_max, give_step_size(x_max)), size=70)
        plt.yticks(size=70)
        plt.legend(loc='upper right',
                   borderaxespad=0.5,
                   fancybox=True,
                   fontsize=75)
        plt.suptitle(self.benchmark, fontsize=100, x=0.6)
        plt.subplots_adjust(left=0.2,
                            top=0.9,
                            right=0.97,
                            bottom=0.15,
                            wspace=0.25)
        if not fname:
            fname = self.benchmark + '.pdf'
        save_path = os.path.join(self.img_path, fname)
        print('saved at', save_path)
        plt.savefig(save_path, format='pdf')


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
    parser.add_argument('-p',
                        '--pretty',
                        action='store_true',
                        help="render pretty plot")
    parser.add_argument('-o',
                        '--output',
                        metavar="OUTPUT_FILE",
                        help="name of output file")
    args = parser.parse_args()

    plotter = Plotter(args.benchmark, args.timestamp, args.pretty)
    plotter.transform_data()
    plotter.render_or(args.output)
