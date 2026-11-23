import importlib.util
import json
import subprocess
import sys
import tempfile
import textwrap
import unittest
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent.parent / "scripts"


def load(name):
    spec = importlib.util.spec_from_file_location(name, SCRIPTS / f"{name}.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


scan = load("scan")
build = load("build")
redact = load("redact")

DIFF = textwrap.dedent("""\
    diff --git a/app/client.rb b/app/client.rb
    index 111..222 100644
    --- a/app/client.rb
    +++ b/app/client.rb
    @@ -3,4 +3,6 @@ class Client
       def old
    -    legacy
    +    Faraday.get("https://orders.example.com/v1/x")
    +    -- not a header
       end
    +  def fresh_method; end
     end
    diff --git a/db/old.rb b/db/old.rb
    deleted file mode 100644
    --- a/db/old.rb
    +++ /dev/null
    @@ -1,1 +0,0 @@
    -gone
    diff --git a/new.rb b/new.rb
    new file mode 100644
    --- /dev/null
    +++ b/new.rb
    @@ -0,0 +1,2 @@
    +a
    +b
    """)


class ParseDiff(unittest.TestCase):
    def test_line_numbers_and_statuses(self):
        files = scan.parse_diff(DIFF)
        self.assertEqual([f["path"] for f in files], ["app/client.rb", "db/old.rb", "new.rb"])
        self.assertEqual([f["status"] for f in files], ["M", "D", "A"])
        added = [(n, t) for k, _, n, t in files[0]["hunks"][0]["lines"] if k == "+"]
        self.assertEqual(added[0][0], 4)
        self.assertEqual((files[0]["removed"], files[0]["added"]), (1, 3))

    def test_dash_line_inside_hunk_is_a_body_line(self):
        texts = [t.strip() for k, _, _, t in scan.parse_diff(DIFF)[0]["hunks"][0]["lines"] if k == "+"]
        self.assertIn("-- not a header", texts)


class Classify(unittest.TestCase):
    def test_categories(self):
        c = scan.category
        self.assertEqual(c("Gemfile.lock"), "noise")
        self.assertEqual(c("web/dist/app.js"), "noise")
        self.assertEqual(c("spec/models/user_spec.rb"), "test")
        self.assertEqual(c("db/migrate/20240101_add_x.rb"), "migration")
        self.assertEqual(c("README.md"), "doc")
        self.assertEqual(c("app/models/user.rb"), "code")


class Patterns(unittest.TestCase):
    def test_http_client_with_url(self):
        out = scan.match_line("a.rb", 'Faraday.get("https://x.example.com/v1")')
        self.assertIn(("http", "out", "https://x.example.com/v1"), out)

    def test_env_url_needs_a_url_like_name(self):
        self.assertIn(("endpoint", "out", "ORDERS_URL"), scan.match_line("a.rb", 'ENV.fetch("ORDERS_URL")'))
        self.assertEqual(scan.match_line("a.rb", 'ENV.fetch("LOG_LEVEL")'), [])

    def test_routes_only_in_routes_files(self):
        self.assertEqual([(c, d) for c, d, _ in scan.match_line("config/routes.rb", "  post '/reports'")], [("http", "in")])
        self.assertEqual(scan.match_line("app/x.rb", "  post '/reports'"), [])

    def test_comment_lines_are_skipped(self):
        self.assertEqual(scan.match_line("a.rb", "# Faraday.get('https://x.example.com')"), [])

    def test_signals(self):
        self.assertEqual(scan.match_signal('StatsD.increment("orders.created")')[0], ("metric", "orders.created"))
        self.assertEqual(scan.match_signal("raise ReviewError, 'x'")[0][0], "error")


class ServicesMap(unittest.TestCase):
    def make(self):
        p = Path(tempfile.mkdtemp()) / "services.json"
        p.write_text(json.dumps({"services": {
            "Orders API": {"hosts": ["orders"], "env": ["ORDERS_URL"], "ports": [8080]},
            "Billing": {"hosts": ["billing"]}}}))
        return scan.Services(str(p))

    def test_resolves_env_host_and_local_port(self):
        s = self.make()
        self.assertEqual(s.resolve_env("ORDERS_URL"), ["Orders API"])
        self.assertEqual(s.resolve_url("https://orders-staging.corp.internal/v1"), ["Orders API"])
        self.assertEqual(s.resolve_url("http://localhost:8080/x"), ["Orders API"])
        self.assertEqual(s.resolve_url("https://billing.corp.internal"), ["Billing"])

    def test_unknown_stays_unresolved(self):
        s = self.make()
        self.assertEqual(s.resolve_env("OTHER_URL"), [])
        self.assertEqual(s.resolve_url("https://example.com"), [])
        self.assertEqual(s.resolve_url("http://localhost:1/x"), [])

    def test_no_map_resolves_nothing(self):
        s = scan.Services("/nonexistent")
        self.assertIsNone(s.path)
        self.assertEqual(s.resolve_url("https://orders.corp.internal"), [])


def git(cwd, *args):
    subprocess.run(["git", *args], cwd=cwd, check=True, capture_output=True,
                   env={"GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t", "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@t",
                        "PATH": "/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin", "HOME": str(cwd)})


class Repo(unittest.TestCase):
    def setUp(self):
        self.repo = Path(tempfile.mkdtemp()) / "demo"
        (self.repo / "app").mkdir(parents=True)
        git(self.repo, "init", "-b", "master")
        (self.repo / "app/client.rb").write_text("class Client\n  def old\n    1\n  end\nend\n")
        (self.repo / "app/caller.rb").write_text("class Caller\n  def go\n    Client.new.fetch_report\n  end\nend\n")
        git(self.repo, "add", "-A")
        git(self.repo, "commit", "-m", "base")
        git(self.repo, "checkout", "-b", "feature")
        (self.repo / "app/client.rb").write_text(
            "class Client\n  def old\n    1\n  end\n\n  def fetch_report\n    Faraday.get(ENV['ORDERS_URL'])\n"
            "    StatsD.increment('report.fetched')\n  end\nend\n")
        (self.repo / "spec").mkdir()
        (self.repo / "spec/client_spec.rb").write_text("describe Client do\n  it 'fetches a report' do\n  end\nend\n")
        (self.repo / "Gemfile.lock").write_text("x\n")
        git(self.repo, "add", "-A")
        git(self.repo, "commit", "-m", "feature")
        self.out = Path(tempfile.mkdtemp())

    def run_scan(self, *extra, ok=True):
        p = subprocess.run([sys.executable, str(SCRIPTS / "scan.py"), "--repo", str(self.repo), "--no-fetch", "--out", str(self.out),
                            "--services", "/nonexistent", *extra], capture_output=True, text=True)
        if ok:
            self.assertEqual(p.returncode, 0, p.stderr)
            return p.stdout, json.loads((self.out / "scan.json").read_text())
        return p


class ChangeMode(Repo):
    def test_finds_channels_signals_callers_and_filters_noise(self):
        digest, s = self.run_scan("--base", "master")
        self.assertEqual(s["mode"], "change")
        h = [x for x in s["hits"] if x["file"] == "app/client.rb" and x["in_diff"]]
        self.assertTrue(any(x["channel"] == "http" for x in h))
        self.assertTrue(any(x["channel"] == "endpoint" and x["target"] == "ORDERS_URL" for x in h))
        self.assertEqual([x["name"] for x in s["signals"]], ["report.fetched"])
        self.assertTrue(any(c["file"] == "app/caller.rb" for c in s["callers"]))
        cats = {f["path"]: f["category"] for f in s["files"]}
        self.assertEqual((cats["Gemfile.lock"], cats["spec/client_spec.rb"]), ("noise", "test"))
        self.assertEqual(s["tests"][0]["names"], ["fetches a report"])
        hunks = (self.out / "hunks.txt").read_text()
        self.assertIn("app/client.rb", hunks)
        self.assertNotIn("Gemfile.lock", hunks)
        self.assertIn("NOT pushed", digest)

    def test_budget_skips_files_and_reports_it(self):
        _, s = self.run_scan("--base", "master", "--budget", "1")
        client = next(f for f in s["files"] if f["path"] == "app/client.rb")
        self.assertEqual((client["read"], client["reason"]), (False, "over budget"))

    def test_max_hits_caps_the_list_and_says_so(self):
        _, s = self.run_scan("--base", "master", "--max-hits", "1")
        self.assertEqual(len(s["hits"]), 1)
        self.assertTrue(any("not listed" in w for w in s["warnings"]))

    def test_empty_diff_is_an_error(self):
        git(self.repo, "checkout", "master")
        p = self.run_scan("--base", "master", ok=False)
        self.assertEqual(p.returncode, 2)
        self.assertIn("no changes", p.stderr)


class PathsMode(Repo):
    def test_reads_existing_code_at_head_and_finds_outside_callers(self):
        digest, s = self.run_scan("--paths", "app/client.rb", "--name", "client flow")
        self.assertEqual(s["mode"], "paths")
        named = scan.auto_dir(s["repo"], None, type("A", (), {"paths": ["app/client.rb"], "name": "client flow"})())
        self.assertEqual((named.parent.name, named.name.split("--")[0]), ("flow", "client-flow"))
        self.assertTrue(any(x["channel"] == "http" and x["file"] == "app/client.rb" for x in s["hits"]))
        self.assertTrue(all(x["in_diff"] and not x["removed"] for x in s["hits"]))
        self.assertTrue(any(c["file"] == "app/caller.rb" for c in s["callers"]))
        self.assertIn("class Client", (self.out / "hunks.txt").read_text())
        self.assertNotIn("app/caller.rb", [f["path"] for f in s["files"]])
        self.assertIn("reading HEAD", digest)

    def test_directory_paths_skip_noise_and_missing_paths_fail(self):
        _, s = self.run_scan("--paths", ".")
        self.assertNotIn("Gemfile.lock", [f["path"] for f in s["files"]])
        p = self.run_scan("--paths", "nope/", ok=False)
        self.assertEqual(p.returncode, 2)
        self.assertIn("no tracked files", p.stderr)

    def test_uncommitted_changes_are_flagged(self):
        (self.repo / "app/client.rb").write_text("changed\n")
        _, s = self.run_scan("--paths", "app")
        self.assertTrue(any("uncommitted" in w for w in s["warnings"]))


class Build(unittest.TestCase):
    def scan_fixture(self, linkable, mode="change"):
        return {
            "mode": mode,
            "repo": {"host": "gitlab.example.com", "project": "grp/proj", "kind": "gitlab", "head_sha": "a" * 40, "linkable": linkable, "dir": None},
            "hits": [
                {"id": "H1", "channel": "http", "direction": "out", "target": "https://x", "file": "a b.rb", "line": 7, "in_diff": True, "removed": False, "text": "Faraday.get", "services": ["svc"]},
                {"id": "H2", "channel": "kafka", "direction": "in", "target": "t", "file": "c.rb", "line": 2, "in_diff": False, "removed": False, "text": "consume", "services": []},
            ],
            "signals": [{"id": "S1", "kind": "metric", "name": "m", "file": "a b.rb", "line": 9, "text": "x"}],
            "files": [{"path": "big.rb", "category": "code", "read": False}],
            "stats": {"files": 1, "added": 2, "removed": 1}, "warnings": ["w1"], "mr": None,
        }

    def data(self):
        return {"meta": {"title": "t"}, "tldr": ["x"], "touchpoints": [{"id": "H1", "note": "n"}, {"id": "H9"}],
                "flow": {"nodes": [{"id": "a", "label": "A", "at": "H1"}, {"id": "b", "label": "B", "at": "H7"}], "edges": [{"from": "a", "to": "zz"}]},
                "sequence": {"actors": ["x"], "steps": [{"from": "x", "to": "x", "label": "s", "at": "H2"}]}}

    def test_links_are_pinned_and_encoded_when_pushed(self):
        d = self.data()
        problems = build.expand(d, self.scan_fixture(True))
        row = d["touchpoints"]["rows"][0]
        self.assertEqual(row["where"]["url"], f"https://gitlab.example.com/grp/proj/-/blob/{'a' * 40}/a%20b.rb#L7")
        self.assertEqual((row["service"], row["note"]), ("svc", "n"))
        self.assertEqual([m["id"] for m in d["touchpoints"]["more"]], ["H2"])
        self.assertTrue(any("H9" in p for p in problems))

    def test_at_on_nodes_and_steps_resolves_to_where(self):
        d = self.data()
        problems = build.expand(d, self.scan_fixture(True))
        self.assertTrue(d["flow"]["nodes"][0]["where"]["url"].endswith("/a%20b.rb#L7"))
        self.assertEqual(d["sequence"]["steps"][0]["where"]["label"], "c.rb:2")
        self.assertNotIn("where", d["flow"]["nodes"][1])
        self.assertTrue(any("H7" in p for p in problems))

    def test_no_links_when_not_pushed(self):
        d = self.data()
        build.expand(d, self.scan_fixture(False))
        self.assertIsNone(d["touchpoints"]["rows"][0]["where"]["url"])
        self.assertIn("Not pushed", d["touchpoints"]["lead"])

    def test_evidence_says_what_was_not_read_and_the_mode(self):
        d = self.data()
        build.expand(d, self.scan_fixture(True))
        claims = " ".join(e["claim"] for e in d["evidence"])
        self.assertIn("Not read: 1 code file", claims)
        self.assertIn("w1", claims)
        self.assertIn("Scanned the diff", claims)
        d = self.data()
        build.expand(d, self.scan_fixture(True, "paths"))
        self.assertIn("Read 1 file(s) statically at HEAD", " ".join(e["claim"] for e in d["evidence"]))

    def test_lint_catches_diagram_mistakes(self):
        out = build.lint({"flow": {"nodes": [{"id": "a", "label": "A" * 50}, {"id": "a", "label": "dup"}, {"id": "c", "label": "lonely"}],
                                   "edges": [{"from": "a", "to": "zz", "label": "l" * 30}]},
                          "participants": [{"id": "p"}], "edges": [{"from": "p", "to": "q"}],
                          "sequence": {"actors": ["z"], "steps": [{"from": "p", "to": "p", "label": "s"}]}}, Path("."))
        text = "\n".join(out)
        for needle in ("duplicate node id 'a'", "node label over 40", "unknown node 'zz'", "edge label over 24", "node 'c' has no edges",
                       "unknown participant 'q'", "actor 'z' is not in participants", "step 1 uses 'p'"):
            self.assertIn(needle, text)

    def test_renders_a_page_without_a_scan_and_builds_the_index(self):
        root = Path(tempfile.mkdtemp())
        d = root / "flow" / "demo--abc"
        d.mkdir(parents=True)
        (d / "data.json").write_text(json.dumps({
            "meta": {"title": "Demo </script>", "kind": "flow", "date": "2026-01-01", "tags": ["x"]}, "tldr": ["a"],
            "flow": {"nodes": [{"id": "a", "label": "Start", "kind": "start", "note": "n"}, {"id": "b", "label": "End", "kind": "end"}],
                     "edges": [{"from": "a", "to": "b"}]},
            "states": {"nodes": [{"id": "s1", "label": "new", "kind": "start"}, {"id": "s2", "label": "done", "kind": "state"}], "edges": [{"from": "s1", "to": "s2", "label": "finish"}]}}))
        out, problems = build.build(d)
        self.assertEqual(problems, [])
        html = out.read_text()
        self.assertIn('"title": "Demo <\\/script>"', html)
        self.assertNotIn("/*__DATA__*/", html)
        index = build.build_index(root)
        self.assertIn("demo--abc/index.html", index.read_text())

    def test_unknown_payload_file_is_fatal(self):
        d = Path(tempfile.mkdtemp())
        (d / "data.json").write_text(json.dumps({"meta": {"title": "t"}, "tldr": [], "payloads": [{"id": "p", "file": "payloads/none.json"}]}))
        with self.assertRaises(SystemExit):
            build.build(d)


class Redact(unittest.TestCase):
    def test_masks_by_key_and_by_value(self):
        out = redact.redact({"user": {"email": "a@b.co", "ssn": "123-45-6789", "note": "ssn 123-45-6789"}, "api_key": "k",
                             "file_content": "AAAA", "n": 3, "auth": "Bearer abc.def", "jwt": "eyJhbGciOi.eyJzdWIi.sig-1", "ok": None})
        self.assertEqual(out["user"]["email"], "<email>")
        self.assertEqual(out["user"]["ssn"], "<redacted>")
        self.assertEqual(out["user"]["note"], "ssn <redacted>")
        self.assertEqual(out["api_key"], "<redacted>")
        self.assertIn("omitted", out["file_content"])
        self.assertEqual(out["auth"], "Bearer <redacted>")
        self.assertEqual(out["jwt"], "<jwt>")
        self.assertEqual((out["n"], out["ok"]), (3, None))

    def test_long_strings_are_cut_and_non_json_is_kept_as_text(self):
        self.assertIn("...<1000 chars>", redact.redact({"v": "x" * 1000})["v"])
        self.assertEqual(redact.parse("plain text"), "plain text")
        self.assertIsNone(redact.parse("  "))

    def test_write_payload_numbers_files_and_returns_the_entry(self):
        d = Path(tempfile.mkdtemp())
        e1 = redact.write_payload(d, "a", "svc", "GET", "/x", "", None, '{"token":"t"}')
        e2 = redact.write_payload(d, "b", "svc", "POST", "/y", "", '{"a":1}', None)
        self.assertEqual((e1["file"], e2["file"]), ("payloads/01-a.json", "payloads/02-b.json"))
        self.assertEqual(json.loads((d / e1["file"]).read_text())["response"], {"token": "<redacted>"})
        self.assertEqual(e1["title"], "GET /x")


if __name__ == "__main__":
    unittest.main()
