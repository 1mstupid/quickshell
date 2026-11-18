"""Reads and writes the shell's config.toml (~/.config/lumin/config.toml).

  config.py read PATH                  print the file as JSON; {} when missing or broken
  config.py set PATH TABLE KEY JSON    set one value and write the file back

Run by Config.qml with python3 -I, so nothing from the config folder is imported.
A write replaces the file in one step (temp file, then rename), so the shell's
watcher never reads half of it. A write refuses to run on a broken file rather than
overwrite what the user wrote. Comments are not kept on a write.
"""
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


def load(path):
    """The parsed file, {} when there is none. Raises when it exists but is broken."""
    try:
        with open(path, "rb") as f:
            return tomllib.load(f)
    except FileNotFoundError:
        return {}


def read(path):
    try:
        return load(path)
    except (OSError, tomllib.TOMLDecodeError) as e:
        print(f"config: {path}: {e}", file=sys.stderr)
        return {}


def write(path, doc):
    folder = os.path.dirname(path)
    os.makedirs(folder, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=folder, prefix=".config-", suffix=".toml")
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write(dumps(doc))
    os.replace(tmp, path)


def main(argv):
    if len(argv) == 2 and argv[0] == "read":
        print(json.dumps(read(argv[1])))
        return 0
    if len(argv) == 5 and argv[0] == "set":
        path, table, key, raw = argv[1:]
        try:
            doc = load(path)
            if not isinstance(doc.get(table, {}), dict):
                raise ValueError(f"[{table}] is not a table")
            doc.setdefault(table, {})[key] = json.loads(raw)
            write(path, doc)
        except Exception as e:  # the shell shows nothing; the message reaches the journal
            print(f"config: set {table}.{key} failed: {e}", file=sys.stderr)
            return 1
        return 0
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
