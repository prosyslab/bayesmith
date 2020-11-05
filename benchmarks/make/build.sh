#!/bin/bash

pushd /tmp

wget http://ftp.gnu.org/gnu/autoconf/autoconf-2.69.tar.gz
wget http://ftp.gnu.org/gnu/automake/automake-1.16.1.tar.gz

tar -xvzf autoconf-2.69.tar.gz
tar -xvzf automake-1.16.1.tar.gz

pushd autoconf-2.69
./configure --prefix=/usr && make -j && make install
popd

pushd automake-1.16.1
./configure --prefix=/usr && make -j && make install
popd

popd

./bootstrap
./configure
$SMAKE/smake --init
$SMAKE/smake -j32
