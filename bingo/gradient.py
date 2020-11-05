#!/usr/bin/env python3
import argparse

# TODO: check if analysis is done
# TODO: check if timestamp is unified among benchmarks

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Find the worst v-curve")
    parser.add_argument('one_out_prog',
                        metavar='ONE_OUT_PROG',
                        help='target program that will be left out')

    args = parser.parse_args()
    false_alarm = "Alarm(_G_-ENTRY,ftp_parse_vms_ls-131962)"
    true_alarm = "Alarm(_G_-ENTRY,ftp_parse_vms_ls-131842)"
    print("FALSE:{},TRUE:{}".format(false_alarm, true_alarm))
