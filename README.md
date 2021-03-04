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


### Visualize Bayesian Network

```sh
$ bingo/visualizer $BNET_DIR
```

Above command shall prompt a shell starting with `visualizer> `. Then, one may run further commands to get the visuals. Here, we illustrate commonly used commands. For more information, just enter 'help' in the prompted shell as `visualizer> help`.

Then, the following command will output an svg file showing partial BNet that shows common ancestor between two alarms:

```sh
visualizer> common $ALARM_1 $ALARM_2 $OUT_FILE_NAME
```

The following command will output an svg file showing partial BNet that shows derivation of a single alarm. :

```sh
visualizer> single $ALARM $OUT_FILE_NAME
```

By default, it will visualize up to 100 close nodes used for alarm derivation. As one may want to track more nodes, will use the following command:

```sh
visualizer> single $ALARM $SIZE $OUT_FILE_NAME
```
`$SIZE` describes the maximum number of nodes to visualize.
