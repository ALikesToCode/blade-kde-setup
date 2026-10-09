"""Edit keys inside one Codex TOML table while leaving every other line untouched.

Codex Desktop rewrites ~/.codex/config.toml from its UI, so edits stay line-based
instead of re-serialising the whole document, and every result is re-parsed
before it is written.
"""

import re
import tomllib

HEADER = re.compile(r"^\s*\[\[?\s*(?P<name>[^\]]+?)\s*\]\]?\s*(#.*)?$")


class ConfigError(Exception):
    pass


def normalise(table):
    return re.sub(r"\s*\.\s*", ".", table).replace('"', "")


def _table_of(line):
    match = HEADER.match(line)
    return normalise(match.group("name")) if match else None


def _span(lines, table):
    """Return the header index and the end of the table's own key lines."""
    wanted = normalise(table)
    for start, line in enumerate(lines):
        if _table_of(line) == wanted:
            end = start + 1
            while end < len(lines) and _table_of(lines[end]) is None:
                end += 1
            return start, end
    return None


def _key_lines(lines, start, end, key):
    """Return the first line and the end of a key, following multi-line arrays."""
    pattern = re.compile(rf"^\s*\"?{re.escape(key)}\"?\s*=")
    for first in range(start, end):
        if not pattern.match(lines[first]):
            continue
        depth = 0
        for last in range(first, end):
            depth += lines[last].count("[") - lines[last].count("]")
            if depth <= 0:
                return first, last + 1
        return first, end
    return None


def set_key(text, table, key, literal):
    lines = text.splitlines()
    span = _span(lines, table)
    if span is None:
        if lines and lines[-1].strip():
            lines.append("")
        lines += [f"[{table}]", f"{key} = {literal}"]
    else:
        start, end = span
        found = _key_lines(lines, start + 1, end, key)
        if found:
            lines[found[0]:found[1]] = [f"{key} = {literal}"]
        else:
            insert = end
            while insert > start + 1 and not lines[insert - 1].strip():
                insert -= 1
            lines.insert(insert, f"{key} = {literal}")
    return "\n".join(lines) + "\n"


def drop_key(text, table, key):
    lines = text.splitlines()
    span = _span(lines, table)
    if span is None:
        return text
    found = _key_lines(lines, span[0] + 1, span[1], key)
    if found is None:
        return text
    del lines[found[0]:found[1]]
    return "\n".join(lines) + "\n"


def parse(text, origin="config"):
    try:
        return tomllib.loads(text)
    except tomllib.TOMLDecodeError as error:
        raise ConfigError(f"{origin} is not valid TOML: {error}") from error
