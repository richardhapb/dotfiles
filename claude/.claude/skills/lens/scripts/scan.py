#!/usr/bin/env python3
"""lens scanner: static facts about a change or a piece of code, so the model does not have to discover them.

  scan.py [--repo DIR] [--base REF] [--no-fetch]            the local branch vs the default branch
  scan.py --mr URL_OR_IID [--project GROUP/PROJECT]         a GitLab MR (needs glab)
  scan.py --paths PATH [PATH ...] [--name NAME]             how existing code works: the files under PATH at HEAD
          [--out DIR] [--budget N] [--max-hits N] [--services FILE]

Writes DIR/scan.json (everything) and DIR/hunks.txt (budgeted, filtered source) and prints a compact digest.
Without --out the directory is <root>/<change|flow>/<slug>--<ref>. Pure stdlib, read-only against the repo.
"""
import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path
from urllib.parse import quote

ROOT = Path(os.environ.get("LENS_ROOT", Path.home() / "lens"))
DEFAULT_BUDGET = 1500
DEFAULT_MAX_HITS = 120
MAX_PATH_FILES = 400
CONTEXT_CAP_TOTAL, CONTEXT_CAP_FILE = 30, 8
TEXT_MAX = 140


def die(msg):
    print(f"error: {msg}", file=sys.stderr)
    sys.exit(2)


def run(cmd, cwd=None, env=None, check=True):
    p = subprocess.run(cmd, cwd=cwd, env=env, capture_output=True, text=True, errors="replace")
    if check and p.returncode != 0:
        raise RuntimeError(f"{' '.join(cmd[:4])}: {p.stderr.strip()[:300]}")
    return p.stdout


def slugify(s):
    return re.sub(r"[^a-z0-9]+", "-", s.lower()).strip("-")


# ---------------------------------------------------------------- diff parsing

HUNK = re.compile(r"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@")
ANSI = re.compile(r"\x1b\[[0-9;]*m")


def parse_diff(text):
    """Unified diff -> [{path, status, added, removed, binary, hunks:[{header, lines:[(kind, old, new, text)]}]}]."""
    files, cur, hunk = [], None, None
    old_left = new_left = 0
    old_no = new_no = 0
    for raw in ANSI.sub("", text).split("\n"):
        if hunk is not None and (old_left > 0 or new_left > 0):
            kind = raw[:1]
            body = raw[1:]
            if kind == "+":
                hunk["lines"].append(("+", None, new_no, body))
                new_no += 1
                new_left -= 1
                cur["added"] += 1
            elif kind == "-":
                hunk["lines"].append(("-", old_no, None, body))
                old_no += 1
                old_left -= 1
                cur["removed"] += 1
            elif kind == "\\":
                pass
            else:
                hunk["lines"].append((" ", old_no, new_no, body))
                old_no += 1
                new_no += 1
                old_left -= 1
                new_left -= 1
            continue
        hunk = None
        if raw.startswith("diff --git "):
            m = re.match(r"diff --git a/(.*?) b/(.*)$", raw)
            cur = {"path": m.group(2) if m else raw[11:], "old_path": m.group(1) if m else None,
                   "status": "M", "added": 0, "removed": 0, "binary": False, "hunks": []}
            files.append(cur)
        elif cur is None:
            continue
        elif raw.startswith("new file mode"):
            cur["status"] = "A"
        elif raw.startswith("deleted file mode"):
            cur["status"] = "D"
        elif raw.startswith("rename from "):
            cur["status"] = "R"
        elif raw.startswith("Binary files") or raw.startswith("GIT binary patch"):
            cur["binary"] = True
        elif raw.startswith("+++ "):
            p = raw[4:].strip()
            if p != "/dev/null" and p.startswith("b/"):
                cur["path"] = p[2:]
        elif raw.startswith("--- "):
            p = raw[4:].strip()
            if p.startswith("a/"):
                cur["old_path"] = p[2:]
        else:
            m = HUNK.match(raw)
            if m:
                old_no, new_no = int(m.group(1)), int(m.group(3))
                old_left = int(m.group(2)) if m.group(2) is not None else 1
                new_left = int(m.group(4)) if m.group(4) is not None else 1
                hunk = {"header": raw, "lines": []}
                cur["hunks"].append(hunk)
    return files


# ---------------------------------------------------------------- classification

NOISE = re.compile(
    r"(^|/)(package-lock\.json|yarn\.lock|pnpm-lock\.yaml|Gemfile\.lock|go\.sum|poetry\.lock|Cargo\.lock|composer\.lock|Pipfile\.lock"
    r"|schema\.rb|structure\.sql)$"
    r"|\.(pb\.go|min\.js|min\.css|map|snap|svg|png|jpe?g|gif|ico|pdf|woff2?|ttf|lock)$"
    r"|_pb\.rb$|_pb2\.py$|\.generated\.\w+$"
    r"|(^|/)(vendor|node_modules|dist|build|generated|__snapshots__|coverage)/"
)
TEST = re.compile(r"(^|/)(spec|specs|test|tests|__tests__|e2e|cypress)/|_test\.go$|_spec\.rb$|\.(spec|test)\.[jt]sx?$|(^|/)test_[^/]*\.py$|_test\.py$")
MIGRATION = re.compile(r"(^|/)db/migrate/|(^|/)migrations?/")
DOC = re.compile(r"\.(md|rst|txt|adoc)$|(^|/)docs?/", re.I)


def category(path):
    if NOISE.search(path):
        return "noise"
    if TEST.search(path):
        return "test"
    if MIGRATION.search(path):
        return "migration"
    if DOC.search(path):
        return "doc"
    return "code"


RB = r"\.(rb|rake|ru|erb)$|(^|/)(Rakefile|Gemfile)$"
GO = r"\.go$"
JS = r"\.(js|jsx|ts|tsx|mjs|cjs)$"
PY = r"\.py$"
PROTO = r"\.proto$"
SQLF = r"\.sql$"
ROUTES = r"(^|/)routes[^/]*\.rb$|(^|/)config/routes/"
MIGR = r"(^|/)db/migrate/"

PATTERNS = []


def pat(channel, direction, rx, target=None, files=None, flags=0, need_target=False):
    PATTERNS.append({
        "channel": channel, "direction": direction, "rx": re.compile(rx, flags),
        "target": re.compile(target) if target else None,
        "files": re.compile(files) if files else None, "need_target": need_target,
    })


STR = r"""['"`]([^'"`\s]{2,80})['"`]"""
ENVNAME = r"[A-Z][A-Z0-9_]*(?:URL|URI|HOST|ENDPOINT|BASE|ADDR(?:ESS)?)[A-Z0-9_]*"

# http, outbound
pat("http", "out", r"\b(Faraday|HTTParty|RestClient|Typhoeus|Excon|Net::HTTP|HTTPX)\b\s*[.:(]", target=r"(https?://[^\s'\"`)>,]+)", files=RB)
pat("http", "out", r"\bhttp\.(Get|Post|PostForm|Head|NewRequest|NewRequestWithContext)\(|\bresty\.New\(|\bhttp\.Client\b", target=r"(https?://[^\s'\"`)>,]+)", files=GO)
pat("http", "out", r"(?<![\w.])(fetch|axios|got|ky)\s*(\(|\.(get|post|put|patch|delete|request|create)\b)|\$http\.|superagent", target=r"(https?://[^\s'\"`)>,]+)", files=JS)
pat("http", "out", r"\b(requests|httpx|aiohttp)\.(get|post|put|patch|delete|request|Session|Client|AsyncClient|ClientSession)\b", target=r"(https?://[^\s'\"`)>,]+)", files=PY)
# a service address: env var holding a URL or host, or a URL literal
pat("endpoint", "out", r"\bENV\b|environ|[Gg]etenv|LookupEnv|process\.env", target=r"(?:['\"]|process\.env\.)(" + ENVNAME + r")", need_target=True)
pat("endpoint", "out", r"https?://[A-Za-z0-9_.-]+(?::\d+)?", target=r"(https?://[A-Za-z0-9_.-]+(?::\d+)?)", need_target=True)
# http, inbound
pat("http", "in", r"^\s*(get|post|put|patch|delete|resources?|namespace|match|mount|scope)\b", target=r"""['":/]([\w/:.\-]{2,})""", files=ROUTES)
pat("http", "in", r"\bclass\s+\w+Controller\b", target=r"class\s+(\w+Controller)", files=RB)
pat("http", "in", r"\.(GET|POST|PUT|PATCH|DELETE|Handle|HandleFunc|Any)\(\s*\"", target=STR, files=GO)
pat("http", "in", r"\b(app|router|server|fastify)\.(get|post|put|patch|delete|all|use)\(\s*['\"`]", target=STR, files=JS)
pat("http", "in", r"@\s*(app|router|bp|blueprint|api)\.(get|post|put|patch|delete|route)\(", target=STR, files=PY)
# grpc
pat("grpc", "def", r"^\s*(service|rpc)\s+\w+", target=r"(?:service|rpc)\s+(\w+)", files=PROTO)
pat("grpc", "out", r"\bgrpc\.(Dial|NewClient|DialContext|insecure_channel|secure_channel)\b|\bpb\.New\w+Client\b|\bGRPC::|\w+::Stub\b", target=r"(\w+Client|\w+::Stub)")
pat("grpc", "in", r"\bRegister\w+Server\(|<\s*\w*::Service\b")
# kafka
pat("kafka", "in", r"\b(Karafka::BaseConsumer|Racecar::Consumer|KafkaConsumer|consumer_group|consume_each|each_message|consumer\.subscribe|kafka\.NewReader|kgo\.ConsumeTopics)\b", target=r"""\btopics?\s*(?:[:=]|=>|\()\s*\[?\s*['":]?([A-Za-z0-9_.\-]{3,})""")
pat("kafka", "out", r"\b(WaterDrop|DeliveryBoy|deliver_message|produce_sync|produce_async|KafkaProducer|producer\.send|kafka\.NewWriter|sarama\.NewSyncProducer)\b|\bKarafka\.producer\b|\.produce\(", target=r"""\btopic(?:_name)?\s*(?:[:=]|=>|\()\s*['":]?([A-Za-z0-9_.\-]{3,})""")
pat("kafka", "ref", r"\b(Phobos|ruby-kafka|Kafka\.new|confluent_kafka|kafkajs|franz-go)\b")
# temporal
pat("temporal", "def", r"@workflow\.defn|@activity\.defn|<\s*Temporalio::(Workflow|Activity)\b|RegisterWorkflow(WithOptions)?\(|RegisterActivity(WithOptions)?\(|include Temporalio", target=r"(?:class\s+|Register\w+\()(\w+)")
pat("temporal", "orch", r"\b(execute_activity|ExecuteActivity|ExecuteChildWorkflow|start_child_workflow|execute_child_workflow)\w*|\b(proxyActivities|wait_condition|GetSignalChannel|NewTimer|defineSignal)\b|\bworkflow\.(sleep|Sleep)\b|\bWorkflow\.(sleep|execute_activity|signal)\b", target=r"(?:ExecuteActivity|ExecuteChildWorkflow|execute_activity|start_child_workflow)\w*\(\s*\w+\s*,\s*([\w.]+)")
pat("temporal", "out", r"\b(start_workflow|signal_workflow|signal_with_start|execute_workflow|ExecuteWorkflow|SignalWorkflow|SignalWithStartWorkflow|QueryWorkflow|CancelWorkflow|TerminateWorkflow)\w*|\bTemporalio::Client\b", target=r"""(?:workflow|Workflow)\W+([A-Z]\w+)""")
pat("temporal", "ref", r"\btask_queue\b|\bTaskQueue\b", target=r"""(?:task_queue|TaskQueue)['"]?\s*(?:[:=]|=>)\s*['"]([\w.\-]+)""", need_target=True)
# sql / schema
pat("sql", "schema", r"\b(create_table|drop_table|add_column|remove_column|rename_column|change_column|add_index|remove_index|add_reference|change_table|rename_table)\b", target=r"""\(?\s*:?['"]?(\w+)""", files=MIGR)
pat("sql", "rw", r"\b(INSERT\s+INTO|UPDATE\s+\w+\s+SET|DELETE\s+FROM|ALTER\s+TABLE|CREATE\s+TABLE|DROP\s+TABLE|SELECT\b.*\bFROM)\b", target=r"(?:INTO|UPDATE|FROM|TABLE(?:\s+IF\s+NOT\s+EXISTS)?)\s+[`\"]?([A-Za-z_][\w.]*)")
pat("sql", "rw", r"\b(update_all|delete_all|insert_all|upsert_all|find_by_sql|exec_query)\b|connection\.execute|self\.table_name\s*=", target=r"""table_name\s*=\s*['"](\w+)""")
pat("sql", "rw", r"\b(sqlx|gorm|pgx)\b|sql\.Open\(|\bdb\.(Exec|Query|QueryRow|Get|Select)(Context)?\(", files=GO)
pat("sql", "rw", r"\b(cursor\.execute|engine\.execute|session\.(execute|query|commit))\b", files=PY)
# other stores and queues
pat("nosql", "rw", r"\b(Mongoid::Document|include Mongoid|Mongo::Client|MongoClient|mongoose\.)|mongo\.Connect\(")
pat("redis", "rw", r"\b(Redis\.(new|current)|RedisClient|go-redis|ioredis)\b|\bredis\.(get|set|hset|hget|lpush|rpush|incr|expire|del|setex|publish|subscribe|xadd)\b|Rails\.cache\.")
pat("queue", "out", r"\b(\w+)\.perform_(async|in|at|later)\b|\.delay\(|apply_async|Resque\.enqueue|Aws::SQS|\bSQS\b", target=r"(\w+)\.perform_")
pat("queue", "in", r"include Sidekiq::(Worker|Job)|<\s*ApplicationJob\b|sidekiq_options", target=r"class\s+(\w+)")
pat("blob", "rw", r"\b(Aws::S3|S3Client|ActiveStorage|Google::Cloud::Storage)\b|boto3\.client\(['\"]s3|@aws-sdk/client-s3")
# webhooks and signatures
pat("webhook", "ref", r"webhook", flags=re.I)
pat("webhook", "in", r"OpenSSL::HMAC|hmac\.New\(|createHmac|X-[A-Za-z-]*Signature", flags=re.I)
# feature flags
pat("flag", "read", r"\b(Split\.\w+|split_client|SplitClient|treatments?\(|getTreatments?\(|useSplit\w*|useTreatments?\b|splitio|Flipper\.(enabled\?|enable|disable)|FeatureFlag\w*|feature_flag\w*|feature_enabled\?|flag_enabled\?|LaunchDarkly|ld_client|variation\(|HarnessFeatureFlags?|Harness::\w+)", target=STR)
pat("flag", "def", r"^\s*(export\s+)?(const\s+|let\s+)?[A-Z][A-Z0-9_]{3,}\s*=?\s*$|^\s*(export\s+)?(const\s+|let\s+)?[A-Z][A-Z0-9_]{3,}\s*=\s*['\"]", target=STR, files=r"(?i)flags?[^/]*\.(ts|tsx|js|rb|go|py)$|(^|/)flags?/")

SIGNALS = [
    ("metric", re.compile(r"\b(statsd|dogstatsd|ddstats|metrics?)\b.*\b(increment|incr|decrement|gauge|timing|histogram|distribution|count|observe|measure)\b", re.I), re.compile(STR)),
    ("trace", re.compile(r"\b(Datadog\.tracer|Datadog::Tracing\.trace|tracer\.trace|tracer\.Start|StartSpan|span\.set_tag|opentelemetry)\b"), re.compile(STR)),
    ("log", re.compile(r"\b(logger|log|Rails\.logger|slog|zap|logrus|console)\b[.:]\s*(error|warn|warning|fatal|critical|Error|Warn|Errorf|Warnf)\b"), re.compile(STR)),
    ("error", re.compile(r"\braise\s+[A-Z]|\brescue\s+[A-Z]|\bthrow new \w+|errors\.New\(|fmt\.Errorf\(|class \w+(Error|Exception)\b"), re.compile(r"(?:raise|rescue|throw new)\s+([A-Z][\w:]*)|class\s+(\w+(?:Error|Exception))")),
    ("timeout", re.compile(r"\b\w*(retr(y|ies)|timeout|backoff|deadline|ttl|expires_in|rate_limit|circuit)\w*\b\s*(?:[:=]|=>|\()\s*[\w.:\-]+", re.I), re.compile(r"(\b\w*(?:retr(?:y|ies)|timeout|backoff|deadline|ttl|expires_in|rate_limit|circuit)\w*\b\s*(?:[:=]|=>|\()\s*[\w.:\-]+)", re.I)),
]

IGNORED_URL = re.compile(r"(json-schema\.org|w3\.org|schema\.org|xmlns|purl\.org|example\.(com|org)|apache\.org/licenses|opensource\.org)")
COMMENT = re.compile(r"^\s*(#(?!\{)|//|/\*|\*|--|<!--)")


def clip(s):
    s = s.strip()
    return s if len(s) <= TEXT_MAX else s[: TEXT_MAX - 1] + "…"


def match_line(path, text):
    """-> [(channel, direction, target)] for one source line."""
    if not text.strip() or COMMENT.match(text):
        return []
    out, seen = [], set()
    for p in PATTERNS:
        if p["files"] and not p["files"].search(path):
            continue
        m = p["rx"].search(text)
        if not m:
            continue
        target = None
        if p["target"]:
            tm = p["target"].search(text)
            if tm:
                target = next((g for g in tm.groups() if g), None)
        if p["need_target"] and not target:
            continue
        if p["channel"] == "endpoint" and target and IGNORED_URL.search(target):
            continue
        if (p["channel"], p["direction"]) in seen:
            continue
        seen.add((p["channel"], p["direction"]))
        out.append((p["channel"], p["direction"], target))
    return out


def match_signal(text):
    if COMMENT.match(text):
        return []
    out = []
    for kind, rx, trg in SIGNALS:
        if rx.search(text):
            tm = trg.search(text)
            name = next((g for g in tm.groups() if g), None) if tm else None
            out.append((kind, name))
    return out


# ---------------------------------------------------------------- services

class Services:
    """Optional name map, so a target resolves to a service name instead of staying a raw host or env var.

    {"services": {"Orders API": {"hosts": ["orders"], "env": ["ORDERS_URL"], "ports": [8080]}}}
    Looked up in --services, $LENS_SERVICES, then <repo>/.lens/services.json. Without one nothing resolves.
    """

    LOCAL = ("localhost", "127.0.0.1", "0.0.0.0")

    def __init__(self, path=None, repo_dir=None):
        self.path, self.hosts, self.envs, self.ports = None, {}, {}, {}
        repo_map = Path(repo_dir) / ".lens" / "services.json" if repo_dir else None
        for cand in [path, os.environ.get("LENS_SERVICES"), repo_map]:
            if cand and Path(cand).expanduser().is_file():
                self.path = str(Path(cand).expanduser())
                break
        if not self.path:
            return
        for name, spec in (json.loads(Path(self.path).read_text()).get("services") or {}).items():
            for h in spec.get("hosts", []):
                self.hosts[h.lower()] = name
            for e in spec.get("env", []):
                self.envs[e] = name
            for port in spec.get("ports", []):
                self.ports[int(port)] = name

    def resolve_env(self, var):
        return [self.envs[var]] if var in self.envs else []

    def resolve_url(self, url):
        m = re.search(r"(?:https?://)?([A-Za-z0-9_.-]+)(?::(\d+))?", url or "")
        if not m:
            return []
        host, port = m.group(1).lower(), m.group(2)
        if port and host in self.LOCAL:
            return [self.ports[int(port)]] if int(port) in self.ports else []
        first = re.sub(r"-(staging|stg|prod|production|sandbox|dev|eu|us)$", "", host.split(".")[0])
        return [self.hosts[first]] if first in self.hosts else []


# ---------------------------------------------------------------- repo + sources

def parse_remote(url):
    url = url.strip()
    m = re.match(r"git@([^:]+):(.+?)(?:\.git)?$", url) or re.match(r"https?://(?:[^@/]+@)?([^/]+)/(.+?)(?:\.git)?/?$", url)
    if not m:
        return None, None, None
    host, project = m.group(1), m.group(2)
    return host, project, ("github" if "github" in host else "gitlab")


def permalink(repo, path, line):
    if not repo.get("host") or not repo.get("project") or not repo.get("head_sha") or not repo.get("linkable"):
        return None
    base = f"https://{repo['host']}/{repo['project']}"
    mid = "/blob/" if repo["kind"] == "github" else "/-/blob/"
    return f"{base}{mid}{repo['head_sha']}/{quote(path)}" + (f"#L{line}" if line else "")


def is_pushed(repo_dir, sha):
    try:
        return bool(run(["git", "branch", "-r", "--contains", sha], cwd=repo_dir).strip())
    except RuntimeError:
        return False


def default_branch(repo_dir):
    try:
        return run(["git", "symbolic-ref", "--short", "refs/remotes/origin/HEAD"], cwd=repo_dir).strip()
    except RuntimeError:
        for b in ("origin/master", "origin/main"):
            if run(["git", "rev-parse", "--verify", "--quiet", b], cwd=repo_dir, check=False).strip():
                return b
    die("cannot find the default branch (pass --base)")


def local_input(args):
    repo_dir = run(["git", "rev-parse", "--show-toplevel"], cwd=args.repo or ".").strip()
    base = args.base or default_branch(repo_dir)
    warnings = []
    if not args.no_fetch and base.startswith("origin/"):
        try:
            run(["git", "fetch", "origin", base.split("/", 1)[1], "--quiet"], cwd=repo_dir)
        except RuntimeError as e:
            warnings.append(f"fetch failed, base may be stale: {e}")
    head = run(["git", "rev-parse", "HEAD"], cwd=repo_dir).strip()
    mb = run(["git", "merge-base", base, "HEAD"], cwd=repo_dir).strip()
    diff = run(["git", "diff", "-U3", "--no-color", "--no-ext-diff", "--find-renames", mb, head], cwd=repo_dir)
    branch = run(["git", "rev-parse", "--abbrev-ref", "HEAD"], cwd=repo_dir).strip()
    remote = run(["git", "remote", "get-url", "origin"], cwd=repo_dir, check=False).strip()
    host, project, kind = parse_remote(remote)
    dirty = bool(run(["git", "status", "--porcelain", "-uno"], cwd=repo_dir).strip())
    if dirty:
        warnings.append("uncommitted changes are NOT in this scan (scanned commits only)")
    pushed = is_pushed(repo_dir, head)
    repo = {"dir": repo_dir, "name": Path(repo_dir).name, "remote": remote, "host": host, "project": project, "kind": kind,
            "head_sha": head, "base_sha": mb, "base": base, "branch": branch, "pushed": pushed, "linkable": pushed, "dirty": dirty}
    return repo, diff, None, warnings


def paths_input(args):
    repo_dir = run(["git", "rev-parse", "--show-toplevel"], cwd=args.repo or ".").strip()
    head = run(["git", "rev-parse", "HEAD"], cwd=repo_dir).strip()
    branch = run(["git", "rev-parse", "--abbrev-ref", "HEAD"], cwd=repo_dir).strip()
    remote = run(["git", "remote", "get-url", "origin"], cwd=repo_dir, check=False).strip()
    host, project, kind = parse_remote(remote)
    warnings = []
    listed = run(["git", "ls-tree", "-r", "--name-only", head, "--", *args.paths], cwd=repo_dir).split("\n")
    names = [n for n in listed if n and category(n) != "noise"]
    if not names:
        die("no tracked files under those paths at HEAD")
    if len(names) > MAX_PATH_FILES:
        warnings.append(f"{len(names)} files under those paths: only the first {MAX_PATH_FILES} were read, narrow the paths")
        names = names[:MAX_PATH_FILES]
    if run(["git", "status", "--porcelain", "-uno", "--", *args.paths], cwd=repo_dir).strip():
        warnings.append("uncommitted changes under those paths are NOT in this scan (read from HEAD)")
    repo = {"dir": repo_dir, "name": Path(repo_dir).name, "remote": remote, "host": host, "project": project, "kind": kind,
            "head_sha": head, "base_sha": None, "base": None, "branch": branch, "pushed": is_pushed(repo_dir, head), "dirty": False}
    repo["linkable"] = repo["pushed"]
    source, parts = Source(repo), []
    for n in names:
        body = source.read(n)
        if body and body[-1] == "":
            body = body[:-1]
        if not body or any("\x00" in ln for ln in body):
            continue
        parts.append(f"diff --git a/{n} b/{n}\nnew file mode 100644\n--- /dev/null\n+++ b/{n}\n@@ -0,0 +1,{len(body)} @@\n" + "\n".join("+" + ln for ln in body))
    return repo, "\n".join(parts) + "\n", None, warnings


def mr_input(args):
    ref = args.mr
    m = re.match(r"https?://([^/]+)/(.+?)/-/merge_requests/(\d+)", ref)
    env = dict(os.environ)
    if m:
        host, project, iid = m.group(1), m.group(2), m.group(3)
        env["GITLAB_HOST"] = host
    elif ref.isdigit():
        iid, project, host = ref, args.project, None
        if not project:
            remote = run(["git", "remote", "get-url", "origin"], cwd=args.repo or ".").strip()
            host, project, _ = parse_remote(remote)
            if not project:
                die("cannot tell the project; pass --project GROUP/PROJECT or a full MR URL")
    else:
        die("--mr takes an MR URL or an iid")
    if host is None:
        remote = run(["git", "remote", "get-url", "origin"], cwd=args.repo or ".", check=False).strip()
        host = parse_remote(remote)[0]
    info = json.loads(run(["glab", "api", f"projects/{quote(project, safe='')}/merge_requests/{iid}"], env=env))
    diff = run(["glab", "mr", "diff", iid, "--raw", "--color=never", "-R", project], env=env)
    head = info.get("sha") or (info.get("diff_refs") or {}).get("head_sha") or ""
    repo = {"dir": None, "name": project.split("/")[-1], "remote": f"https://{host}/{project}", "host": host, "project": project,
            "kind": "gitlab", "head_sha": head, "base_sha": (info.get("diff_refs") or {}).get("base_sha"), "base": info.get("target_branch"),
            "branch": info.get("source_branch"), "pushed": True, "linkable": bool(head), "dirty": False}
    # a local clone makes whole-file reads and caller search possible, but only if it already has the head commit
    cand = Path(args.repo or ".").expanduser()
    if head and subprocess.run(["git", "cat-file", "-e", f"{head}^{{commit}}"], cwd=cand, capture_output=True).returncode == 0:
        repo["dir"] = run(["git", "rev-parse", "--show-toplevel"], cwd=cand).strip()
    mr = {"iid": int(iid), "url": info.get("web_url"), "title": info.get("title"), "description": (info.get("description") or "")[:1500]}
    return repo, diff, mr, []


class Source:
    def __init__(self, repo):
        self.dir, self.sha, self.cache = repo.get("dir"), repo.get("head_sha"), {}

    def read(self, path):
        if not self.dir or not self.sha:
            return None
        if path not in self.cache:
            p = subprocess.run(["git", "show", f"{self.sha}:{path}"], cwd=self.dir, capture_output=True, text=True, errors="replace")
            self.cache[path] = p.stdout.split("\n") if p.returncode == 0 else None
        return self.cache[path]

    def grep(self, symbol):
        if not self.dir or not self.sha:
            return []
        p = subprocess.run(["git", "grep", "-n", "-w", "-F", "-I", symbol, self.sha, "--"], cwd=self.dir, capture_output=True, text=True, errors="replace")
        rows = []
        for ln in p.stdout[:30000].split("\n"):
            m = re.match(rf"^{re.escape(self.sha)}:(.*?):(\d+):(.*)$", ln)
            if m:
                rows.append((m.group(1), int(m.group(2)), m.group(3)))
        return rows


# ---------------------------------------------------------------- analysis

SYMS = [
    re.compile(r"^\s*(?:class|module)\s+([A-Z]\w*(?:::\w+)*)"),
    re.compile(r"^\s*def\s+(?:self\.)?([A-Za-z_]\w*[?!]?)"),
    re.compile(r"^func\s+(?:\([^)]*\)\s*)?([A-Za-z_]\w*)\("),
    re.compile(r"^\s*(?:export\s+)?(?:async\s+)?function\s+(\w+)"),
    re.compile(r"^\s*(?:export\s+)?const\s+(\w+)\s*=\s*(?:async\s*)?\("),
    re.compile(r"^\s*(?:async\s+)?def\s+(\w+)"),
    re.compile(r"^\s*(?:export\s+)?class\s+(\w+)"),
]
STOP = {"initialize", "call", "new", "index", "show", "create", "update", "destroy", "edit", "perform", "run", "execute", "handle",
        "process", "build", "to_s", "to_h", "to_json", "as_json", "setup", "main", "init", "get", "set", "save", "load", "validate",
        "before", "after", "test", "default", "params", "options", "config", "attributes", "serialize", "render", "handler"}

TEST_NAME = re.compile(r"""^\s*(?:it|describe|context|scenario|feature|test)\s*\(?\s*['"](.+?)['"]|^\s*def\s+(test_\w+)|^func\s+(Test\w+)\(""")


def analyze(files, source, services, max_hits=DEFAULT_MAX_HITS):
    for f in files:
        f["category"] = category(f["path"])
    code = [f for f in files if f["category"] in ("code", "migration")]
    raw_hits = []
    for f in code:
        added_lines = set()
        for h in f["hunks"]:
            for kind, old, new, text in h["lines"]:
                if kind == "+":
                    added_lines.add(new)
                    for ch, d, t in match_line(f["path"], text):
                        raw_hits.append({"channel": ch, "direction": d, "target": t, "file": f["path"], "line": new, "in_diff": True, "removed": False, "text": clip(text)})
                elif kind == "-":
                    for ch, d, t in match_line(f["path"], text):
                        raw_hits.append({"channel": ch, "direction": d, "target": t, "file": f["path"], "line": old, "in_diff": True, "removed": True, "text": clip(text)})
        body = source.read(f["path"]) if f["status"] != "D" and f["category"] == "code" else None
        n = 0
        for i, text in enumerate(body or [], 1):
            if i in added_lines or n >= CONTEXT_CAP_FILE:
                continue
            for ch, d, t in match_line(f["path"], text):
                raw_hits.append({"channel": ch, "direction": d, "target": t, "file": f["path"], "line": i, "in_diff": False, "removed": False, "text": clip(text)})
                n += 1
    # collapse: a literal URL on the same line as a client call is one interaction
    by_line = {}
    for h in raw_hits:
        by_line.setdefault((h["file"], h["line"], h["removed"]), []).append(h)
    hits = []
    for group in by_line.values():
        if any(g["channel"] == "http" for g in group):
            http = next(g for g in group if g["channel"] == "http")
            urls = [g for g in group if g["channel"] == "endpoint" and (g["target"] or "").startswith("http")]
            if urls and not http["target"]:
                http["target"] = urls[0]["target"]
            group = [g for g in group if g not in urls]
        hits += group
    ctx_left = CONTEXT_CAP_TOTAL
    kept = []
    for h in hits:
        if not h["in_diff"]:
            if ctx_left <= 0 or h["channel"] == "flag":
                continue
            ctx_left -= 1
        kept.append(h)
    hits = kept
    order = {"kafka": 0, "temporal": 1, "grpc": 2, "http": 3, "endpoint": 4, "webhook": 5, "queue": 6, "sql": 7, "nosql": 8, "redis": 9, "blob": 10, "flag": 11}
    hits.sort(key=lambda h: (not h["in_diff"], order.get(h["channel"], 99), h["file"], h["line"]))
    dropped = max(0, len(hits) - max_hits)
    hits = hits[:max_hits]
    for i, h in enumerate(hits, 1):
        h["id"] = f"H{i}"
        h["services"] = []
        t = h["target"] or ""
        if h["channel"] == "endpoint":
            h["services"] = services.resolve_env(t) if re.fullmatch(ENVNAME, t) else services.resolve_url(t)
        elif h["channel"] == "http" and t.startswith("http"):
            h["services"] = services.resolve_url(t)
    # signals, from added lines of code files only
    signals = []
    for f in [x for x in code if x["category"] == "code"]:
        for h in f["hunks"]:
            for kind, old, new, text in h["lines"]:
                if kind != "+":
                    continue
                for sk, name in match_signal(text):
                    signals.append({"kind": sk, "name": name, "file": f["path"], "line": new, "text": clip(text)})
    for h in hits:
        if h["channel"] == "flag" and h["in_diff"] and not h["removed"]:
            signals.append({"kind": "flag", "name": h["target"], "file": h["file"], "line": h["line"], "text": h["text"]})
    for i, s in enumerate(signals, 1):
        s["id"] = f"S{i}"
    # tests: names only
    tests = []
    for f in [x for x in files if x["category"] == "test"]:
        names = []
        for h in f["hunks"]:
            for kind, old, new, text in h["lines"]:
                if kind == "+":
                    m = TEST_NAME.match(text)
                    if m:
                        names.append(next(g for g in m.groups() if g))
        tests.append({"file": f["path"], "added": f["added"], "names": names[:12], "more": max(0, len(names) - 12)})
    # callers of changed symbols (one hop out)
    symbols = []
    for f in [x for x in files if x["category"] == "code" and x["status"] != "D"]:
        for h in f["hunks"]:
            for kind, old, new, text in h["lines"]:
                if kind != "+":
                    continue
                for rx in SYMS:
                    m = rx.match(text)
                    if m:
                        name = m.group(1).split("::")[-1]
                        if len(name) >= 5 and name.lower() not in STOP and name not in [s[0] for s in symbols]:
                            symbols.append((name, f["path"], new))
                        break
    symbols.sort(key=lambda s: not s[0][0].isupper())
    changed_paths = {f["path"] for f in files}
    callers, shown = [], 0
    for name, path, line in symbols[:12]:
        rows = [r for r in source.grep(name) if r[0] not in changed_paths and category(r[0]) == "code"]
        for p, ln, text in rows[:4]:
            if shown >= 30:
                break
            callers.append({"symbol": name, "defined_in": f"{path}:{line}", "file": p, "line": ln, "text": clip(text)})
            shown += 1
        if len(rows) > 4:
            callers.append({"symbol": name, "defined_in": f"{path}:{line}", "file": None, "line": None, "text": f"... {len(rows) - 4} more caller(s)"})
    return hits, signals, tests, callers, dropped


def budgeted_hunks(files, hits, budget):
    """Choose which files' hunks the model reads. Returns (text, used, per-file read flags)."""
    hit_files, hit_lines = {}, set()
    for h in hits:
        if h["in_diff"]:
            hit_files.setdefault(h["file"], set()).add(h["id"])
            hit_lines.add((h["file"], h["removed"], h["line"]))

    def hunk_has_hit(path, hunk):
        return any(k in "+-" and (path, k == "-", old if k == "-" else new) in hit_lines for k, old, new, _ in hunk["lines"])

    cand = [f for f in files if f["category"] == "code" and not f["binary"] and f["hunks"]]
    cand.sort(key=lambda f: (f["path"] not in hit_files, -(f["added"] + f["removed"]), f["path"]))
    used, out = 0, []
    for f in cand:
        size = f["added"] + f["removed"]
        chosen, reason = f["hunks"], None
        if used + size > budget:
            hh = [h for h in f["hunks"] if hunk_has_hit(f["path"], h)]
            hsize = sum(1 for x in hh for ln in x["lines"] if ln[0] in "+-")
            if hh and used + hsize <= budget:
                chosen, size, reason = hh, hsize, "only hunks with channel hits"
            else:
                f["read"], f["reason"] = False, "over budget"
                continue
        used += size
        f["read"], f["reason"] = True, reason
        tag = f" [{' '.join(sorted(hit_files[f['path']]))}]" if f["path"] in hit_files else ""
        out.append(f"=== {f['path']} ({f['status']} +{f['added']} -{f['removed']}){tag}")
        for h in chosen:
            out.append(h["header"])
            out += [f"{k}{t}" for k, _, _, t in h["lines"]]
    return "\n".join(out) + "\n", used


# ---------------------------------------------------------------- output

def auto_dir(repo, mr, args):
    if args.paths:
        words = slugify(args.name or " ".join(Path(x).name for x in args.paths))
        return ROOT / "flow" / f"{'-'.join(words.split('-')[:6]) or 'flow'}--{repo['head_sha'][:7]}"
    title = (mr or {}).get("title") or repo.get("branch") or "change"
    ref = f"mr{mr['iid']}" if mr else slugify(repo.get("branch") or "local")
    slug = "-".join(slugify(title).split("-")[:6]) or "change"
    return ROOT / "change" / f"{slug}--{ref}"


def digest(scan):
    r, st = scan["repo"], scan["stats"]
    base = f"base {(r.get('base_sha') or '')[:8]} ({r.get('base')})" if scan["mode"] != "paths" else "reading HEAD"
    L = [f"# lens scan ({scan['mode']}) -- {scan['dir']}",
         f"repo {r['name']} @ {r['head_sha'][:8]}  {base}  branch {r.get('branch')}  "
         f"{'pushed' if r['pushed'] else 'NOT pushed (links appear after push)'}",
         f"files {st['files']} (+{st['added']} -{st['removed']})  read budget {st['budget']}, used {st['used']}  -> read hunks.txt for the code",
         f"service map: {scan['services_map'] or 'none (targets stay unresolved)'}"]
    for w in scan["warnings"]:
        L.append(f"warning: {w}")
    if scan.get("mr"):
        L.append(f"MR !{scan['mr']['iid']}: {scan['mr']['title']}")
        if scan["mr"]["description"]:
            L.append("MR description (reported, not verified): " + scan["mr"]["description"][:600].replace("\n", " "))
    L.append("\n## files  (R = in hunks.txt)")
    for f in scan["files"]:
        flag = "R" if f.get("read") else "-"
        L.append(f"{flag} {f['category']:9} +{f['added']:<4} -{f['removed']:<4} {f['path']}" + (f"   ({f['reason']})" if f.get("reason") else ""))
    L.append("\n## channels  id | channel dir | target -> service | file:line | text  (* = outside the changed lines, in a changed file)")
    for h in scan["hits"]:
        svc = ",".join(h["services"])
        L.append(f"{h['id']} | {h['channel']} {h['direction']}{' REMOVED' if h['removed'] else ''} | {h['target'] or '-'}{' -> ' + svc if svc else ''} | "
                 f"{h['file']}:{h['line']}{'' if h['in_diff'] else ' *'} | {h['text']}")
    if scan["signals"]:
        L.append("\n## signals in the scanned code  id | kind | name | file:line")
        for s in scan["signals"]:
            L.append(f"{s['id']} | {s['kind']} | {s['name'] or s['text'][:70]} | {s['file']}:{s['line']}")
    if scan["callers"]:
        L.append("\n## callers of the scanned symbols (outside the scanned files)")
        for c in scan["callers"]:
            L.append(f"{c['symbol']} <- {c['file']}:{c['line']} {c['text']}" if c["file"] else f"{c['symbol']}: {c['text']}")
    if scan["tests"]:
        L.append("\n## tests (names only)")
        for t in scan["tests"]:
            L.append(f"{t['file']} (+{t['added']}): " + "; ".join(t["names"]) + (f"; +{t['more']} more" if t["more"] else ""))
    return "\n".join(L) + "\n"


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out")
    ap.add_argument("--repo")
    ap.add_argument("--base")
    ap.add_argument("--no-fetch", action="store_true")
    ap.add_argument("--mr")
    ap.add_argument("--project")
    ap.add_argument("--budget", type=int, default=DEFAULT_BUDGET)
    ap.add_argument("--paths", nargs="+")
    ap.add_argument("--name")
    ap.add_argument("--max-hits", type=int, default=DEFAULT_MAX_HITS)
    ap.add_argument("--services")
    args = ap.parse_args()
    try:
        repo, diff, mr, warnings = mr_input(args) if args.mr else paths_input(args) if args.paths else local_input(args)
    except RuntimeError as e:
        die(str(e))
    files = parse_diff(diff)
    if not files:
        die("no changes against the base")
    source, services = Source(repo), Services(args.services, repo.get("dir"))
    if repo.get("dir") is None and args.mr:
        warnings.append("no local clone at the MR head: scanned the diff only (no whole-file hits, no callers)")
    hits, signals, tests, callers, dropped = analyze(files, source, services, args.max_hits)
    if dropped:
        warnings.append(f"{dropped} more channel hit(s) were not listed (--max-hits {args.max_hits}): narrow the paths or raise it")
    text, used = budgeted_hunks(files, hits, args.budget)
    for f in files:
        f.setdefault("read", False)
        if f["category"] != "code" and not f.get("reason"):
            f["reason"] = {"noise": "generated or lock file", "doc": "docs", "test": "names only", "migration": "table names only"}.get(f["category"], "")
    out = Path(args.out).expanduser() if args.out else auto_dir(repo, mr, args)
    out.mkdir(parents=True, exist_ok=True)
    scan = {
        "version": 1, "mode": "paths" if args.paths else "mr" if args.mr else "change", "dir": str(out), "repo": repo, "mr": mr, "warnings": warnings,
        "services_map": services.path,
        "stats": {"files": len(files), "added": sum(f["added"] for f in files), "removed": sum(f["removed"] for f in files), "budget": args.budget, "used": used},
        "files": [{k: f[k] for k in ("path", "status", "added", "removed", "category", "read", "reason") if k in f} for f in files],
        "hits": hits, "signals": signals, "tests": tests, "callers": callers,
    }
    (out / "scan.json").write_text(json.dumps(scan, indent=1) + "\n")
    (out / "hunks.txt").write_text(text)
    sys.stdout.write(digest(scan))


if __name__ == "__main__":
    main()
