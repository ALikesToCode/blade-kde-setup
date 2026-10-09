#!/usr/bin/env python3
"""Print an fstab with the entry for one mount point replaced or added.

Usage: fstab-entry.py FSTAB MOUNT_POINT SPEC TYPE OPTIONS DUMP PASS

Only the uncommented line whose second field is MOUNT_POINT changes; comments,
spacing, and every other entry are kept. More than one entry for the mount
point is refused rather than guessed at.
"""

import sys


def replace_entry(text, mount_point, fields):
    lines = text.splitlines()
    matches = [index for index, line in enumerate(lines)
               if line.strip() and not line.lstrip().startswith("#")
               and len(line.split()) > 1 and line.split()[1] == mount_point]
    if len(matches) > 1:
        raise ValueError(f"{len(matches)} entries mount {mount_point}")
    entry = " ".join(fields)
    if matches:
        lines[matches[0]] = entry
    else:
        if lines and lines[-1].strip():
            lines.append("")
        lines.append(entry)
    return "\n".join(lines) + "\n"


def main(argv):
    if len(argv) != 8:
        print(__doc__.strip().splitlines()[2], file=sys.stderr)
        return 2
    fstab, mount_point, *fields = argv[1:]
    if any(not field or any(character.isspace() for character in field) for field in fields):
        print("fstab-entry: fields must be non-empty and contain no spaces", file=sys.stderr)
        return 2
    with open(fstab) as stream:
        text = stream.read()
    try:
        sys.stdout.write(replace_entry(text, mount_point, [fields[0], mount_point, *fields[1:]]))
    except ValueError as error:
        print(f"fstab-entry: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
