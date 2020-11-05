#!/usr/bin/env bash

clang -c $TARGET_FILE >/dev/null 2>&1 &&\
! sparrow -il -frontend clang $TARGET_FILE >/dev/null 2>&1
