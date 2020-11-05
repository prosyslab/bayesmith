# rank-history-plot

Due to maintenance issue, here is the new way of plotting rank of `TrueGround` alarms for each [benchmark](benchmarks.txt). The necessity of this work rises as [continuous-reasoning](https://github.com/prosyslab/continuous-reasoning) project makes progress. Using virtual environment is recommended for clean package management. This project follows [PEP 8](https://www.python.org/dev/peps/pep-0008/). [autopep8](https://pypi.org/project/autopep8/) is a reference formatter.

## Virtual environment setup (optional)

```sh
$ pip3 install virtualenv
$ virtualenv -p /usr/bin/python3 env
$ source env/bin/activate
```

`env` is the name of your virtual environment. One may use custom name for the environment.

## Install

```sh
$ pip3 install -r requirements.txt

# To show plot in local console (optional)
$ sudo apt-get install python3-tk       # Ubuntu 18.04 or higher

$ brew install tcl-tk                   # MacOS 10.15.3 or higher
$ brew reinstall python
```

If having trouble with installing `tkinter` module in Mac OS, view [this issue](https://github.com/hyunsukimsokcho/rank-history-plot/issues/1).

## Configure

```sh
$ ./configure.sh <PATH_TO_BENCHMARKS> 
```
e.g. `./configure.sh ../../benchmarks`

After successful configuration, one can see `facts.txt` being generated.

## Run

```sh
# Save as file (default)
$ python3 plot.py <BENCHMARK_NAME> <TIMESTAMP>

# Show in local console
$ python3 plot.py --show <BENCHMARK_NAME> <TIMESTAMP>

# For more options
$ python3 plot.py --help
```

e.g. `python3 plot.py urjtag 20200710-11:49:25`

One doesn't need to specify target path for each benchmark.
