#!/usr/bin/env python3

import matplotlib

matplotlib.use('Agg')
import matplotlib.pyplot as plt

matplotlib.rcParams['text.latex.preamble'] = [r'\usepackage{amsmath}']
matplotlib.rcParams['hatch.linewidth'] = 2.0
# for camera ready
plt.rc('text', usetex=True)

drake_prog = [{
    "name": "wget",
    "version": "1.12",
    "typ": "interval"
}, {
    "name": "readelf",
    "version": "2.24",
    "typ": "interval"
}, {
    "name": "grep",
    "version": "2.19",
    "typ": "interval"
}, {
    "name": "sed",
    "version": "4.3",
    "typ": "interval"
}, {
    "name": "sort",
    "version": "7.2",
    "typ": "interval"
}, {
    "name": "tar",
    "version": "1.28",
    "typ": "interval"
}, {
    "name": "optipng",
    "version": "0.5.3",
    "typ": "taint"
}, {
    "name": "shntool",
    "version": "3.0.5",
    "typ": "taint"
}, {
    "name": "latex2rtf",
    "version": "2.1.1",
    "typ": "taint"
}, {
    "name": "urjtag",
    "version": "0.8",
    "typ": "taint"
}]
# drake = [136, 24, 8, 44, 13, 32, 9, 19, 6, 22]
# drake_B = [46, 5, 13, 14, 3, 16, 8, 18, 6, 14]
drake = []
drake_B = []
for prog in drake_prog:
    prog_full_name = prog['name'] + '-' + prog['version']
    with open(
            '~/drake/benchmark/{}/sparrow-out/{}/bingo_delta_sem-eps_strong_0.001_stats.txt'
            .format(prog_full_name, prog['typ'])) as f:
        num = len(f.readlines()) - 1
        drake.append(num)
    with open(
            '~/drake/benchmark/{}/sparrow-out/{}/bingo_delta_sem-eps_strong_0.001_bayesmith_stats.txt'
            .format(prog_full_name, prog['typ'])) as f:
        num = len(f.readlines()) - 1
        drake_B.append(num)

dynaboost_prog = [
    "bc", "cflow", "grep", "gzip", "patch", "readelf", "sed", "sort", "tar",
    "optipng", "latex2rtf", "shntool"
]
# dynaboost = [48, 21, 66, 235, 14, 88, 70, 106, 91, 4, 5, 18]
# dynaboost_B = [48, 24, 73, 217, 15, 35, 66, 61, 43, 4, 6, 18]
dynaboost = []
dynaboost_B = []
for prog in dynaboost_prog:
    with open('~/bingo/{}true-stats.txt'.format(prog)) as f:
        num = len(f.readlines()) - 1
        dynaboost.append(num)
    with open('~/bingo/{}bayesmith-stats.txt'.format(prog)) as f:
        num = len(f.readlines()) - 1
        dynaboost_B.append(num)

tickfontsize = 25
markersize = 100

epsilons = [str(x) for x in [0.001, 0.005, 0.01, 0.05]]  #, 0.1 ]

color = {
    '0.001': 'royalblue',
    '0.005': 'white',
    '0.01': 'white',
    '0.05': 'white',
    '0.1': 'white',
    '0.5': 'white'
}

ecolor = {
    '0.001': 'royalblue',
    '0.005': 'salmon',
    '0.01': 'forestgreen',
    '0.05': 'midnightblue',
    '0.1': 'salmon',
    '0.5': 'forestgreen',
}

hatch = {
    '0.001': None,
    '0.005': '.....',
    '0.01': None,
    '0.05': 'xxxxx',
    '0.1': '//////',
    '0.5': '.....',
}

marker = {
    '0.001': '.',
    '0.005': '+',
    '0.01': '*',
    #    '0.05': 'x'
}

drake_app = {
    '0.001': r'$\textsc{Drake}$',
    '0.01': r'$\textsc{BayeSmith}$',
}

dynaboost_app = {
    '0.001': r'$\textsc{DynaBoost}$',
    '0.01': r'$\textsc{BayeSmith}$',
}


def figure_app(app):
    assert (app == 'drake' or app == 'dynaboost')
    epsilons = [str(x) for x in [0.001, 0.01]]  #, 0.1 ]
    fig, ax = plt.subplots()
    plt.xticks(range(0, 13) if app == "dynaboost" else range(0, 11),
               fontsize=tickfontsize - 5,
               rotation=45)
    if app == "drake":
        yticks = [0, 20, 40, 60, 80, 100, 120, 140]
    else:
        yticks = [0, 50, 100, 150, 200]
    plt.yticks(fontsize=tickfontsize)
    if app == "drake":
        programs = [p['name'] for p in drake_prog]
        baseline = drake
        bayesmith = drake_B
        label_app = drake_app
    else:
        programs = dynaboost_prog
        baseline = dynaboost
        bayesmith = dynaboost_B
        label_app = dynaboost_app
    programs.append("avg.")
    baseline.append(sum(baseline) / len(baseline))
    bayesmith.append(sum(bayesmith) / len(bayesmith))
    ax.set_xticklabels(programs)
    ax.set_yticklabels([str(x) for x in yticks])
    xidx = 0
    bar_width = 0.27
    j = 0
    N = len(programs)
    for name in programs:
        i = 0
        for eps in epsilons:
            if i == 0:
                rank = baseline[j]
            else:
                rank = bayesmith[j]
            calib = 0.14
            if xidx == 0:
                plt.bar(xidx + calib + (i - 1) * (bar_width + 0.02),
                        rank,
                        bar_width,
                        color=color[eps],
                        hatch=hatch[eps],
                        edgecolor=ecolor[eps],
                        zorder=2,
                        label=label_app[eps])
            else:
                plt.bar(xidx + calib + (i - 1) * (bar_width + 0.02),
                        rank,
                        bar_width,
                        color=color[eps],
                        hatch=hatch[eps],
                        edgecolor=ecolor[eps],
                        zorder=2)
            i += 1
        j += 1
        xidx += 1
    plt.ylabel("\# Interactions", size=25)
    plt.legend(fontsize=tickfontsize)
    plt.tight_layout()
    plt.savefig("{}-bayesmith.pdf".format(app))


figure_app("drake")
figure_app("dynaboost")
