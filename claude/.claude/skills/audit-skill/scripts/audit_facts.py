#!/usr/bin/env python3
"""Read-only fact gatherer for the audit-skill skill.
(audit-ignore-file: this file defines the risk patterns it scans for)

Subcommands (all print JSON or a table to stdout, never write files):
  list                         skills in ~/.claude/skills, with provenance
  static <skill>               lint facts about one skill directory
  runs <skill> [options]       digest of each past invocation (forked sessions deduplicated)

Run with `python3 -I` so the script dir and cwd are not put on sys.path.
Stdlib only, Python 3.9+.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time
from pathlib import Path

HOME = Path(os.environ.get("AUDIT_HOME", Path.home()))
SKILLS_DIR = HOME / ".claude" / "skills"

PROJECTS_DIR = HOME / ".claude" / "projects"

SECRET_PATTERNS = [
    ("aws-key", re.compile(r"AKIA[0-9A-Z]{16}")),
    ("private-key", re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----")),
    ("slack-token", re.compile(r"xox[abprs]-[A-Za-z0-9-]{10,}")),
    ("github-token", re.compile(r"gh[pousr]_[A-Za-z0-9]{20,}")),
    ("gitlab-token", re.compile(r"glpat-[A-Za-z0-9_-]{10,}")),
    ("bearer", re.compile(r"(?i)bearer\s+[A-Za-z0-9._~+/-]{20,}")),
    ("assigned-secret", re.compile(r"(?i)\b(password|passwd|secret|api[_-]?key|token)\s*[=:]\s*['\"]?[^\s'\"<>$`{(]{8,}")),
]

# (rule, severity, regex). Severity is a hint for the auditor, not a verdict.
RISK_PATTERNS = [
    ("rm-recursive", "high", re.compile(r"\brm\s+-[a-zA-Z]*[rR]")),
    ("git-push", "high", re.compile(r"\bgit\s+push\b")),
    ("force-flag", "high", re.compile(r"--force\b|--no-verify\b|push\s+-f\b")),
    ("remote-write-http", "high", re.compile(r"curl\b[^\n]*(-X\s*(POST|PUT|PATCH|DELETE)|--data|\s-d\s|-F\s)")),
    ("k8s-mutation", "high", re.compile(r"\bkubectl\s+(exec|delete|apply|patch|scale|rollout)\b")),
    ("sql-mutation", "high", re.compile(r"(?i)\b(DROP\s+(TABLE|DATABASE)|DELETE\s+FROM|TRUNCATE\s+TABLE|UPDATE\s+\w+\s+SET)\b")),
    ("host-mr-write", "medium", re.compile(r"\b(glab\s+mr\s+(create|merge|note|update)|gh\s+pr\s+(create|merge|comment|edit))\b")),
    ("host-api-write", "medium", re.compile(r"\b(glab|gh)\s+api\b[^\n]*(-X|--method)\s*(POST|PUT|PATCH|DELETE)")),
    ("pipe-to-shell", "high", re.compile(r"\|\s*(sudo\s+)?(sh|bash|zsh)\b")),
    ("eval", "medium", re.compile(r"\beval\s+[\"'$`]")),
    ("sudo", "high", re.compile(r"\bsudo\b")),
    ("chmod-wide", "medium", re.compile(r"chmod\s+(-R\s+)?(777|a\+rwx)")),
    ("terminal-send", "medium", re.compile(r"\b(rex|tmux)\s+send(-keys)?\b")),
    ("remote-shell", "medium", re.compile(r"\b(ssh|tsh\s+ssh|scp|rsync)\b")),
]
CONFIRM_WORDS = re.compile(r"(?i)\b(confirm|confirmation|ask (the )?user|ask first|approval|approve|draft|dry[- ]run|read-only|never (push|send|post|merge))\b")
HOME_PATH = re.compile(r"/Users/[A-Za-z0-9._-]+|/home/[A-Za-z0-9._-]+")
LINK = re.compile(r"\]\(([^)#\s]+)\)")
TICK_PATH = re.compile(r"`((?:\./)?(?:scripts|references|assets|templates|tests)/[A-Za-z0-9._/-]+)`")
SYSTEMS = {
    "git-host": re.compile(r"\b(glab|gh |gitlab|github)\b", re.I),
    "chat": re.compile(r"\bslack\b", re.I),
    "tracker": re.compile(r"\b(jira|linear|asana)\b", re.I),
    "kubernetes": re.compile(r"\b(kubectl|k8s|kubernetes|pod)\b", re.I),
    "database": re.compile(r"\b(mysql|psql|postgres|mongo|snowflake|sql)\b", re.I),
    "terminal-mux": re.compile(r"\b(rex|tmux)\b", re.I),
    "browser": re.compile(r"\b(browser|screenshot|hammerspoon)\b", re.I),
    "notes": re.compile(r"\b(notes|heramty|sapere|obsidian)\b", re.I),
    "ci": re.compile(r"\b(pipeline|harness|jenkins|github actions)\b", re.I),
}
TEXT_EXT = {".md", ".sh", ".py", ".rb", ".js", ".ts", ".json", ".yml", ".yaml", ".txt", ".toml", ""}
CORRECTION = re.compile(r"(?i)^(no\b|nope|stop\b|wait\b|wrong|don'?t\b|do not\b|why did you|that'?s not|not what|instead\b|actually\b|revert|undo)")
DENIAL = re.compile(r"(?i)(doesn'?t want to proceed|tool use was rejected|user declined|auto mode classifier|blocked by (a )?hook|denied by (the )?(permission|hook))")


def redact(text: str, limit: int = 200) -> str:
    text = text or ""
    for _, rx in SECRET_PATTERNS:
        text = rx.sub("[REDACTED]", text)
    text = text.replace("\n", " ")
    return text[:limit] + ("..." if len(text) > limit else "")


def parse_frontmatter(text: str):
    m = re.match(r"^---\n(.*?)\n---\n", text, re.S)
    if not m:
        return None, text
    fm = {}
    key = None
    for line in m.group(1).split("\n"):
        kv = re.match(r"^([A-Za-z_-]+):\s*(.*)$", line)
        if kv:
            key = kv.group(1)
            fm[key] = kv.group(2).strip()
        elif key and line.startswith((" ", "\t")):
            fm[key] += " " + line.strip()
    return fm, text[m.end():]


def resolve_skill(arg: str) -> Path:
    p = Path(arg).expanduser()
    if p.is_dir():
        return p
    cand = SKILLS_DIR / arg
    if cand.is_dir():
        return cand
    raise SystemExit(f"skill not found: {arg}")


def provenance(path: Path) -> str:
    if path.is_symlink():
        target = os.path.realpath(path)
        return "symlink:tracked" if "/dotfiles/" in target else "symlink:external"
    return "local-only"


def cmd_list(_args) -> int:
    for d in sorted(SKILLS_DIR.iterdir()) if SKILLS_DIR.is_dir() else []:
        if d.name.startswith(".") or not (d / "SKILL.md").is_file():
            continue
        fm, _ = parse_frontmatter((d / "SKILL.md").read_text(errors="replace"))
        desc = (fm or {}).get("description", "(no frontmatter)")
        print(f"{d.name:32} {provenance(d):17} {desc[:80]}")
    return 0


def iter_text_files(root: Path):
    for p in sorted(root.rglob("*")):
        if p.is_file() and not any(part.startswith(".") for part in p.relative_to(root).parts) \
                and p.suffix in TEXT_EXT and p.stat().st_size < 1_000_000:
            yield p


def cmd_static(args) -> int:
    root = resolve_skill(args.skill)
    skill_md = root / "SKILL.md"
    out = {"skill": root.name, "path": str(root), "provenance": provenance(root), "findings": []}
    add = lambda rule, sev, file, line, text="": out["findings"].append(
        {"rule": rule, "severity": sev, "file": file, "line": line, "text": redact(text, 160)})

    if not skill_md.is_file():
        add("no-skill-md", "high", "SKILL.md", 0)
        print(json.dumps(out, indent=2))
        return 0
    body = skill_md.read_text(errors="replace")
    fm, content = parse_frontmatter(body)
    out["skill_md"] = {"lines": body.count("\n") + 1, "words": len(body.split())}
    if fm is None:
        add("no-frontmatter", "high", "SKILL.md", 1)
    else:
        desc = fm.get("description", "")
        out["description_chars"] = len(desc)
        if fm.get("name") != root.name:
            add("name-mismatch", "medium", "SKILL.md", 2, f"name={fm.get('name')!r} dir={root.name!r}")
        if not desc:
            add("no-description", "high", "SKILL.md", 2)
        elif not re.search(r"(?i)\buse (when|whenever|for|this|if)\b|\btrigger", desc):
            add("description-no-trigger", "medium", "SKILL.md", 2, "description does not say when to use it")
        if len(desc) > 1024:
            add("description-long", "low", "SKILL.md", 2, f"{len(desc)} chars, loaded into every session")

    files = list(iter_text_files(root))
    out["files"] = [str(p.relative_to(root)) for p in files]
    all_text = ""
    referenced = set()
    for p in files:
        rel = str(p.relative_to(root))
        text = p.read_text(errors="replace")
        all_text += text + "\n"
        skip_scan = rel.startswith("tests/") or "audit-ignore-file" in "\n".join(text.split("\n")[:5])
        for i, line in enumerate(text.split("\n"), 1):
            if skip_scan:
                break
            for name, rx in SECRET_PATTERNS:
                if rx.search(line):
                    add("secret:" + name, "critical", rel, i, line)
            for rule, sev, rx in RISK_PATTERNS:
                if rx.search(line):
                    add("risk:" + rule, sev, rel, i, line)
            if HOME_PATH.search(line):
                add("hardcoded-home-path", "low", rel, i, line)
        if p.suffix == ".md":
            for m in LINK.finditer(text):
                referenced.add(m.group(1))
            for m in TICK_PATH.finditer(text):
                referenced.add(m.group(1))
        if (p.suffix in {".sh", ".py"} or text.startswith("#!")) and not rel.startswith("tests/"):
            if not text.startswith("#!"):
                add("script-no-shebang", "low", rel, 1)
            if p.suffix == ".sh" and not re.search(r"set -[a-z]*e[a-z]*u?|set -o errexit", text):
                add("shell-no-errexit", "medium", rel, 1)
            if not os.access(p, os.X_OK):
                add("script-not-executable", "low", rel, 1)

    for ref in sorted(referenced):
        if re.match(r"^[a-z]+://", ref) or ref.startswith(("/", "~", "mailto:")):
            continue
        if not (root / ref.lstrip("./")).exists():
            add("missing-referenced-file", "medium", "SKILL.md", 0, ref)
    ref_names = {os.path.normpath(r.lstrip("./")) for r in referenced}
    md_text = "\n".join(p.read_text(errors="replace") for p in files if p.suffix == ".md")
    for rel in out["files"]:
        if rel != "SKILL.md" and rel not in ref_names and not rel.startswith("tests/") and rel not in md_text:
            add("orphan-file", "low", rel, 0, "bundled but never referenced from markdown")

    risky = [f for f in out["findings"] if f["rule"].startswith("risk:")]
    out["mutations"] = {"count": len(risky), "confirmation_language_present": bool(CONFIRM_WORDS.search(all_text))}
    out["systems_touched"] = sorted(n for n, rx in SYSTEMS.items() if rx.search(all_text))
    print(json.dumps(out, indent=2))
    return 0


def run_files(since_days, project_sub, include_subagents):
    cutoff = time.time() - since_days * 86400 if since_days else 0
    if not PROJECTS_DIR.is_dir():
        return
    for proj in sorted(PROJECTS_DIR.iterdir()):
        if project_sub and project_sub not in proj.name:
            continue
        pattern = "**/*.jsonl" if include_subagents else "*.jsonl"
        for f in proj.glob(pattern):
            if f.stat().st_mtime >= cutoff:
                yield proj.name, f


def text_of(content):
    if isinstance(content, str):
        return content
    return "".join(b.get("text", "") for b in content or [] if isinstance(b, dict) and b.get("type") == "text")


def load_events(f):
    events = []
    with f.open(errors="replace") as fh:
        for line in fh:
            try:
                events.append(json.loads(line))
            except ValueError:
                continue
    return events


def is_typed_prompt(d):
    c = (d.get("message") or {}).get("content")
    return d.get("type") == "user" and isinstance(c, str) and not d.get("isMeta") and not c.lstrip().startswith("<")


def find_starts(events, skill):
    """(index, how, invocation_id) for every invocation of the skill in a transcript."""
    starts = []
    for i, d in enumerate(events):
        content = (d.get("message") or {}).get("content")
        if d.get("type") == "assistant" and isinstance(content, list):
            for b in content:
                if b.get("type") == "tool_use" and b.get("name") == "Skill" \
                        and (b.get("input") or {}).get("skill", "").split(":")[-1] == skill:
                    starts.append((i, "tool", b.get("id") or d.get("uuid")))
        elif d.get("type") == "user" and isinstance(content, str) and f"<command-name>/{skill}</command-name>" in content:
            starts.append((i, "slash", d.get("uuid")))
    return starts


def digest_one(proj, f, events, skill, start, how, inv_id, end_limit, user_turns, max_events):
    """Window = invocation until the next invocation, the (user_turns+1)-th typed prompt, max_events or end."""
    stop, ended_by = min(len(events), start + max_events), "max_events" if len(events) > start + max_events else "end_of_session"
    if end_limit is not None and end_limit < stop:
        stop, ended_by = end_limit, "next_invocation"
    typed = 0
    for i in range(start + 1, stop):
        if is_typed_prompt(events[i]):
            typed += 1
            if typed > user_turns:
                stop, ended_by = i, "user_turns"
                break
    window = events[start:stop]
    ts = [d.get("timestamp") for d in window if d.get("timestamp")]
    run = {
        "session": f.stem, "project": proj, "file": str(f), "invocation_id": inv_id, "invoked_via": how,
        "started": ts[0] if ts else None, "ended": ts[-1] if ts else None,
        "branch": window[0].get("gitBranch"), "events": len(window), "window_ended_by": ended_by,
        "tools": {}, "segments": [], "bash": [], "errors": [], "denials": [],
        "user_messages": [], "repeated_commands": [], "other_skills": [],
    }
    seg = {"after_user_message": None, "tools": {}}
    seen = {}
    for j, d in enumerate(window):
        content = (d.get("message") or {}).get("content")
        if d.get("type") == "assistant" and isinstance(content, list):
            for b in content:
                if b.get("type") != "tool_use":
                    continue
                name = b.get("name", "?")
                run["tools"][name] = run["tools"].get(name, 0) + 1
                seg["tools"][name] = seg["tools"].get(name, 0) + 1
                inp = b.get("input") or {}
                if name == "Skill" and inp.get("skill", "").split(":")[-1] != skill:
                    run["other_skills"].append(inp.get("skill"))
                if name == "Bash":
                    cmd = redact(inp.get("command", ""), 160)
                    run["bash"].append(cmd)
                    seen[cmd] = seen.get(cmd, 0) + 1
        elif d.get("type") == "user":
            if isinstance(content, list):
                for b in content:
                    if b.get("type") != "tool_result" or not b.get("is_error"):
                        continue
                    raw = b.get("content")
                    msg = raw if isinstance(raw, str) else text_of(raw)
                    (run["denials"] if DENIAL.search(msg or "") else run["errors"]).append(redact(msg, 160))
            elif j > 0 and is_typed_prompt(d):
                run["segments"].append(seg)
                text = redact(content, 200)
                run["user_messages"].append({"text": text, "looks_like_correction": bool(CORRECTION.match(content.strip()))})
                seg = {"after_user_message": text[:60], "tools": {}}
    run["segments"].append(seg)
    run["repeated_commands"] = [{"cmd": c, "times": n} for c, n in seen.items() if n > 1]
    run["bash"] = run["bash"][:40]
    run["errors"] = run["errors"][:20]
    return run


def digest(proj, f, skill, max_events, user_turns=2):
    events = load_events(f)
    starts = find_starts(events, skill)
    runs = []
    for k, (i, how, inv) in enumerate(starts):
        nxt = starts[k + 1][0] if k + 1 < len(starts) else None
        runs.append(digest_one(proj, f, events, skill, i, how, inv, nxt, user_turns, max_events))
    return runs


def cmd_runs(args) -> int:
    needles = (f'"skill":"{args.skill}"', f'"skill": "{args.skill}"', f"<command-name>/{args.skill}</command-name>")
    hits = []
    for proj, f in run_files(args.since, args.project, args.subagents):
        if args.session and args.session not in f.name:
            continue
        try:
            raw = f.read_bytes().decode(errors="replace")
        except OSError:
            continue
        if any(n in raw for n in needles):
            hits.append((f.stat().st_mtime, proj, f))
    hits.sort(reverse=True)
    runs, by_inv = [], {}
    for _, proj, f in hits:
        for r in digest(proj, f, args.skill, args.max_events, args.user_turns):
            key = r["invocation_id"]
            if key and key in by_inv:
                by_inv[key].setdefault("also_in_sessions", []).append(r["session"])
                continue
            if key:
                by_inv[key] = r
            runs.append(r)
    runs.sort(key=lambda r: r["started"] or "", reverse=True)
    print(json.dumps({"skill": args.skill, "sessions_scanned_with_hits": len(hits),
                      "invocations_found": len(runs), "runs": runs[:args.limit]}, indent=2))
    return 0


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("list").set_defaults(fn=cmd_list)
    s = sub.add_parser("static")
    s.add_argument("skill")
    s.set_defaults(fn=cmd_static)
    r = sub.add_parser("runs")
    r.add_argument("skill")
    r.add_argument("--since", type=int, default=60, help="only files modified in the last N days (0 = all)")
    r.add_argument("--project", help="substring of the encoded project dir name")
    r.add_argument("--session", help="substring of the session file name")
    r.add_argument("--limit", type=int, default=5)
    r.add_argument("--max-events", type=int, default=400)
    r.add_argument("--user-turns", type=int, default=2,
                   help="window ends at the (N+1)-th typed user prompt after the invocation")
    r.add_argument("--subagents", action="store_true", help="also scan subagent transcripts")
    r.set_defaults(fn=cmd_runs)
    args = ap.parse_args(argv)
    return args.fn(args)


if __name__ == "__main__":
    sys.exit(main())
