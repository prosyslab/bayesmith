#!/usr/bin/env bash

SCRIPT_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FINAL_TIMESTAMP=final

python3 $SCRIPT_HOME/bnet.py all baseline $FINAL_TIMESTAMP --table fg
