"""Reads and writes the shell's config.toml (~/.config/lumin/config.toml).

  config.py read PATH                  print the file as JSON; {} when missing or broken
  config.py set PATH TABLE KEY JSON    set one value and write the file back

Run by Config.qml with python3 -I, so nothing from the config folder is imported.
A set changes only that one line: comments, blank lines and the rest of the layout stay
as written, and a new key goes at the end of its table. If that edit cannot be checked,
the file is rewritten from its parsed values instead, which keeps the data but drops
comments. A write replaces the file in one step (temp file, then rename), so the shell's
watcher never reads half of it. A set refuses to run on a broken file rather than
overwrite what the user wrote.
"""
import copy
import json
import os
import sys
import tempfile
import tomllib

BARE_KEY = set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")


def fmt_key(k):
    # keys like "org.app" or "prefix*" need quotes; JSON strings are valid TOML basic strings
    return k if k and all(c in BARE_KEY for c in k) else json.dumps(k)


def fmt_value(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(v)
    if isinstance(v, str):
        return json.dumps(v)
    if isinstance(v, list):
        return "[" + ", ".join(fmt_value(x) for x in v) + "]"
    raise ValueError(f"cannot write {type(v).__name__} to config.toml")


def dumps(doc):
    lines = [f"{fmt_key(k)} = {fmt_value(v)}" for k, v in doc.items() if not isinstance(v, dict)]
    for name, table in doc.items():
        if isinstance(table, dict):
            lines += ["", f"[{fmt_key(name)}]"]
            lines += [f"{fmt_key(k)} = {fmt_value(v)}" for k, v in table.items()]
    return "\n".join(lines) + "\n"


def read_text(path):
    try:
        with open(path, encoding="utf-8", newline="") as f:
            return f.read()
    except FileNotFoundError:
        return ""


def load(path):
    """The parsed file, {} when there is none. Raises when it exists but is broken."""
    return tomllib.loads(read_text(path))


def read(path):
    try:
        return load(path)
    except (OSError, tomllib.TOMLDecodeError) as e:
        print(f"config: {path}: {e}", file=sys.stderr)
        return {}


def header_name(line):
    """The table name when the (stripped) line is a [table] header, else None."""
    if not line.startswith("["):
        return None
    try:
        d = tomllib.loads(line)
    except tomllib.TOMLDecodeError:
        return None
    if len(d) == 1:
        (name, value), = d.items()
        if isinstance(value, dict) and not value:
            return name
    return None


def key_comment(line, key):
    """Where the trailing comment of a `key = value` line starts (len(line) when none),
    or None when the line is not that key. The first '#' that leaves a valid line before
    it is the comment, so a '#' inside a string is not mistaken for one."""
    for k in [i for i, c in enumerate(line) if c == "#"] + [len(line)]:
        try:
            d = tomllib.loads(line[:k])
        except tomllib.TOMLDecodeError:
            continue
        return k if list(d) == [key] else None
    return None


def edit(text, table, key, value):
    """The text with table.key set to value, changing only that line where it can."""
    lines = text.splitlines(keepends=True)
    start = end = None
    for i, line in enumerate(lines):
        name = header_name(line.strip())
        if name is None:
            continue
        if start is not None:
            end = i
            break
        if name == table:
            start = i
    if start is None:
        sep = "\n" if text.strip() else ""
        if text and not text.endswith("\n"):
            text += "\n"
        return f"{text}{sep}[{fmt_key(table)}]\n{fmt_key(key)} = {fmt_value(value)}\n"
    if end is None:
        end = len(lines)
    for i in range(start + 1, end):
        body = lines[i].rstrip("\r\n")
        k = key_comment(body, key)
        if k is not None:
            rest = body[k:]
            lines[i] = f"{fmt_key(key)} = {fmt_value(value)}" + (" " + rest if rest else "") \
                + lines[i][len(body):]
            return "".join(lines)
    # a new key goes after the table's last line with content
    last = start
    for i in range(start + 1, end):
        if lines[i].strip():
            last = i
    if not lines[last].endswith("\n"):
        lines[last] += "\n"
    lines.insert(last + 1, f"{fmt_key(key)} = {fmt_value(value)}\n")
    return "".join(lines)


def write_text(path, text):
    folder = os.path.dirname(path) or "."
    os.makedirs(folder, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=folder, prefix=".config-", suffix=".toml")
    with os.fdopen(fd, "w", encoding="utf-8", newline="") as f:
        f.write(text)
    os.replace(tmp, path)


def set_value(path, table, key, raw):
    text = read_text(path)
    doc = tomllib.loads(text)  # a broken file raises here, before anything is written
    if not isinstance(doc.get(table, {}), dict):
        raise ValueError(f"[{table}] is not a table")
    value = json.loads(raw)
    expected = copy.deepcopy(doc)
    expected.setdefault(table, {})[key] = value
    new = edit(text, table, key, value)
    try:
        checked = tomllib.loads(new) == expected
    except tomllib.TOMLDecodeError:  # an edit that left invalid TOML is not written
        checked = False
    if not checked:
        print("config: the edit could not be checked, so the file was rewritten and its "
              "comments are gone", file=sys.stderr)
        new = dumps(expected)
    write_text(path, new)


def main(argv):
    if len(argv) == 2 and argv[0] == "read":
        print(json.dumps(read(argv[1])))
        return 0
    if len(argv) == 5 and argv[0] == "set":
        path, table, key, raw = argv[1:]
        try:
            set_value(path, table, key, raw)
        except Exception as e:  # the shell shows nothing; the message reaches the journal
            print(f"config: set {table}.{key} failed: {e}", file=sys.stderr)
            return 1
        return 0
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
