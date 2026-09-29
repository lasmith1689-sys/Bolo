#!/usr/bin/env python3
"""Turns compiler and test errors in a build log into GitHub annotations, so failures can be read
from the run page (or the API) without downloading logs.

  annotate_errors.py <log> [label]

GitHub shows at most 10 error annotations per step, so the first 9 distinct errors get their own
file/line annotation and everything else (up to 40 in total) is folded into one more annotation.
Also prints the last 60 lines of the log.
"""
import os
import re
import sys

log_path = sys.argv[1]
label = sys.argv[2] if len(sys.argv) > 2 else "Build"
workspace = os.environ.get("GITHUB_WORKSPACE", os.getcwd()).rstrip("/") + "/"
pattern = re.compile(r"^(?P<file>/[^:\n]+?):(?P<line>\d+):(?:(?P<col>\d+):)? (?:fatal )?error: (?P<msg>.*)$")


def esc(s):
    return s.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")


try:
    lines = open(log_path, encoding="utf-8", errors="replace").read().splitlines()
except FileNotFoundError:
    print(f"::error::{label}: no log at {log_path}")
    sys.exit(0)

seen, errors = set(), []
for raw in lines:
    raw = raw.strip()
    m = pattern.match(raw)
    if m:
        path = m["file"]
        rel = path[len(workspace):] if path.startswith(workspace) else path
        key = (rel, m["line"], m["msg"])
        if key not in seen:
            seen.add(key)
            errors.append((rel, m["line"], m["msg"]))
    elif " error: " in raw or raw.startswith("error:") or "** BUILD FAILED **" in raw or "** TEST FAILED **" in raw:
        key = (None, None, raw)
        if key not in seen:
            seen.add(key)
            errors.append((None, None, raw))

errors = errors[:40]
for rel, line, msg in errors[:9]:
    if rel:
        print(f"::error file={rel},line={line},title={esc(label)}::{esc(msg)}")
    else:
        print(f"::error title={esc(label)}::{esc(msg)}")
rest = errors[9:]
if rest:
    body = "\n".join(f"{r}:{l}: {m}" if r else m for r, l, m in rest)
    print(f"::error title={esc(label)} (more)::{esc(body)}")

print(f"----- last 60 lines of {log_path} -----")
print("\n".join(lines[-60:]))
