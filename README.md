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
One may change the name of the directory with option `-out_dir $DIRNAME`.