#!/usr/bin/env python3
"""Filter machine snapshot entries through machine/hardware-rules.tsv.

Reads one entry per line on stdin and prints the entries allowed for the
active hardware gates. With --skipped, prints "entry<TAB>gate" for the
entries that were held back instead.
"""
import argparse
import pathlib
import re
import sys


def load_rules(path):
    rules = []
    for line in pathlib.Path(path).read_text().splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        pattern, gate = line.split("\t")
        rules.append((re.compile(rf"(?:{pattern})"), gate.strip()))
    return rules


def required_gate(entry, rules):
    for pattern, gate in rules:
        if pattern.fullmatch(entry):
            return gate
    return None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("rules")
    parser.add_argument("gates", help="comma-separated active gates")
    parser.add_argument("--skipped", action="store_true")
    arguments = parser.parse_args()
    rules = load_rules(arguments.rules)
    active = {gate for gate in arguments.gates.split(",") if gate}
    for entry in (line.strip() for line in sys.stdin):
        if not entry:
            continue
        gate = required_gate(entry, rules)
        allowed = gate is None or gate in active
        if allowed and not arguments.skipped:
            print(entry)
        elif not allowed and arguments.skipped:
            print(f"{entry}\t{gate}")


if __name__ == "__main__":
    main()
