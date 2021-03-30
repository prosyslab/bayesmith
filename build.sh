#!/bin/bash

set -e

echo "Build Souffle"
if [[ ! -d "souffle" ]]; then
  echo "souffle not found"
  exit 1
fi
pushd souffle
./bootstrap
./configure
make -j
popd

echo "Build libdai"
if [[ ! -d "libdai" ]]; then
  echo "libdai not found"
  exit 1
fi
pushd libdai
cp Makefile.LINUX Makefile.conf
make -j
popd

echo "Build Bingo"
pushd bingo/prune-cons
make
popd
opam install -y batteries linenoise yojson ocamlgraph
pushd bingo
make
popd
