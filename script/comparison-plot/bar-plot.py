#!/usr/bin/env python3

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

matplotlib.rcParams['text.latex.preamble'] = [r'\usepackage{amsmath}']
matplotlib.rcParams['hatch.linewidth'] = 2.0
# for camera ready
plt.rc('text', usetex=True)

drake_prog = ["wget", "readelf", "grep", "sed", "sort", "tar", "optipng", "shntool", "latex2rtf", "urjtag"]
drake = [136, 24, 8, 44, 13, 32, 9, 19, 6, 22]
drake_B = [46, 5, 13, 14, 3, 16, 8, 18, 6, 14]
drake_bingo = [192, 79, 53, 123, 175, 219, 14, 14, 6, 22]

dynaboost_prog = ["bc", "cflow", "grep", "gzip", "patch", "readelf", "sed", "sort", "tar", "optipng", "latex2rtf", "shntool"]
dynaboost = [48, 21, 66, 235, 14, 88, 70, 106, 91, 4, 5, 18]
dynaboost_B = [48, 24, 73, 217, 15, 35, 66, 61, 43, 4, 6, 18]
dynaboost_bingo = [96, 94, 53, 283, 36, 78, 122, 176, 218, 14, 6, 14]

tickfontsize = 25
markersize = 100

epsilons = [str(x) for x in [0.001, 0.005, 0.01, 0.05]] #, 0.1 ]

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
    epsilons = [str(x) for x in [0.001, 0.01]] #, 0.1 ]
    fig, ax = plt.subplots()
    plt.xticks(range(0, 13), fontsize=tickfontsize-5, rotation=45)
    if app == "drake":
        yticks = [0, 20, 40, 60, 80, 100, 120, 140]
    else:
        yticks = [0, 50, 100, 150, 200] 
    plt.yticks(fontsize=tickfontsize)
    if app == "drake":
        programs = drake_prog
        baseline = drake
        bayesmith = drake_B
        label_app = drake_app
    else:
        programs = dynaboost_prog
        baseline = dynaboost
        bayesmith = dynaboost_B
        label_app = dynaboost_app
    programs.append("avg.")
    baseline.append(sum(baseline)/len(baseline))
    bayesmith.append(sum(bayesmith)/len(bayesmith))
    ax.set_xticklabels(programs)
    ax.set_yticklabels([str(x) for x in yticks])
    xidx = 0
    bar_width = 0.27
    j = 0
    total = 0
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
                plt.bar(xidx + calib + (i-1) * (bar_width + 0.02), rank, bar_width, color=color[eps],
                        hatch=hatch[eps], edgecolor=ecolor[eps], zorder=2,
                        label=label_app[eps])
            else:
                plt.bar(xidx + calib + (i-1) * (bar_width + 0.02), rank, bar_width, color=color[eps],
                        hatch=hatch[eps], edgecolor=ecolor[eps], zorder=2)
            i += 1
        j += 1
        xidx += 1
    plt.ylabel("\# Interactions", size=25)
    plt.legend(fontsize=tickfontsize)
    plt.tight_layout()
    plt.savefig("{}-bayesmith.pdf".format(app))


figure_app("drake")
figure_app("dynaboost")
