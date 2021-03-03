# Continuous Reasoning
## Setup
```
./build.sh
```

## Run

### Learn

```sh
$ bingo/learn -reuse -analysis_type [ interval | taint ] -debug $BENCH_NAME
```

e.g. `bingo/learn -reuse -analysis_type interval -debug sort`

Logs (`learn.log`) and output (`.dl` file) will be generated under `learn-out` directory.
One may change the name of the directory with option `-out_dir $DIRNAME`.

### Test

```sh
$ bingo/learn -test -analysis_type [ interval | taint ] -out_dir test-out $BENCH_NAME
```

e.g. `bingo/learn -test -analysis_type interval -out_dir test-out -dl_from $PATH_TO_DL_FILE sort`

Logs (`learn.log`) and output (`.dl` file) will be generated under `test-out` directory.
One may run test with existing datalog rule file with option `-dl_from $PATH_TO_DATALOG_FILE`.
One may run test with custom rule weights with option `-rule_prob_from $PATH_TO_RULE_PROB_TXT_FILE`.
One may change the name of the directory with option `-out_dir $DIRNAME`.

### Report

```sh
$ script/pldi19/report.sh $TIMESTAMP
```

e.g. `script/pldi19/report.sh baseline` will show statistics for baseline performace. Similarly, `script/pldi19/report.sh pldi` will show statistics for pldi21 submitted version performace.
