#!/usr/bin/env python3
"""Merge a recorded KDE config file into an existing one, key by key.

Groups and keys from the snapshot replace the matching ones in the target;
every other group and key in the target is preserved, so settings written by
apply-kde.sh or created on the new machine survive. Prints "changed" or
"unchanged".
"""
import pathlib
import sys


def parse(text):
    groups, order, current = {}, [], None
    preamble = []
    for line in text.splitlines():
        if line.startswith("["):
            current = line.strip()
            if current not in groups:
                groups[current] = []
                order.append(current)
        elif current is None:
            if line.strip():
                preamble.append(line)
        elif line.strip():
            groups[current].append(line)
    return preamble, groups, order


def key_of(line):
    return line.split("=", 1)[0].strip()


def merge(target_text, snapshot_text):
    preamble, groups, order = parse(target_text)
    snapshot_preamble, snapshot_groups, snapshot_order = parse(snapshot_text)
    for line in snapshot_preamble:
        replaced = False
        for index, existing in enumerate(preamble):
            if "=" in line and key_of(existing) == key_of(line):
                preamble[index] = line
                replaced = True
        if not replaced and line not in preamble:
            preamble.append(line)
    for group in snapshot_order:
        if group not in groups:
            groups[group] = []
            order.append(group)
        lines = groups[group]
        for line in snapshot_groups[group]:
            if "=" not in line:
                if line not in lines:
                    lines.append(line)
                continue
            for index, existing in enumerate(lines):
                if "=" in existing and key_of(existing) == key_of(line):
                    lines[index] = line
                    break
            else:
                lines.append(line)
    blocks = []
    if preamble:
        blocks.append("\n".join(preamble))
    blocks.extend("\n".join([group] + groups[group]) for group in order)
    return "\n\n".join(blocks) + "\n"


def main():
    if len(sys.argv) != 3:
        sys.exit("usage: merge-kde-config.py SNAPSHOT TARGET")
    snapshot, target = map(pathlib.Path, sys.argv[1:])
    original = target.read_text() if target.exists() else ""
    merged = merge(original, snapshot.read_text())
    # Compare against the target's own normalized form so formatting alone
    # never counts as a change.
    if merged == merge(original, ""):
        print("unchanged")
        return
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(merged)
    print("changed")


if __name__ == "__main__":
    main()
