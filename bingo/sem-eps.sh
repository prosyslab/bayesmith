#!/usr/bin/env bash

# Runs Delta-Bingo in the sem-eps mode.
# Usage: ./delta/sem-eps.sh OLD_PROGRAM_DIR NEW_PROGRAM_DIR [interval | taint] [strong | inter | weak] [reuse]

# The main operational difference is in invoking mb-eps.py instead of mb.py.

########################################################################################################################
# 0. Prelude

set -e

if [[ $# -lt 4 || $# -gt 8 ]]; then
  echo "Invalid Argument" 1>&2
  exit 1
fi

OLD_PGM=$1
NEW_PGM=$2
ANALYSIS=$3
OLD_BNET=$4
NEW_BNET=$5
FB_MODE=$6
EPS=$7
REUSE=$8
OLD_OUTPUT_DIR=$OLD_PGM/sparrow-out
NEW_OUTPUT_DIR=$NEW_PGM/sparrow-out

echo "Running Delta Bingo (sem)" 1>&2
MERGED="merged_bnet_$EPS"
mkdir -p $NEW_OUTPUT_DIR/$ANALYSIS/$MERGED

########################################################################################################################
# 1. Translating Constraints

echo "Step 1: Translating constraints" 1>&2
START_TIME=$SECONDS

####
# 1a. Invoke translate-cons.py

# translate-cons.py takes as input:
# 1. the old- and new named_cons_all.txt files ($OLD_PGM/.../bnet/named_cons_all.txt and
#    $NEW_PGM/.../bnet/named_cons_all.txt respectively),
# 2. the old- and new sets of alarms ($OLD_PGM/.../bnet/Alarm.txt and $NEW_PGM/.../bnet/Alarm.txt respectively),
# 3. the old- and new node.json files ($OLD_PGM/.../node.json and $NEW_PGM/.../node.json respectively),
# 4. the line matching file produced by Sparrow ($NEW_PGM/line_matching.json), and
# 5. the name of the output directory ($NEW_PGM/sparrow-out/bnet).

# In the output directory, it places:
# 1. $NEW_PGM/sparrow-out/bnet/trans_named_cons_all.txt.
#    TODO: Confirm the contents of trans_named_cons_all.txt with Kihong, specifically the ???.
#    Every tuple R(a_1, a_2, ..., a_k) is transformed into R(b_1, b_2, ..., b_k), where
#        b_i = h(a_i) if h(a_i) occurs in $NEW_PGM/.../bnet/named_cons_all.txt, and
#              ???-OLD, otherwise.
# 2. $NEW_PGM/sparrow-out/bnet/translation.map.
# 3. $NEW_PGM/sparrow-out/bnet/OldAlarm.txt. This file contains the list of old alarms transformed by the h-function.

####
# 1b. Compute the set of new alarms

# DEFINITION: The new alarms are those which were not observed in the old program.
# NOTE: This definition is useless in the sem.sh script, since the major premise of Delta-Bingo is that even alarms
#       which are not syntactically new may represent real bugs.
# We store the new alarms in $NEW_OUTPUT_DIR/bnet/NewAlarm.txt.

comm -13 <(sort $NEW_OUTPUT_DIR/$ANALYSIS/$NEW_BNET/OldAlarm.txt) \
  <(sort $NEW_OUTPUT_DIR/$ANALYSIS/$NEW_BNET/Alarm.txt) \
  >$NEW_OUTPUT_DIR/$ANALYSIS/$NEW_BNET/NewAlarm.txt

echo "$(wc -l $NEW_OUTPUT_DIR/$ANALYSIS/$NEW_BNET/NewAlarm.txt | cut -f 1 -d ' ') syntactically new alarms detected" 1>&2

####
# 1c. Add FX tuples to named_cons_all.txt

# $NEW_OUTPUT_DIR/.../trans_named_cons_all.txt and $NEW_OUTPUT_DIR/.../named_cons_all.txt may contain clauses of the
# form DUPath(p1, p2) => Alarm(p1, p2). These clauses represent unencoded reasoning performed by Sparrow, where only
# certain dataflows may result in potentially undesirable program behavior. Outputting these clauses was important for
# the accuracy of Bingo, but was unfortunately incompletely planned. A far more useful version of the clause is
# DUPath(p1, p2), FX(p1, p2) => Alarm(p1, p2), where the EDB tuples FX(p1, p2) (standing for 'Unencoded Sparrow Factor
# X') determines whether a dataflow represents an alarm. Principally, adding the FX tuples restores the common clause
# hypothesis which is checked by mb-eps.py. The following scripts accomplish this.

./bingo/add-fx.py <$NEW_OUTPUT_DIR/$ANALYSIS/$NEW_BNET/trans_named_cons_all.txt >$NEW_OUTPUT_DIR/$ANALYSIS/$NEW_BNET/trans_named_cons_all.txt.fx
./bingo/add-fx.py <$NEW_OUTPUT_DIR/$ANALYSIS/$NEW_BNET/named_cons_all.txt >$NEW_OUTPUT_DIR/$ANALYSIS/$NEW_BNET/named_cons_all.txt.fx

ELAPSED_TIME=$(($SECONDS - $START_TIME))
echo "Finished translating constraints ($ELAPSED_TIME sec)" 1>&2

########################################################################################################################
# 2. Merging Constraints

echo "Step 2: Merging constraints" 1>&2
START_TIME=$SECONDS

# mb-eps.py takes as input:
# 1. the old- and new named_cons_all.txt files ($NEW_OUTPUT_DIR/bnet/trans_named_cons_all.txt.fx and
#    $NEW_OUTPUT_DIR/bnet/named_cons_all.txt.fx respectively), and
# 2. the list of old- and new alarms ($NEW_OUTPUT_DIR/.../OldAlarm.txt and $NEW_OUTPUT_DIR/.../Alarm.txt respectively).

# It produces as output:
# 1. The constraints of the merged Bayesian network, in $NEW_OUTPUT_DIR/merged_bnet/named_cons_all.txt.ukd.
# 2. All EDB tuples of these merged constraints, in the file $NEW_OUTPUT_DIR/merged_bnet/AllEDB.txt.
#    This is the set of tuples:
#        { RNEW(a1, a2, ..., ak) | EDB tuple R(a1, a2, ..., ak) in $NEW_OUTPUT_DIR/bnet/named_cons_all.txt.fx } union
#        { ROLD(a1, a2, ..., ak) | EDB tuple R(a1, a2, ..., ak) in $NEW_OUTPUT_DIR/bnet/named_cons_all.txt.fx such that
#                                            R(a1, a2, ..., ak) in $NEW_OUTPUT_DIR/bnet/trans_named_cons_all.txt.fx }.
# 3. Old alarm tuples which need to be silencecd, in the file $NEW_OUTPUT_DIR/merged_bnet/fb0Alarm.txt.
#    This is the set of tuples:
#        { AlarmOLD(a1, a2) | Alarm(a1, a2) in $NEW_OUTPUT_DIR/bnet/named_cons_all.txt.fx and
#                             Alarm(a1, a2) in $NEW_OUTPUT_DIR/bnet/trans_named_cons_all.txt.fx }.
# 4. All alarm tuples (both AlarmOLD and AlarmNEW) which appear in .../named_cons_all.txt.ukd, in the file
#    $NEW_OUTPUT_DIR/merged_bnet/SemAllAlarm.txt.ukd.

if [[ "$REUSE" = "reuse" ]]; then
  echo "Reusing old merged network" 1>&2
else
  bingo/mb-eps.py $NEW_OUTPUT_DIR/$ANALYSIS/$NEW_BNET/trans_named_cons_all.txt.fx \
    $NEW_OUTPUT_DIR/$ANALYSIS/$NEW_BNET/OldAlarm.txt \
    $NEW_OUTPUT_DIR/$ANALYSIS/$NEW_BNET/named_cons_all.txt.fx \
    $NEW_OUTPUT_DIR/$ANALYSIS/$NEW_BNET/Alarm.txt \
    $NEW_OUTPUT_DIR/$ANALYSIS/$MERGED/named_cons_all.txt.ukd \
    $NEW_OUTPUT_DIR/$ANALYSIS/$MERGED/AllEDB.txt \
    $NEW_OUTPUT_DIR/$ANALYSIS/$MERGED/fb0Alarm.txt \
    $NEW_OUTPUT_DIR/$ANALYSIS/$MERGED/SemAllAlarm.txt.ukd \
    2> >(tee $NEW_OUTPUT_DIR/$ANALYSIS/$MERGED/mb.log >&2)
fi

# The .ukd suffix for the file output by mb-eps.py is a historical relic of sem.sh and mb.py. In the current setting,
# all new EDB tuples are derivable and therefore, keep-derivable.cpp should be a noop. We will confirm this after
# calling keep-derivable.

# The .ukd suffix for the file output by mb-eps.py indicates the presence of tuples which are not derivable using the
# constraints and starting from .../AllEDB.txt. Similarly, not all alarms in SemAllAlarm.txt.ukd need be derivable
# either. Both these situations violate assumptions made by prune-cons.cpp. Therefore, we now use the keep-derivable.cpp
# script to eliminate these underivable tuples.

# Each alarm Alarm(a1, a2) of the new program splits into two components:
# 1. AlarmOLD(a1, a2), which is produced by derivation trees also present in the old program, and
# 2. AlarmNEW(a1, a2), which is produced by derivation trees only present in the new program.
# By assumption, the bugs we seek are only present in the new program.

sed 's/(/NEW(/' $NEW_OUTPUT_DIR/$ANALYSIS/$NEW_BNET/Alarm.txt >$NEW_OUTPUT_DIR/$ANALYSIS/$MERGED/SemAlarm.txt
sed 's/(/NEW(/' $NEW_OUTPUT_DIR/$ANALYSIS/$NEW_BNET/GroundTruth.txt >$NEW_OUTPUT_DIR/$ANALYSIS/$MERGED/SemGroundTruth.txt

# keep-derivable.cpp takes as input:
# 1. the set of EDB tuples from which to compute fixpoint (.../AllEDB.txt),
# 2. the set of alarms in the new program requiring new derivation trees (.../SemAlarm.txt), and
# 3. the set of alarms in .../merged_bnet/named_cons_all.txt.ukd (.../SemAllAlarm.txt.ukd).

# It produces as output:
# 1. the set of clauses actually present in the fixpoint (on stdout), and
# 2. all derivable alarms of the combined constraints (../merged_bnet/SemAllAlarm.txt).
# This script produces large amounts of logging data on stderr which we redirect to an appropriate log file.

./bingo/prune-cons/keep-derivable $NEW_OUTPUT_DIR/$ANALYSIS/$MERGED/AllEDB.txt \
  $NEW_OUTPUT_DIR/$ANALYSIS/$MERGED/SemAlarm.txt \
  $NEW_OUTPUT_DIR/$ANALYSIS/$MERGED/SemAllAlarm.txt.ukd \
  $NEW_OUTPUT_DIR/$ANALYSIS/$MERGED/SemAllAlarm.txt \
  <$NEW_OUTPUT_DIR/$ANALYSIS/$MERGED/named_cons_all.txt.ukd \
  >$NEW_OUTPUT_DIR/$ANALYSIS/$MERGED/named_cons_all.txt \
  2>$NEW_OUTPUT_DIR/$ANALYSIS/$MERGED/keep-derivable.log

# Sanity check
if [[ $(comm -13 <(sort $NEW_OUTPUT_DIR/$ANALYSIS/$MERGED/SemAllAlarm.txt.ukd) \
  <(sort $NEW_OUTPUT_DIR/$ANALYSIS/$MERGED/SemAllAlarm.txt)) ]]; then
  echo "SemAllAlarm.txt is not a subset of SemAllAlarm.txt.ukd!" 1>&2
  exit 1
elif [[ $(comm -23 <(sort $NEW_OUTPUT_DIR/$ANALYSIS/$MERGED/SemAllAlarm.txt.ukd) \
  <(sort $NEW_OUTPUT_DIR/$ANALYSIS/$MERGED/SemAllAlarm.txt) | grep -v 'OLD(') ]]; then
  echo "SemAllAlarm.txt.ukd contains the following tuples not in SemAllAlarm.txt!" 1>&2
  comm -23 <(sort $NEW_OUTPUT_DIR/$ANALYSIS/$MERGED/SemAllAlarm.txt.ukd) \
    <(sort $NEW_OUTPUT_DIR/$ANALYSIS/$MERGED/SemAllAlarm.txt) |
    grep -v 'OLD(' 1>&2
  exit 1
else
  echo "SemAllAlarm.txt contains the same new tuples as SemAllAlarm.txt.ukd. Good-good!" 1>&2
fi

# Store a dictionary between each AlarmNEW and its corresponding AlarmOLD
cat $NEW_OUTPUT_DIR/$ANALYSIS/$MERGED/SemAllAlarm.txt | grep OLD | sed 's/\(.*\)/\1: \1/' | sed 's/OLD(/NEW(/' \
  >$NEW_OUTPUT_DIR/$ANALYSIS/$MERGED/AlarmNODict.txt

ELAPSED_TIME=$(($SECONDS - $START_TIME))
echo "Finished merging constraints ($ELAPSED_TIME sec)" 1>&2

########################################################################################################################
# 3. Building Bayesian Network

echo "Step 3: Building Bayesian Network" 1>&2
START_TIME=$SECONDS

if [[ "$REUSE" = "reuse" ]]; then
  echo "Reusing old Bayesian network" 1>&2
else
  # TODO: temporal workaround
  touch $NEW_OUTPUT_DIR/$ANALYSIS/$MERGED/rule-prob.txt
  bingo/build-bnet.sh $NEW_OUTPUT_DIR/$ANALYSIS $NEW_OUTPUT_DIR/$ANALYSIS/$MERGED/SemAllAlarm.txt $MERGED $EPS
fi

# No EDB tuples are silenced in sem-eps mode. Therefore, fb0Strong.txt is simply fb0Alarm.txt,
# i.e., we initially silence all alarms in fb0Alarm.txt,
cat $NEW_OUTPUT_DIR/$ANALYSIS/$MERGED/fb0Alarm.txt |
  sort | uniq >$NEW_OUTPUT_DIR/$ANALYSIS/$MERGED/fb0Strong.txt
# and fb0InterWeak.txt is empty:
>$NEW_OUTPUT_DIR/$ANALYSIS/$MERGED/fb0InterWeak.txt

if [[ "$FB_MODE" == "strong" ]]; then
  export FBFILE=$NEW_OUTPUT_DIR/$ANALYSIS/$MERGED/fb0Strong.txt
elif [[ "$FB_MODE" == "inter" ]]; then
  export FBFILE=$NEW_OUTPUT_DIR/$ANALYSIS/$MERGED/fb0InterWeak.txt
else
  export FBFILE=$NEW_OUTPUT_DIR/$ANALYSIS/$MERGED/fb0InterWeak.txt
fi

comm -12 <(./bingo/all-tuples.sh <$NEW_OUTPUT_DIR/$ANALYSIS/$MERGED/named_cons_all.txt.pruned) $FBFILE >$FBFILE.pruned

ELAPSED_TIME=$(($SECONDS - $START_TIME))
echo "Finished building Bayeisan network ($ELAPSED_TIME sec)" 1>&2

########################################################################################################################
# 4. Running accmd

echo "Step 4: Executing Interaction" 1>&2
START_TIME=$SECONDS

comm -12 <(sort $NEW_OUTPUT_DIR/$ANALYSIS/$MERGED/SemAlarm.txt) \
  <(sort $NEW_OUTPUT_DIR/$ANALYSIS/$MERGED/SemAllAlarm.txt) \
  >$NEW_OUTPUT_DIR/$ANALYSIS/$MERGED/RankingAlarms.txt

if [[ "$FB_MODE" == "strong" ]]; then
  export DFILE=/dev/null
elif [[ "$FB_MODE" == "inter" ]]; then
  export DFILE=$NEW_OUTPUT_DIR/$ANALYSIS/$MERGED/AlarmNODict.txt
else
  export DFILE=/dev/null
fi

set -x
bingo/accmd $NEW_OUTPUT_DIR/$ANALYSIS \
  $NEW_OUTPUT_DIR/$ANALYSIS/$MERGED/RankingAlarms.txt \
  $NEW_OUTPUT_DIR/$ANALYSIS/$MERGED/SemGroundTruth.txt \
  $DFILE \
  500 \
  $FBFILE.pruned \
  $MERGED \
  "merged" \
  libdai/bingo

ELAPSED_TIME=$(($SECONDS - $START_TIME))
echo "Interaction completes ($ELAPSED_TIME sec)" 1>&2

########################################################################################################################
# A. Shunt

# bingo/print_bnet.py $NEW_OUTPUT_DIR/merged_bnet/named_cons_all.txt.cep \
#   $NEW_OUTPUT_DIR/merged_bnet/SemAlarm.txt $NEW_OUTPUT_DIR/merged_bnet/SemGroundTruth.txt \
#   $NEW_OUTPUT_DIR/merged_bnet/graph.svg $NEW_OUTPUT_DIR/merged_bnet/fb0.txt
