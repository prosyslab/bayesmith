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

Logs (`learn.log`) and output (`.dl` file) will be generated under `learn-out` directory.
One may change the name of the directory with option `-out_dir $DIRNAME`.

### Test

```sh
$ bingo/learn -test -analysis_type [ interval | taint ] -out_dir test-out $BENCH_NAME
```

Logs (`learn.log`) and output (`.dl` file) will be generated under `test-out` directory.
One may run test with existing datalog rule file with option `-dl_from $PATH_TO_DATALOG_FILE`.
One may run test with custom rule weights with option `-rule_prob_from $PATH_TO_RULE_PROB_TXT_FILE`.
One may change the name of the directory with option `-out_dir $DIRNAME`.