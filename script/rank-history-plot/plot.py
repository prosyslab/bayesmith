#!/usr/bin/env python3

import matplotlib
import matplotlib.pyplot as plt
import pandas as pd
import argparse
import os
import errno
import json

BASE_DIR = os.path.dirname(__file__)
FACTS_TXT = os.path.join(BASE_DIR, "facts.txt")
BENCH_TXT = os.path.join(BASE_DIR, "benchmarks.txt")


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


def get_img_path(timestamps):
    stamp = "+".join(timestamps)
    return os.path.join(BASE_DIR, "images-" + stamp)


def get_benchmarks():
    """Get list of benchmarks which are candidate benchmark.
    """
    df = pd.read_csv(BENCH_TXT, header=0, usecols=['Name'])
    return df['Name'].to_list()


class Plotter:
    def __init__(self, benchmark, timestamps):
        self.benchmark = benchmark
        self.timestamps = timestamps
        self.rank_history = {}
        self.data_path_dict = get_data_path_dict(benchmark, timestamps)
        self.img_path = get_img_path(timestamps)
        print('Info: ' + benchmark + ' is specified')

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
                self.rank_history[true_alarm['Tuple'] + '-' +
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
                    self.rank_history[true_alarm['Tuple'] + '-' +
                                      timestamp] += [true_alarm['Rank']]

    def make_dir(self):
        """Make a directory where plots are being saved.
        """
        try:
            os.mkdir(self.img_path)
        except OSError as e:
            if e.errno != errno.EEXIST:
                print('Error: ', e)
                exit(1)

    def render_or(self, is_saving=True, fname=None):
        """Render plot by traversing over history of each alarm.

        It takes save option into account on demand.
        """
        # TODO: eye-soaring plot style
        plt.figure(figsize=(10, 10))
        for alarm, rank in self.rank_history.items():
            plt.plot(rank, label=alarm)
        plt.ylabel('rank')
        plt.legend(loc='upper right', borderaxespad=1, fancybox=True)
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
    parser.add_argument('--no-save',
                        action='store_true',
                        help="do not save the plot")
    parser.add_argument('-o',
                        '--output',
                        metavar="OUTPUT_FILE",
                        help="name of output file")
    args = parser.parse_args()

    plotter = Plotter(args.benchmark, args.timestamp)
    plotter.transform_data()
    save = not args.no_save
    if save:
        plotter.make_dir()
    else:
        print('Info: no-save option is set')
    plotter.render_or(save, args.output)
    if args.show:
        print('Info: show option is set')
        plotter.show()
