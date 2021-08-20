# rank-history-plot

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
