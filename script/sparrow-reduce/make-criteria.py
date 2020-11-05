#!/usr/bin/env python3

import argparse
import os
import stat

BASE_DIR = os.path.dirname(__file__)
CWD = os.getcwd()
SCRIPT = 'criteria.sh'
TEMPLATE = 'template.sh'
TEMP_PATH = os.path.join(BASE_DIR, TEMPLATE)


def get_abspath(target):
    abs_path = os.path.abspath(os.path.join(CWD, target))
    return (abs_path)


def get_dirname(path):
    return os.path.dirname(path)


def get_basename(path):
    return os.path.basename(path)


def split_target(target):
    target = get_abspath(target)
    d = get_dirname(target)
    b = get_basename(target)
    return d, b


def get_script(filename):
    arg_dict = {'$TARGET_FILE': filename}
    with open(TEMP_PATH, 'r') as f:
        s = f.read()
        for _from, _to in arg_dict.items():
            s = s.replace(_from, _to)
    return s


def write_criteria(target):
    target_dir, target_file = split_target(target)
    script_path = os.path.join(target_dir, SCRIPT)
    with open(script_path, 'w') as f:
        script = get_script(target_file)
        f.write(script)
    st = os.stat(script_path)
    os.chmod(script_path, st.st_mode | stat.S_IEXEC)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Make criteria script to run Creduce")
    parser.add_argument('target', metavar="TARGET", help="path to target file")
    args = parser.parse_args()

    write_criteria(args.target)
