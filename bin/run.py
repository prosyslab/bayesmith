#!/usr/bin/env python3

import argparse
import glob
import shutil
import json
import os
import subprocess

from datetime import datetime
from github import Github

PROJECT_HOME = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
BENCHMARK_DIR = os.path.join(PROJECT_HOME, 'benchmarks')
BENCHMARK_LIST = os.path.join(BENCHMARK_DIR, 'list.json')
DOCKER_PREFIX = "prosyslab/continuous-reasoning"
SPARROW_CONFIG = "sparrow-config.json"
SPARROW_HOME = os.path.join(PROJECT_HOME, "sparrow")
SPARROW_BIN = os.path.join(SPARROW_HOME, 'bin', 'sparrow')
SOUFFLE_HOME = os.path.join(PROJECT_HOME, "souffle")
SOUFFLE_BIN = os.path.join(SOUFFLE_HOME, 'src', 'souffle')
DATALOG_DIR = os.path.join(PROJECT_HOME, 'datalog')
BINGO_DIR = os.path.join(PROJECT_HOME, 'bingo')
LIBDAI_HOME = os.path.join(PROJECT_HOME, "libdai")
TRAIN_MODE = "TRAIN"
TEST_MODE = "TEST"


def initialize():
    if not os.path.isdir(BENCHMARK_DIR):
        os.mkdir(BENCHMARK_DIR)

    with open(BENCHMARK_LIST) as f:
        benchmark_list = json.load(f)

    return benchmark_list


def get_repo_name(url):
    repo_name = url.split('github.com/')[1]
    if repo_name.endswith('.git'):
        repo_name = repo_name[:-4]
    return repo_name


def fetch(args, benchmark_list):
    github = Github()

    # https://stackoverflow.com/a/43136160
    for benchmark in benchmark_list:
        repo_name = get_repo_name(benchmark['repository'])
        print("Fetching " + benchmark['name'] + " from github.com/" +
              repo_name)
        repo = github.get_repo(repo_name)
        commits = repo.get_commits(since=args.since, until=args.until)

        PROGRAM = benchmark['name']
        program_dir = os.path.join(BENCHMARK_DIR, PROGRAM)
        if not os.path.isdir(program_dir):
            os.mkdir(program_dir)

        os.chdir(program_dir)
        for commit in commits:
            commit_dir = os.path.join(program_dir, commit.sha)
            if not os.path.exists(commit_dir):
                os.mkdir(commit_dir)
            if os.path.exists(os.path.join(commit_dir, "sparrow")):
                print("Skip", os.path.join(PROGRAM, commit.sha))
                continue
            image_id = DOCKER_PREFIX + "-" + benchmark[
                'name'] + ":" + commit.sha
            subprocess.run([
                "docker", "build", "-t", image_id, "--build-arg",
                "SHA=" + commit.sha, "."
            ])
            container_id = subprocess.check_output(
                ["docker", "run", "-dit", image_id])
            container_id = container_id.decode("utf-8").rstrip()
            subprocess.run([
                "docker", "cp",
                container_id + ":" + os.path.join("/src", PROGRAM + "/."),
                commit_dir
            ])
            subprocess.run(["docker", "stop", container_id])
            subprocess.run(["docker", "rm", container_id])


default_sparrow_options = ["-unsound_alloc", "-extract_datalog_fact_full"]

sparrow_options = {
    # pldi19 benchmark
    "shntool": ["-taint"],
    "latex2rtf": [
        "-taint", "-unsound_const_string", "-unsound_skip_function",
        "diagnostics"
    ],
    "urjtag": [
        "-taint", "-unsound_const_string", "-unsound_skip_file", "flex",
        "-unsound_skip_file", "bison"
    ],
    "optipng": ["-taint"],
    "kilo": ["-taint"],
    "wget": [
        "-inline", "alloc", "-filter_file", "hash.c", "-filter_file",
        "html-parse.c", "-filter_file", "utils.c", "-filter_file", "url.c",
        "-filter_allocsite", " _G_", "-filter_allocsite", "extern",
        "-filter_allocsite", "uri_", "-filter_allocsite", "url_",
        "-filter_allocsite", "fd_read_hunk", "-filter_allocsite", "main",
        "-filter_allocsite", "gethttp", "-filter_allocsite", "strdupdelim",
        "-filter_allocsite", "checking_strdup", "-filter_allocsite", "xmemdup",
        "-filter_allocsite", "getftp", "-filter_allocsite", "cookie_header",
        "-filter_allocsite", "dot_create", "-filter_allocsite", "yy",
        "-filter_function", "yy_scan_bytes"
    ],
    "readelf": [
        "-inline", "alloc", "-filter_allocsite", "extern", "-filter_allocsite",
        "_G_", "-filter_allocsite", "simple", "-filter_allocsite", "get_"
    ],
    "grep": ["-inline", "alloc"],
    "sed": [
        "-inline", "alloc", "-filter_allocsite", "match_regex", "-filter_file",
        "obstack.c", "-filter_node", "match_regex-64558", "-filter_node",
        "do_subst-*", "-filter_allocsite", "extern", "-filter_allocsite",
        "_G_", "-filter_allocsite", "quote", "-filter_function",
        "str_append_modified", "-filter_function", "compile_regex_1"
    ],
    "sort": [
        "-inline", "alloc", "-unsound_skip_file", "getdate.y",
        "-filter_allocsite", "yyparse", "-filter_allocsite", "extern",
        "-filter_allocsite", "main", "-filter_allocsite", "_G_",
        "-filter_file", "quotearg.c", "-filter_file", "printf-args.c",
        "-filter_file", "printf-parse.c"
    ],
    "tar": [
        "-inline", "alloc", "-filter_extern", "-unsound_skip_file",
        "parse-datetime", "-filter_allocsite", "_G_-", "-filter_allocsite",
        "parse", "-filter_allocsite", "delete_archive_members",
        "-filter_allocsite", "hash", "-filter_allocsite", "main",
        "-filter_allocsite", "quote", "-filter_allocsite", "hol",
        "-filter_allocsite", "header", "-filter_allocsite", "xmemdup",
        "-filter_allocsite", "xmalloc", "-filter_allocsite", "dump"
    ],
    "cflow": [
        "-inline",
        "alloc",
        "-unsound_alloc",
        "-filter_function",
        "yy",
        "-filter_file",
        "c\.l",
    ],
    "screen": [
        "-inline", "alloc", "-unsound_alloc", "-unsound_recursion",
        "-unsound_noreturn_function", "-filter_extern"
    ],
    "libtasn1": ["-inline", "alloc", "-unsound_alloc"],
    "bc": ["-inline", "alloc", "-unsound_alloc"],
    "patch": ["-inline", "alloc", "-unsound_alloc"],
    "fribidi": [
        "-inline", "alloc", "-unsound_alloc", "-unsound_recursion",
        "-unsound_noreturn_function"
    ],
    "gzip": [
        "-inline", "alloc", "-unsound_alloc", "-unsound_recursion",
        "-unsound_noreturn_function"
    ],
    "a2ps": ["-taint", "-inline", "alloc", "-unsound_alloc"],
    "rrdtool": ["-taint", "-inline", "alloc", "-unsound_alloc"],
    "dicod": ["-taint", "-inline", "alloc", "-unsound_alloc"],
    "autotrace": ["-taint"],
    "sam2p": ["-taint"],
    "gimp": ["-taint"],
    "less": ["-taint"],
    "jhead": ["-taint"],
    "libming": ["-taint"],
    "putty": ["-taint"],
    "sdop": ["-taint"],
    "man": ["-inline", "alloc"],
    "bzip2": ["-inline", "alloc"]
}


def run_sparrow(args, program, version):
    benchmark_dir = os.path.join(BENCHMARK_DIR, program)
    with open(os.path.join(benchmark_dir, SPARROW_CONFIG)) as f:
        sparrow_config = json.load(f)
    if not os.path.exists(benchmark_dir):
        print("Directory {} not found".format(benchmark_dir))
        exit(1)
    sha_dir = os.path.join(benchmark_dir, version)
    target_dir = os.path.join(sha_dir, 'sparrow', sparrow_config['target'])
    source_files = glob.glob(target_dir + '/*.[ci]')
    output_dir = os.path.join(sha_dir, "sparrow-out")
    options = default_sparrow_options + sparrow_options[program] + [
        "-outdir", output_dir
    ]
    if args.reuse:
        options = options + ["-marshal_in"]
        print("(reuse old analysis results)")
    else:
        options = options + ["-marshal_out"]

    subprocess.run([SPARROW_BIN] + options + source_files)


def analyze(args, benchmark_list):
    if args.target == "all":
        for benchmark in benchmark_list:
            program = benchmark['name']
            benchmark_dir = os.path.join(BENCHMARK_DIR, program)
            os.chdir(benchmark_dir)
            for sha in [
                    os.path.join(benchmark_dir, sub) for sub in os.listdir('.')
                    if os.path.isdir(os.path.join(benchmark_dir, sub))
            ]:
                sha_dir = os.path.join(benchmark_dir, sha)
                if os.path.exists(os.path.join(sha_dir, "sparrow-out")):
                    print("Skip", os.path.join(program, os.path.basename(sha)))
                    continue
                os.chdir(sha_dir)
                run_sparrow(benchmark_dir, sha)
    else:
        path = os.path.abspath(args.target)
        program = os.path.basename(os.path.dirname(path))
        version = os.path.basename(path)
        run_sparrow(args, program, version)


def build_bnet(program, version, analysis_type, bnet_dir, skip_compress, mode,
               em_rule):
    print("Building Bayesian Network to {}".format(bnet_dir))
    benchmark_dir = os.path.join(BENCHMARK_DIR, program)
    output_dir = os.path.join(benchmark_dir, version, "sparrow-out")
    command = [
        os.path.join(BINGO_DIR, "generate-alarm.sh"), output_dir,
        analysis_type, bnet_dir, "Alarm.csv"
    ]
    subprocess.run(command, check=True)
    analysis_dir = os.path.join(output_dir, analysis_type)
    skip_compress = "YES" if skip_compress else "NO"
    command = [
        os.path.join(BINGO_DIR, "build-bnet.sh"), analysis_dir,
        os.path.join(analysis_dir, bnet_dir, "Alarm.txt"), bnet_dir, skip_compress
    ]
    if mode == TRAIN_MODE:
        return
    elif mode == TEST_MODE and em_rule:
        subprocess.run(command + ["em-test", em_rule], check=True)
    else:
        subprocess.run(command, check=True)
        cnt = 0
        with open(os.path.join(analysis_dir, bnet_dir, "named_cons_all.txt"),
                  'r') as f:
            for line in f.readlines():
                cnt += 1
        print("Number of lines named_cons_all: {}".format(cnt))


def run_bingo(program, benchmark_dir, output_dir, analysis_type, bnet_dir,
              suffix):
    print("Running Bingo")
    command = [
        os.path.join(BINGO_DIR, "generate-ground-truth.py"), benchmark_dir,
        analysis_type, bnet_dir
    ]
    subprocess.run(command)
    command = [
        os.path.join(BINGO_DIR, "accmd"),
        os.path.join(output_dir, analysis_type),
        os.path.join(output_dir, analysis_type, bnet_dir, "Alarm.txt"),
        os.path.join(output_dir, analysis_type, bnet_dir, "GroundTruth.txt"),
        "/dev/null", "500", "/dev/null", bnet_dir, suffix,
        os.path.join(LIBDAI_HOME, "bingo")
    ]
    subprocess.run(command)


def run_em_train_bingo(program, benchmark_dir, output_dir, analysis_type,
                       bnet_dir, suffix, fg_file):
    print("Running Bingo (em-train)")
    command = [
        os.path.join(BINGO_DIR, "generate-ground-truth.py"), benchmark_dir,
        analysis_type, bnet_dir
    ]
    subprocess.run(command)
    command = [
        os.path.join(BINGO_DIR, "em-train-accmd"),
        os.path.join(output_dir, analysis_type),
        os.path.join(output_dir, analysis_type, bnet_dir, "Alarm.txt"),
        os.path.join(output_dir, analysis_type, bnet_dir, "GroundTruth.txt"),
        "/dev/null", "500", "/dev/null", bnet_dir, suffix,
        os.path.join(LIBDAI_HOME, "bingo"), fg_file
    ]
    subprocess.run(command)


def run_em_test_bingo(program, benchmark_dir, output_dir, analysis_type,
                      bnet_dir, suffix):
    print("Running Bingo (em-test)")
    command = [
        os.path.join(BINGO_DIR, "generate-ground-truth.py"), benchmark_dir,
        analysis_type, bnet_dir
    ]
    subprocess.run(command)
    command = [
        os.path.join(BINGO_DIR, "em-test-accmd"),
        os.path.join(output_dir, analysis_type),
        os.path.join(output_dir, analysis_type, bnet_dir, "Alarm.txt"),
        os.path.join(output_dir, analysis_type, bnet_dir, "GroundTruth.txt"),
        "/dev/null", "500", "/dev/null", bnet_dir, suffix,
        os.path.join(LIBDAI_HOME, "bingo")
    ]
    subprocess.run(command)


def generate_named_cons(args, program, version, analysis_type, bnet_dir):
    print("Generating Datalog Rules")
    benchmark_dir = os.path.join(BENCHMARK_DIR, program)
    output_dir = os.path.join(benchmark_dir, version, "sparrow-out")
    command = [
        os.path.join(BINGO_DIR, "generator"), analysis_type, output_dir,
        bnet_dir
    ]
    subprocess.run(command, check=True)


def rank(args, benchmark_list):
    if args.target == "all":
        print("Not supported yet")
        exit(1)
    else:
        path = os.path.abspath(args.target)
        program = os.path.basename(os.path.dirname(path))
        version = os.path.basename(path)
        benchmark_dir = os.path.join(BENCHMARK_DIR, program, version)
        output_dir = os.path.join(benchmark_dir, "sparrow-out")

        json_info = os.path.join(path, "sparrow", "info.json")
        with open(json_info) as f:
            analysis_info = json.load(f)
        analysis_type = analysis_info["type"]

        if args.reuse and os.path.isdir(
                os.path.join(output_dir, analysis_type + '/bnet')):
            print("(reuse old bayesian network)")
            suffix = args.reuse
            bnet_dir = 'bnet-' + args.reuse
        else:
            if args.timestamp is None:
                suffix = datetime.today().strftime('%Y%m%d-%H:%M:%S')
            else:
                suffix = args.timestamp
            bnet_dir = 'bnet-' + suffix
            os.makedirs(os.path.join(output_dir, analysis_type, bnet_dir),
                        exist_ok=True)
            if not args.skip_generate_named_cons:
                generate_named_cons(args, program, version, analysis_type,
                                    bnet_dir)
            build_bnet(program, version, analysis_type, bnet_dir,
                       args.skip_compress, "RANK", None)
        if os.path.exists(os.path.join(benchmark_dir, 'label.json')):
            run_bingo(program, benchmark_dir, output_dir, analysis_type,
                      bnet_dir, suffix)


def em_train(args, benchmark_list):
    if args.target == "all":
        print("Not supported yet")
        exit(1)
    else:
        path = os.path.abspath(args.target)
        program = os.path.basename(os.path.dirname(path))
        version = os.path.basename(path)
        benchmark_dir = os.path.join(BENCHMARK_DIR, program, version)
        output_dir = os.path.join(benchmark_dir, "sparrow-out")

        json_info = os.path.join(path, "sparrow", "info.json")
        with open(json_info) as f:
            analysis_info = json.load(f)
        analysis_type = analysis_info["type"]

        if args.reuse and os.path.isdir(
                os.path.join(output_dir, analysis_type + '/bnet')):
            print("(reuse old bayesian network)")
            suffix = args.reuse
            bnet_dir = 'bnet-' + args.reuse
        else:
            if args.timestamp is None:
                suffix = datetime.today().strftime('%Y%m%d-%H:%M:%S')
            else:
                suffix = args.timestamp
            bnet_dir = 'bnet-' + suffix
            os.makedirs(os.path.join(output_dir, analysis_type, bnet_dir),
                        exist_ok=True)
            if not args.skip_generate_named_cons:
                generate_named_cons(args, program, version, analysis_type,
                                    bnet_dir)
            build_bnet(program, version, analysis_type, bnet_dir, False,
                       TRAIN_MODE, None)
        if os.path.exists(os.path.join(benchmark_dir, 'label.json')):
            run_em_train_bingo(program, benchmark_dir, output_dir,
                               analysis_type, bnet_dir, suffix, args.fg_file)


def em_test(args, benchmark_list):
    if args.target == "all":
        print("Not supported yet")
        exit(1)
    else:
        path = os.path.abspath(args.target)
        program = os.path.basename(os.path.dirname(path))
        version = os.path.basename(path)
        benchmark_dir = os.path.join(BENCHMARK_DIR, program, version)
        output_dir = os.path.join(benchmark_dir, "sparrow-out")

        json_info = os.path.join(path, "sparrow", "info.json")
        with open(json_info) as f:
            analysis_info = json.load(f)
        analysis_type = analysis_info["type"]

        if args.reuse and os.path.isdir(
                os.path.join(output_dir, analysis_type + '/bnet')):
            print("(reuse old bayesian network)")
            suffix = args.reuse
            bnet_dir = 'bnet-' + args.reuse
        else:
            if args.timestamp is None:
                suffix = datetime.today().strftime('%Y%m%d-%H:%M:%S')
            else:
                suffix = args.timestamp
            bnet_dir = 'bnet-' + suffix
            os.makedirs(os.path.join(output_dir, analysis_type, bnet_dir),
                        exist_ok=True)
            if not args.skip_generate_named_cons:
                generate_named_cons(args, program, version, analysis_type,
                                    bnet_dir)
            rule_prob_file = os.path.join(PROJECT_HOME, args.rule_prob_file)
            build_bnet(program, version, analysis_type, bnet_dir, False,
                       TEST_MODE, rule_prob_file)
        if os.path.exists(os.path.join(benchmark_dir, 'label.json')):
            run_em_test_bingo(program, benchmark_dir, output_dir,
                              analysis_type, bnet_dir, suffix)


def translate_cons(new_path, old_output_path, new_output_path, analysis_type,
                   old_bnet_id, new_bnet_id):
    old_bnet = os.path.join(old_output_path, analysis_type, old_bnet_id)
    new_bnet = os.path.join(new_output_path, analysis_type, new_bnet_id)
    old_named_cons = os.path.join(old_bnet, "named_cons_all.txt")
    new_named_cons = os.path.join(new_bnet, "named_cons_all.txt")
    old_alarm = os.path.join(old_bnet, "Alarm.txt")
    new_alarm = os.path.join(new_bnet, "Alarm.txt")
    old_node = os.path.join(old_output_path, "node.json")
    new_node = os.path.join(new_output_path, "node.json")
    command = [
        os.path.join(BINGO_DIR, "translate-cons.py"), old_named_cons,
        new_named_cons, old_alarm, new_alarm, old_node, new_node,
        os.path.join(new_path, "line_matching.json"), new_bnet
    ]
    with open(os.path.join(new_bnet, "translate-cons.err"), 'w+') as f:
        subprocess.run(command, stderr=f)


def delta(old_path, new_path, analysis_type, old_bnet_id, new_bnet_id):
    command = [
        os.path.join(BINGO_DIR, "sem-eps.sh"), old_path, new_path,
        analysis_type, old_bnet_id, new_bnet_id, "strong", "0.001"
    ]
    subprocess.run(command)


def drake(args):
    # TODO: simplify
    old_path = os.path.abspath(args.old)
    new_path = os.path.abspath(args.new)
    json_info = os.path.join(new_path, "sparrow", "info.json")
    with open(json_info) as f:
        analysis_info = json.load(f)
    analysis_type = analysis_info["type"]
    old_output_path = os.path.join(old_path, "sparrow-out")
    new_output_path = os.path.join(new_path, "sparrow-out")
    # TODO: currently pick the latest one
    old_bnet_id = [
        d for d in os.listdir(os.path.join(old_output_path, analysis_type))
        if d.startswith("bnet-")
    ][-1]
    new_bnet_id = [
        d for d in os.listdir(os.path.join(new_output_path, analysis_type))
        if d.startswith("bnet-")
    ][-1]
    #    translate_cons(new_path, old_output_path, new_output_path, analysis_type,
    #                   old_bnet_id, new_bnet_id)
    delta(old_path, new_path, analysis_type, old_bnet_id, new_bnet_id)


def main():
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest='subcmd')
    parser_fetch = subparsers.add_parser('fetch')
    parser_fetch.add_argument('--since',
                              required=True,
                              type=lambda s: datetime.strptime(s, '%Y-%m-%d'))
    parser_fetch.add_argument('--until',
                              required=True,
                              type=lambda s: datetime.strptime(s, '%Y-%m-%d'))
    parser_analyze = subparsers.add_parser('analyze')
    parser_analyze.add_argument('target', type=str)
    parser_analyze.add_argument('--reuse', action='store_true')
    parser_analyze.add_argument('--save', action='store_true')
    parser_rank = subparsers.add_parser('rank')
    parser_rank.add_argument('target', type=str)
    parser_rank.add_argument('--reuse', type=str)
    parser_rank.add_argument('--skip-generate-named-cons', action='store_true')
    parser_rank.add_argument('--timestamp', type=str)
    parser_rank.add_argument('--datalog', type=str)
    parser_rank.add_argument('--skip-compress', action='store_true')
    parser_em_train = subparsers.add_parser('em-train')
    parser_em_train.add_argument('target', type=str)
    parser_em_train.add_argument('fg_file', type=str)
    parser_em_train.add_argument('--timestamp', type=str)
    parser_em_test = subparsers.add_parser('em-test')
    parser_em_test.add_argument('target', type=str)
    parser_em_test.add_argument('rule_prob_file', type=str)
    parser_em_test.add_argument('--timestamp', type=str)
    parser_drake = subparsers.add_parser('drake')
    parser_drake.add_argument('--old', type=str, required=True)
    parser_drake.add_argument('--new', type=str, required=True)

    args = parser.parse_args()
    benchmark_list = initialize()

    if args.subcmd == "fetch":
        fetch(args, benchmark_list)
    elif args.subcmd == "analyze":
        analyze(args, benchmark_list)
    elif args.subcmd == "rank":
        rank(args, benchmark_list)
    elif args.subcmd == "em-train":
        em_train(args, benchmark_list)
    elif args.subcmd == "em-test":
        em_test(args, benchmark_list)
    elif args.subcmd == "drake":
        drake(args)
    else:
        print("Unknown subcommand")
        exit(1)


if __name__ == "__main__":
    main()
