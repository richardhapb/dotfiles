#!/usr/bin/env python3
"""lens builder: data.json (authored, small) + scan.json (mechanical, optional) + payloads/ -> index.html.

  build.py <dir> [--open]

The model writes notes keyed by scan ids; this step fills in file:line, text, service names and links, lints the
diagrams, and renders one self-contained page. Re-running it is free and upgrades links once the branch is pushed.
If <dir> sits at <root>/<kind>/<name> it also rebuilds <root>/INDEX.html.
"""
import json
import os
import re
import subprocess
import sys
import webbrowser
from html import escape
from pathlib import Path
from urllib.parse import quote

HERE = Path(__file__).resolve().parent
TEMPLATE = HERE.parent / "template.html"
ROOT = Path(os.environ.get("LENS_ROOT", Path.home() / "lens"))
KINDS = ("change", "flow")
CHANNEL_LABEL = {"http": "HTTP", "grpc": "gRPC", "kafka": "Kafka", "temporal": "Temporal", "sql": "SQL", "webhook": "webhook",
                 "endpoint": "Endpoint", "nosql": "Mongo", "redis": "Redis", "queue": "Queue", "blob": "Blob store", "flag": "Flag"}
DIRECTION = {"out": "calls out", "in": "receives", "def": "defines", "orch": "orchestrates", "ref": "references", "rw": "reads/writes",
             "schema": "schema", "read": "reads"}
REQUIRED = ("meta", "tldr")
NODE_MAX, EDGE_MAX = 40, 24


def link(repo, path, line):
    if not repo.get("linkable") or not repo.get("host") or not repo.get("project") or not repo.get("head_sha"):
        return None
    mid = "/blob/" if repo.get("kind") == "github" else "/-/blob/"
    return f"https://{repo['host']}/{repo['project']}{mid}{repo['head_sha']}/{quote(path)}" + (f"#L{line}" if line else "")


def refresh_links(repo):
    """Re-check push state, so a rebuild after `git push` upgrades path:line text to links."""
    if repo.get("dir") and not repo.get("linkable") and repo.get("head_sha"):
        p = subprocess.run(["git", "branch", "-r", "--contains", repo["head_sha"]], cwd=repo["dir"], capture_output=True, text=True)
        if p.returncode == 0 and p.stdout.strip():
            repo["pushed"] = repo["linkable"] = True


def where(repo, file, line, removed=False):
    return {"label": f"{file}:{line}", "url": None if removed else link(repo, file, line)}


def row(h, repo, note=None, service=None):
    return {
        "id": h["id"], "service": service or ", ".join(h.get("services") or []) or "",
        "channel": CHANNEL_LABEL.get(h["channel"], h["channel"]), "direction": DIRECTION.get(h["direction"], h["direction"]),
        "target": h.get("target") or "", "where": where(repo, h["file"], h["line"], h.get("removed")),
        "text": h["text"], "removed": h.get("removed", False), "note": note or "",
    }


def resolve_at(items, hits, repo, problems, what):
    """Turn `at: "H3"` on diagram nodes and steps into a `where` the template can render."""
    for it in items:
        ref = it.get("at")
        if not ref:
            continue
        h = hits.get(ref)
        if h is None:
            problems.append(f"{what} '{it.get('label') or it.get('id')}' points at {ref}, which is not in scan.json")
            continue
        it["where"] = where(repo, h["file"], h["line"], h.get("removed"))


def expand(data, scan):
    repo = scan["repo"]
    refresh_links(repo)
    hits = {h["id"]: h for h in scan["hits"]}
    problems = []
    picks = data.get("touchpoints") or []
    rows, used = [], set()
    for p in picks:
        h = hits.get(p.get("id"))
        if not h:
            problems.append(f"touchpoint {p.get('id')} is not in scan.json")
            continue
        used.add(h["id"])
        rows.append(row(h, repo, p.get("note"), p.get("service")))
    more = [row(h, repo) for h in scan["hits"] if h["id"] not in used]
    if repo.get("linkable"):
        lead = f"Each row links to the exact line, pinned to commit `{repo['head_sha'][:8]}`; line numbers are valid at that commit only."
    else:
        lead = "Not pushed yet, so rows show `file:line` without links. Run the build step again after the push to get links."
    data["touchpoints"] = {"lead": lead, "rows": rows, "more": more}
    resolve_at((data.get("flow") or {}).get("nodes", []), hits, repo, problems, "flow node")
    resolve_at((data.get("states") or {}).get("nodes", []), hits, repo, problems, "state")
    resolve_at((data.get("sequence") or {}).get("steps", []), hits, repo, problems, "sequence step")
    data["signalsAuto"] = [{"kind": s["kind"], "name": s.get("name") or s["text"][:60], "where": where(repo, s["file"], s["line"])} for s in scan["signals"]]
    ev = list(data.get("evidence") or [])
    st, sha = scan["stats"], f"commit `{repo['head_sha'][:8]}`" + ("" if repo.get("linkable") else " (not pushed)")
    if scan.get("mode") == "paths":
        ev.append({"claim": f"Read {st['files']} file(s) statically at HEAD; nothing was run.", "status": "code", "source": sha})
    else:
        ev.append({"claim": f"Scanned the diff statically: {st['files']} files, +{st['added']} -{st['removed']}; nothing was run.", "status": "code", "source": sha})
    not_read = [f for f in scan["files"] if f["category"] == "code" and not f.get("read")]
    if not_read:
        ev.append({"claim": f"Not read: {len(not_read)} code file(s) over the read budget ({', '.join(f['path'] for f in not_read[:4])}{' ...' if len(not_read) > 4 else ''}).", "status": "unverified", "source": "scan.json"})
    if scan.get("review") and scan["review"].get("description"):
        ev.append({"claim": "The motivation comes from the description.", "status": "reported", "source": scan["review"]["label"] + " description"})
    for w in scan.get("warnings") or []:
        ev.append({"claim": w, "status": "unverified", "source": "scan"})
    data["evidence"] = ev
    if scan.get("review") and scan["review"].get("url") and not data["meta"].get("refs"):
        data["meta"]["refs"] = [{"label": scan["review"]["label"], "url": scan["review"]["url"]}]
    return problems


def lint_graph(name, g, actor_key=None):
    """Checks that save a rebuild round trip: ids, dangling edges, labels the renderer would cut."""
    out, ids, seen = [], [], set()
    for n in g.get("nodes", []):
        if n["id"] in seen:
            out.append(f"{name}: duplicate node id '{n['id']}'")
        seen.add(n["id"])
        ids.append(n["id"])
        if len(n.get("label", "")) > NODE_MAX:
            out.append(f"{name}: node label over {NODE_MAX} characters, it will be cut: '{n['label'][:30]}...'")
    touched = set()
    for e in g.get("edges", []):
        for k in ("from", "to"):
            if e[k] not in seen:
                out.append(f"{name}: edge references unknown node '{e[k]}'")
        touched.update((e["from"], e["to"]))
        if len(e.get("label", "")) > EDGE_MAX:
            out.append(f"{name}: edge label over {EDGE_MAX} characters, it will be cut: '{e['label'][:30]}...'")
    for i in ids:
        if g.get("edges") and i not in touched:
            out.append(f"{name}: node '{i}' has no edges")
    return out


def lint(data, d):
    out = []
    for key in ("flow", "states"):
        if data.get(key):
            out += lint_graph(key, data[key])
    pids = {p["id"] for p in data.get("participants", [])}
    for e in data.get("edges", []):
        for k in ("from", "to"):
            if pids and e[k] not in pids:
                out.append(f"map: edge references unknown participant '{e[k]}'")
        if len(e.get("label", "")) > EDGE_MAX:
            out.append(f"map: edge label over {EDGE_MAX} characters, it will be cut: '{e['label'][:30]}...'")
    seq = data.get("sequence") or {}
    for a in seq.get("actors", []):
        if pids and a not in pids:
            out.append(f"sequence: actor '{a}' is not in participants")
    for i, st in enumerate(seq.get("steps", []), 1):
        for k in ("from", "to"):
            if st.get(k) and st[k] not in seq.get("actors", []):
                out.append(f"sequence: step {i} uses '{st[k]}', which is not in actors")
    todos = json.dumps(data).count("TODO")
    if todos:
        out.append(f"{todos} TODO placeholder(s) left in data.json")
    return out


def load_payloads(data, d):
    payloads = {}
    for p in data.get("payloads", []):
        f = d / p["file"]
        if not f.exists():
            sys.exit(f"error: payload file not found: {f}")
        payloads[p["id"]] = json.loads(f.read_text())
    return payloads


def js(obj):
    return json.dumps(obj, ensure_ascii=False).replace("</", "<\\/").replace("\u2028", "\\u2028").replace("\u2029", "\\u2029")


def render_html(data, payloads):
    return TEMPLATE.read_text().replace("/*__DATA__*/null", js(data), 1).replace("/*__PAYLOADS__*/{}", js(payloads), 1)


INDEX = """<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>lens index</title>
<style>:root{--bg:#f6f7f9;--panel:#fff;--ink:#1c2330;--mute:#5d6878;--line:#dfe3ea;--accent:#2f5bea;--soft:#e8eefe}
@media(prefers-color-scheme:dark){:root{--bg:#0f141c;--panel:#171e29;--ink:#e6eaf1;--mute:#98a3b5;--line:#2a3445;--accent:#7aa2ff;--soft:#1d2a47}}
body{margin:0;background:var(--bg);color:var(--ink);font:15px/1.5 -apple-system,BlinkMacSystemFont,"Segoe UI",Inter,sans-serif}
main{max-width:980px;margin:0 auto;padding:30px 22px 70px}h1{margin:0 0 4px}p.s{color:var(--mute);margin:0 0 18px}
input{width:100%;padding:10px 12px;border:1px solid var(--line);border-radius:9px;background:var(--panel);color:var(--ink);font-size:15px;margin-bottom:18px;box-sizing:border-box}
h2{font-size:13px;letter-spacing:.08em;text-transform:uppercase;color:var(--mute);margin:24px 0 8px}
a.c{display:block;background:var(--panel);border:1px solid var(--line);border-radius:11px;padding:12px 15px;margin:8px 0;text-decoration:none;color:var(--ink)}
a.c:hover{border-color:var(--accent)}a.c b{font-size:16px}a.c span{display:block;color:var(--mute);font-size:13.5px}
.t{display:inline-block;font-size:11px;background:var(--soft);color:var(--accent);border-radius:99px;padding:1px 8px;margin:4px 5px 0 0}.d{float:right;color:var(--mute);font-size:12px}</style></head><body><main>
<h1>lens</h1><p class="s">How things work, explained with diagrams. __COUNT__ pages.</p>
<input id="q" placeholder="Filter by title, tag, service..." autofocus>__BODY__
<script>const q=document.getElementById('q');q.oninput=()=>{const v=q.value.toLowerCase();document.querySelectorAll('a.c').forEach(a=>a.style.display=a.dataset.s.includes(v)?'':'none')}</script></main></body></html>"""


def build_index(root):
    entries = []
    for dj in sorted(root.glob("*/*/data.json")):
        try:
            entries.append((dj.parent, json.loads(dj.read_text())["meta"]))
        except (ValueError, KeyError):
            continue
    body = ""
    for kind in KINDS:
        items = sorted([e for e in entries if e[1].get("kind") == kind], key=lambda e: e[1].get("date", ""), reverse=True)
        if not items:
            continue
        body += f"<h2>{escape(kind)}</h2>"
        for d, m in items:
            tags = "".join(f'<span class="t">{escape(t)}</span>' for t in m.get("tags", []))
            hay = " ".join([m.get("title", ""), m.get("subtitle", ""), " ".join(m.get("tags", [])), d.name]).lower()
            body += (f'<a class="c" href="{escape(d.parent.name + "/" + d.name + "/index.html")}" data-s="{escape(hay, quote=True)}">'
                     f'<span class="d">{escape(m.get("date", ""))}</span><b>{escape(m.get("title", d.name))}</b><span>{escape(m.get("subtitle", ""))}</span>{tags}</a>')
    out = root / "INDEX.html"
    out.write_text(INDEX.replace("__BODY__", body).replace("__COUNT__", str(len(entries))))
    return out


def build(d):
    data = json.loads((d / "data.json").read_text())
    for k in REQUIRED:
        if k not in data:
            sys.exit(f"error: data.json is missing '{k}'")
    scan_file = d / "scan.json"
    problems = expand(data, json.loads(scan_file.read_text())) if scan_file.exists() else []
    if not scan_file.exists() and any(
            n.get("at") for key in ("flow", "states") for n in (data.get(key) or {}).get("nodes", [])):
        problems.append("nodes use `at`, but there is no scan.json to resolve it")
    problems += lint(data, d)
    out = d / "index.html"
    out.write_text(render_html(data, load_payloads(data, d)))
    return out, problems


def main():
    args = [a for a in sys.argv[1:] if a != "--open"]
    if len(args) != 1:
        print(__doc__)
        sys.exit(1)
    d = Path(args[0]).expanduser().resolve()
    out, problems = build(d)
    for p in problems:
        print(f"warning: {p}", file=sys.stderr)
    print(out)
    if d.parent.parent == ROOT.resolve():
        build_index(ROOT.resolve())
    if "--open" in sys.argv:
        webbrowser.open(out.as_uri())


if __name__ == "__main__":
    main()
