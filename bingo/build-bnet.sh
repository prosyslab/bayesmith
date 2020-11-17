#!/usr/bin/env bash

########################################################################################################################
# TODO: All comments in this file are possibly obsolete! Please exercise caution!
########################################################################################################################

# NOTE! This is the compressed BNet builder! The output is unsuitable for applications such as EM, and is still
# experimental!

# Intended to be run from the chord-fork folder.
# Given a project name and a project path, runs the commands that must be run before driver.py can be invoked. This
# includes pruning the constraints in named_cons_all.txt, turning named_cons_all.txt.pruned into a bayesian network, and
# finally turning named-bnet.out into factor-graph.fg which is readable by driver.py.

# Arguments:
# 1. Project name, in a format recognized by list.sh, and eventually by runner.pl.
# 2. Project path, in a format recognized by list.sh, and eventually by runner.pl.
# 3. Augment dir: "augment" or "noaugment", suffixed with any string, in which the BN will be built.
#                 This will also indicate to prune-cons whether or not to augment the forward constraints while pruning.
#                 The second part of the name is merely a convention: it indicates the list of queries used as
#                 base_queries.txt while performing prune-cons.
#                 Ex: noaugment_or_thr means that prune-cons will not augment (because of the noaugment prefix)
#                     and the BN will be placed in the directory noaugment_or_thr. The or_thr suffix indicates, again by
#                     convention, that the k-obj=3-sensitive oracle with thread escape was used as the set of queries to
#                     to be ranked.
# 4. rule-prob.txt, file mapping rule names to probabilities.
# 5. bnet dir: The chord_output folder that contains the named_cons_all.txt and in which the bnet should be built.
# 6. Name of the file containing the output tuples (ex. .../base_queries.txt) relative to the second argument above, i.e. project path.
# 7. Optionally, "dolist", indicating whether to run list.sh. If supplied, list.sh is run to create the chord_output_*
#    directories. Otherwise, the chord_output directories from some previous run are used instead.
# 8. Optionally, "noprune", indicating whether to skip pruning named_cons_all.txt, and instead use a pre-existing
#    named_cons_all.txt.pruned file from a previous invocation of prune-cons.
# 9. Optionally, "oldbnet", indicating whether to use a pre-existing named-bnet.out from a previous invocation of
#    cons_all2bnet.py.

# cd ./Error-Ranking/chord-fork
# ./bingo/bnet/compressed/build-bnet.sh ftp pjbench/ftp \
#                                         noaugment_base rule-prob.txt \
#                                         chord_output_mln-datarace-problem \
#                                         chord_output_mln-datarace-problem/base_queries.txt \
#                                         [dolist] [noprune] [oldbnet]

set -e
export PROGRAM_PATH=$(readlink -f $1)
export OP_TUPLE_FILENAME=$2
export BNET=$3
export EPS=$4
export PYTHONHASHSEED=0 # to make python set deterministic
IS_EM=$5
RULE_PROB_FILE=$6
EM_TEST="em-test"

if [ "$IS_EM" = "$EM_TEST" ]; then
  $BINGO_DIR/bnet2fg.py $RULE_PROB_FILE 0.99 \
    <$PROGRAM_PATH/bnet-baseline/named-bnet.out \
    >$PROGRAM_PATH/${BNET}/factor-graph.fg \
    2>$PROGRAM_PATH/${BNET}/bnet2fg.log
else
  mkdir -p $PROGRAM_PATH/$BNET

  export AUGMENT="noaugment"

  BINGO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  $BINGO_DIR/prune-cons/prune-cons $AUGMENT $OP_TUPLE_FILENAME \
    <$PROGRAM_PATH/${BNET}/named_cons_all.txt \
    >$PROGRAM_PATH/${BNET}/named_cons_all.txt.pruned \
    2>$PROGRAM_PATH/${BNET}/prune-cons.log

  $BINGO_DIR/derive-edb.py \
    <$PROGRAM_PATH/${BNET}/named_cons_all.txt.pruned \
    >$PROGRAM_PATH/${BNET}/named_cons_all.txt.edbderived \
    2>$PROGRAM_PATH/${BNET}/derive-edb.log

  $BINGO_DIR/elide-edb.py \
    <$PROGRAM_PATH/${BNET}/named_cons_all.txt.edbderived \
    >$PROGRAM_PATH/${BNET}/named_cons_all.txt.ep \
    2>$PROGRAM_PATH/${BNET}/elide-edb.log

  $BINGO_DIR/compress-cons-all.py \
    $PROGRAM_PATH/${BNET}/named_cons_all.txt.ep \
    $PROGRAM_PATH/$BNET/rule-prob.txt \
    0.99 \
    $OP_TUPLE_FILENAME \
    $PROGRAM_PATH/${BNET}/new-rule-prob.txt \
    $PROGRAM_PATH/${BNET}/named_cons_all.txt.cep \
    2>$PROGRAM_PATH/${BNET}/compress-cons-all.log

  $BINGO_DIR/cons_all2bnet.py $PROGRAM_PATH/${BNET}/bnet-dict.out narrowand narrowor \
    <$PROGRAM_PATH/${BNET}/named_cons_all.txt.cep \
    >$PROGRAM_PATH/${BNET}/named-bnet.out \
    2>$PROGRAM_PATH/${BNET}/cons_all2bnet.log

  $BINGO_DIR/bnet2fg.py $PROGRAM_PATH/${BNET}/new-rule-prob.txt 0.99 \
    <$PROGRAM_PATH/${BNET}/named-bnet.out \
    >$PROGRAM_PATH/${BNET}/factor-graph.fg \
    2>$PROGRAM_PATH/${BNET}/bnet2fg.log
fi