#!/usr/bin/env python3
"""lens payload helper: mask a captured request/response and store it as a payload file.

  redact.py --out DIR --id ID --service NAME --method GET --route /orders/:id [--when ISO] [--request FILE|-] [--response FILE|-]

Writes DIR/payloads/NN-ID.json and prints the payloads[] entry to paste into data.json. Bodies are JSON when they parse,
otherwise a cut string. Masked: secrets by key name, file contents, SSN-like values, emails, bearer tokens and JWTs.
Never edit a captured body to make it prettier: mask or cut only.
"""
import argparse
import json
import re
import sys
from pathlib import Path

SENS = re.compile(r"ssn|token|password|passwd|secret|authorization|cookie|private[_-]?key|api[_-]?key|credit|card|cvv|dob|birth", re.I)
FILE_KEY = re.compile(r"base64|file_content|file_body", re.I)
VALUE_MASKS = [
    (re.compile(r"\b\d{3}-\d{2}-\d{4}\b"), "<redacted>"),
    (re.compile(r"[\w.+-]+@[\w-]+\.[\w.-]+"), "<email>"),
    (re.compile(r"Bearer\s+[\w.~+/=-]+", re.I), "Bearer <redacted>"),
    (re.compile(r"\beyJ[\w-]+\.[\w-]+\.[\w-]+\b"), "<jwt>"),
]
CUT = 400


def redact(o, key=""):
    if isinstance(o, dict):
        return {k: redact(v, k) for k, v in o.items()}
    if isinstance(o, list):
        return [redact(v, key) for v in o]
    if o is None or isinstance(o, bool):
        return o
    if FILE_KEY.search(key):
        return f"<file content omitted, {len(str(o))} chars>"
    if SENS.search(key):
        return "<redacted>"
    if isinstance(o, str):
        for rx, repl in VALUE_MASKS:
            o = rx.sub(repl, o)
        if len(o) > CUT:
            o = o[: CUT // 2] + f"...<{len(o)} chars>"
    return o


def parse(text):
    if not text or not text.strip():
        return None
    try:
        return redact(json.loads(text))
    except ValueError:
        return redact(text.strip()[:CUT * 2])


def slug(s):
    return re.sub(r"[^a-z0-9]+", "-", s.lower()).strip("-")[:48]


def read(src):
    if not src:
        return None
    return sys.stdin.read() if src == "-" else Path(src).expanduser().read_text()


def write_payload(out, pid, service, method, route, when, request, response):
    d = Path(out).expanduser() / "payloads"
    d.mkdir(parents=True, exist_ok=True)
    n = len(list(d.glob("*.json"))) + 1
    name = f"{n:02d}-{slug(pid)}.json"
    (d / name).write_text(json.dumps({"when": when, "service": service, "method": method, "route": route,
                                      "request": parse(request), "response": parse(response)}, indent=1) + "\n")
    return {"id": pid, "title": f"{method} {route}".strip(), "file": f"payloads/{name}", "proto": "HTTP", "summary": "TODO", "annotations": []}


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", required=True)
    ap.add_argument("--id", required=True)
    ap.add_argument("--service", default="")
    ap.add_argument("--method", default="")
    ap.add_argument("--route", default="")
    ap.add_argument("--when", default="")
    ap.add_argument("--request")
    ap.add_argument("--response")
    a = ap.parse_args()
    if a.request == "-" and a.response == "-":
        sys.exit("error: only one of --request and --response can read stdin")
    entry = write_payload(a.out, a.id, a.service, a.method, a.route, a.when, read(a.request), read(a.response))
    print(json.dumps(entry, indent=1))


if __name__ == "__main__":
    main()
