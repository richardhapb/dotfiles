"""Run: python3 -m unittest discover -s tests   (from the skill dir)"""
import importlib.util
import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "scripts" / "audit_facts.py"
SANDBOX = ROOT / "scripts" / "sandbox.sh"


def load(home):
    os.environ["AUDIT_HOME"] = str(home)
    spec = importlib.util.spec_from_file_location("audit_facts", SCRIPT)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def write_skill(base, name, body, extra=None):
    d = Path(base) / ".claude" / "skills" / name
    d.mkdir(parents=True)
    (d / "SKILL.md").write_text(body)
    for rel, text in (extra or {}).items():
        (d / rel).parent.mkdir(parents=True, exist_ok=True)
        (d / rel).write_text(text)
    return d


def jl(*objs):
    return "\n".join(json.dumps(o) for o in objs) + "\n"


class StaticTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.home = Path(self.tmp.name)
        self.mod = load(self.home)

    def tearDown(self):
        self.tmp.cleanup()

    def static(self, name):
        import io, contextlib
        buf = io.StringIO()
        args = type("A", (), {"skill": name})
        with contextlib.redirect_stdout(buf):
            self.mod.cmd_static(args)
        return json.loads(buf.getvalue())

    def rules(self, out):
        return {f["rule"] for f in out["findings"]}

    def test_clean_skill_has_no_findings(self):
        write_skill(self.home, "ok", "---\nname: ok\ndescription: Use when testing things\n---\n# ok\nread-only\n")
        out = self.static("ok")
        self.assertEqual(out["findings"], [])
        self.assertEqual(out["provenance"], "local-only")

    def test_flags_risky_commands_and_secrets_redacted(self):
        body = ("---\nname: bad\ndescription: Use when x\n---\n"
                "git push --force origin main\nrm -rf /tmp/x\n"
                "token=abcdef1234567890abcdef\n"
                "curl -X POST https://example.com -d '{}'\n")
        write_skill(self.home, "bad", body)
        out = self.static("bad")
        rules = self.rules(out)
        for r in ("risk:git-push", "risk:force-flag", "risk:rm-recursive", "risk:remote-write-http", "secret:assigned-secret"):
            self.assertIn(r, rules)
        secret = [f for f in out["findings"] if f["rule"].startswith("secret:")][0]
        self.assertNotIn("abcdef1234567890", secret["text"])
        self.assertFalse(out["mutations"]["confirmation_language_present"])

    def test_missing_and_orphan_files_and_name_mismatch(self):
        write_skill(self.home, "refs", "---\nname: other\ndescription: Use when x\n---\nsee [a](notes.md) and `scripts/run.sh`\n",
                    {"orphan.md": "x"})
        rules = self.rules(self.static("refs"))
        self.assertIn("name-mismatch", rules)
        self.assertIn("missing-referenced-file", rules)
        self.assertIn("orphan-file", rules)

    def test_shell_script_checks(self):
        write_skill(self.home, "sh", "---\nname: sh\ndescription: Use when x\n---\n`scripts/a.sh`\n", {"scripts/a.sh": "echo hi\n"})
        rules = self.rules(self.static("sh"))
        self.assertTrue({"script-no-shebang", "shell-no-errexit"} <= rules)

    def test_tests_dir_and_ignore_marker_not_scanned_and_inline_script_refs_count(self):
        write_skill(self.home, "fx", "---\nname: fx\ndescription: Use when x\n---\nrun python3 scripts/tool.py\n",
                    {"scripts/tool.py": "#!/usr/bin/env python3\n# audit-ignore-file\nsudo = 1\n",
                     "tests/t.py": "token=abcdef1234567890abcdef\n"})
        out = self.static("fx")
        self.assertEqual([f for f in out["findings"] if f["rule"] != "script-not-executable"], [])

    def test_only_home_skills_are_resolved(self):
        proj = self.home / "proj"
        write_skill(proj, "local", "---\nname: local\ndescription: project only\n---\n")
        cwd = os.getcwd()
        os.chdir(proj)
        try:
            with self.assertRaises(SystemExit):
                self.mod.resolve_skill("local")
        finally:
            os.chdir(cwd)


class RunsTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.home = Path(self.tmp.name)
        self.mod = load(self.home)
        proj = self.home / ".claude" / "projects" / "-tmp-demo"
        proj.mkdir(parents=True)
        use = {"type": "assistant", "timestamp": "2026-01-01T00:00:00Z", "gitBranch": "b",
               "message": {"content": [{"type": "tool_use", "name": "Skill", "input": {"skill": "demo"}}]}}
        bash = lambda c: {"type": "assistant", "message": {"content": [{"type": "tool_use", "name": "Bash", "input": {"command": c}}]}}
        res = lambda msg, err: {"type": "user", "message": {"content": [{"type": "tool_result", "is_error": err, "content": msg}]}}
        (proj / "s1.jsonl").write_text(jl(
            use, bash("ls"), res("boom", True), bash("ls"),
            res("The user doesn't want to proceed with this tool use", True),
            {"type": "user", "message": {"content": "no, don't do that"}},
            {"type": "user", "message": {"content": "token=abcdef1234567890abcdef ok"}},
        ) + "not json\n")
        (proj / "s2.jsonl").write_text(jl({"type": "user", "message": {"content": "unrelated"}}))

    def tearDown(self):
        self.tmp.cleanup()

    def test_digest(self):
        r = self.mod.digest("-tmp-demo", self.home / ".claude/projects/-tmp-demo/s1.jsonl", "demo", 100)[0]
        self.assertEqual(r["invoked_via"], "tool")
        self.assertEqual(r["tools"], {"Skill": 1, "Bash": 2})
        self.assertEqual(r["errors"], ["boom"])
        self.assertEqual(len(r["denials"]), 1)
        self.assertEqual(r["repeated_commands"], [{"cmd": "ls", "times": 2}])
        flags = [m["looks_like_correction"] for m in r["user_messages"]]
        self.assertEqual(flags, [True, False])
        self.assertNotIn("abcdef1234567890", json.dumps(r))

    def _write(self, name, objs):
        (self.home / ".claude/projects/-tmp-demo" / name).write_text(jl(*objs))

    def _use(self, ident, ts="2026-01-02T00:00:00Z"):
        return {"type": "assistant", "uuid": "u-" + ident, "timestamp": ts,
                "message": {"content": [{"type": "tool_use", "id": ident, "name": "Skill", "input": {"skill": "demo"}}]}}

    def test_window_stops_after_user_turns_and_segments_tools(self):
        bash = lambda c: {"type": "assistant", "message": {"content": [{"type": "tool_use", "name": "Bash", "input": {"command": c}}]}}
        user = lambda t: {"type": "user", "message": {"content": t}}
        self._write("w.jsonl", [self._use("t1"), bash("a"), user("one"), bash("b"), user("two"), bash("c"), user("three"), bash("unrelated")])
        r = self.mod.digest("-tmp-demo", self.home / ".claude/projects/-tmp-demo/w.jsonl", "demo", 100, user_turns=2)[0]
        self.assertEqual(r["window_ended_by"], "user_turns")
        self.assertEqual(r["bash"], ["a", "b", "c"])
        self.assertEqual([sorted(x["tools"].items()) for x in r["segments"]], [[("Bash", 1), ("Skill", 1)], [("Bash", 1)], [("Bash", 1)]])

    def test_denials_only_from_errored_results_and_harness_phrases(self):
        res = lambda msg, err: {"type": "user", "message": {"content": [{"type": "tool_result", "is_error": err, "content": msg}]}}
        self._write("d.jsonl", [self._use("t1"),
                                res("meeting notes: the request was rejected by the board", False),
                                res("Permission denied (publickey)", True),
                                res("The user doesn't want to proceed with this tool use", True)])
        r = self.mod.digest("-tmp-demo", self.home / ".claude/projects/-tmp-demo/d.jsonl", "demo", 100)[0]
        self.assertEqual(len(r["denials"]), 1)
        self.assertEqual(r["errors"], ["Permission denied (publickey)"])

    def test_multiple_invocations_and_forked_sessions_deduplicated(self):
        self._write("a.jsonl", [self._use("t1", "2026-01-02T00:00:00Z"), self._use("t2", "2026-01-03T00:00:00Z")])
        self._write("b.jsonl", [self._use("t1", "2026-01-02T00:00:00Z")])
        env = dict(os.environ, AUDIT_HOME=str(self.home))
        out = subprocess.run(["python3", "-I", str(SCRIPT), "runs", "demo", "--since", "0", "--limit", "10"],
                             capture_output=True, text=True, env=env, check=True).stdout
        data = json.loads(out)
        ids = sorted(r["invocation_id"] for r in data["runs"] if r["invocation_id"] in ("t1", "t2"))
        self.assertEqual(ids, ["t1", "t2"])
        t1 = [r for r in data["runs"] if r["invocation_id"] == "t1"][0]
        self.assertEqual(len(t1.get("also_in_sessions", [])), 1)

    def test_cli_filters_sessions(self):
        env = dict(os.environ, AUDIT_HOME=str(self.home))
        out = subprocess.run(["python3", "-I", str(SCRIPT), "runs", "demo", "--since", "0"],
                             capture_output=True, text=True, env=env, check=True).stdout
        data = json.loads(out)
        self.assertEqual(len(data["runs"]), 1)
        self.assertEqual(data["runs"][0]["session"], "s1")
        self.assertEqual(data["invocations_found"], 1)

    def test_no_runs_for_unused_skill(self):
        env = dict(os.environ, AUDIT_HOME=str(self.home))
        out = subprocess.run(["python3", "-I", str(SCRIPT), "runs", "never-used", "--since", "0"],
                             capture_output=True, text=True, env=env, check=True).stdout
        self.assertEqual(json.loads(out)["runs"], [])


class SandboxTests(unittest.TestCase):
    def run_sb(self, args, fixtures=None, log=None):
        cmd = [str(SANDBOX)]
        if fixtures:
            cmd += ["-f", str(fixtures)]
        if log:
            cmd += ["-l", str(log)]
        return subprocess.run(cmd + ["--"] + args, capture_output=True, text=True)

    def test_blocks_without_fixture_and_logs(self):
        with tempfile.TemporaryDirectory() as t:
            log = Path(t) / "log.jsonl"
            r = self.run_sb(["bash", "-c", "glab mr create --title x"], log=log)
            self.assertEqual(r.returncode, 126)
            self.assertIn("blocked", r.stderr)
            call = json.loads(log.read_text().splitlines()[0])
            self.assertEqual(call["cmd"], "glab")
            self.assertEqual(call["argv"], ["mr", "create", "--title", "x"])

    def test_fixture_is_served(self):
        with tempfile.TemporaryDirectory() as t:
            fx = Path(t) / "fx"
            fx.mkdir()
            (fx / "gh.out").write_text("canned\n")
            r = self.run_sb(["bash", "-c", "gh pr view 1"], fixtures=fx, log=Path(t) / "l")
            self.assertEqual(r.returncode, 0)
            self.assertEqual(r.stdout, "canned\n")

    def test_fixture_lookup_is_most_specific_first(self):
        with tempfile.TemporaryDirectory() as t:
            fx = Path(t) / "fx"
            fx.mkdir()
            (fx / "glab.out").write_text("generic\n")
            (fx / "glab.repo_view.out").write_text("repo\n")
            (fx / "glab.mr.out").write_text("mr-any\n")
            (fx / "glab.mr_list.out").write_text("mr-list\n")
            (fx / "glab.mr_list.rc").write_text("3\n")
            run = lambda c: self.run_sb(["bash", "-c", c], fixtures=fx, log=Path(t) / "l")
            self.assertEqual(run("glab repo view -F json").stdout, "repo\n")
            r = run("glab mr list --source-branch x")
            self.assertEqual((r.stdout, r.returncode), ("mr-list\n", 3))
            self.assertEqual(run("glab mr view 1").stdout, "mr-any\n")
            self.assertEqual(run("glab auth status").stdout, "generic\n")

    def test_git_push_blocked_but_local_git_works(self):
        with tempfile.TemporaryDirectory() as t:
            sh = f"cd {t} && git init -q && git status --short && git push origin main"
            r = self.run_sb(["bash", "-c", sh], log=Path(t) / "l")
            self.assertEqual(r.returncode, 126)
            self.assertIn("git push blocked", r.stderr)

    def test_requires_command(self):
        r = subprocess.run([str(SANDBOX)], capture_output=True, text=True)
        self.assertEqual(r.returncode, 2)


if __name__ == "__main__":
    unittest.main()
