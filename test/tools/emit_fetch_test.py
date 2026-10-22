"""Exercise artifact producer trust through emit-fetch.sh, with no network."""
import json
from pathlib import Path
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
import zipfile


SCRIPT = Path(__file__).resolve().parents[2] / "scripts/emit-fetch.sh"


def artifact(branch="main", repository=42, expired=False, artifact_id=901, run=77):
    return {"id": artifact_id, "expired": expired, "workflow_run": {
        "id": run, "head_branch": branch,
        "head_repository_id": repository, "repository_id": 42,
    }}


class EmitFetchTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        (self.root / "scripts").mkdir()
        shutil.copyfile(SCRIPT, self.root / "scripts/emit-fetch.sh")
        (self.root / "bin").mkdir()
        gh = self.root / "bin/gh"
        gh.write_text(f"#!{sys.executable}\n" + r'''
import json, os, pathlib, subprocess, sys
root = pathlib.Path(os.environ["EMIT_TEST_ROOT"])
data = json.loads((root / "fixture.json").read_text())
args = sys.argv[1:]
assert args[0] == "api", args
endpoint = args[1]
if endpoint.endswith("/zip"):
    (root / "downloaded").write_text(endpoint)
    sys.stdout.buffer.write((root / "artifact.zip").read_bytes())
    sys.exit(0)
if endpoint == "repos/owner/repo":
    response = {"id": 42}
elif endpoint.startswith("repos/owner/repo/actions/artifacts?"):
    response = {"artifacts": data["artifacts"]}
elif endpoint.startswith("repos/owner/repo/actions/runs/"):
    run = endpoint.rsplit("/", 1)[1]
    (root / "queried-run").write_text(run)
    if data.get("api_failure"):
        sys.exit(1)
    response = {"event": data.get("events", {}).get(run)}
else:
    raise AssertionError(endpoint)
expression = args[args.index("--jq") + 1]
result = subprocess.run(["jq", "-r", expression], input=json.dumps(response), text=True)
sys.exit(result.returncode)
''')
        gh.chmod(0o755)
        self.env = os.environ | {
            "PATH": str(self.root / "bin") + os.pathsep + os.environ["PATH"],
            "BACKPLANE_EMIT_REPO": "owner/repo",
            "BACKPLANE_EMIT_REMOTE": "1",
            "EMIT_TEST_ROOT": str(self.root),
        }
        self.output = self.root / "out.c"
        self.output.write_text("existing output")

    def fetch(self, artifacts, events=None, api_failure=False, bad_size=False):
        (self.root / "fixture.json").write_text(json.dumps({
            "artifacts": artifacts, "events": events or {}, "api_failure": api_failure,
        }))
        with zipfile.ZipFile(self.root / "artifact.zip", "w") as archive:
            archive.writestr("key.c", "trusted C\n")
            archive.writestr("key.ok", "1" if bad_size else "10")
        return subprocess.run(
            ["sh", str(self.root / "scripts/emit-fetch.sh"), "key", str(self.output)],
            env=self.env, capture_output=True, text=True,
        )

    def rejected(self, artifacts, **kwargs):
        result = self.fetch(artifacts, **kwargs)
        self.assertNotEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.output.read_text(), "existing output")
        self.assertFalse((self.root / "downloaded").exists())

    def test_accepts_main_push(self):
        result = self.fetch([artifact()], {"77": "push"})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.output.read_text(), "trusted C\n")
        self.assertEqual((self.root / "queried-run").read_text(), "77")

    def test_rejects_same_repository_pr_branch_with_forged_key(self):
        self.rejected([artifact(branch="unreviewed")], events={"77": "pull_request"})

    def test_rejects_non_main_push(self):
        self.rejected([artifact(branch="unreviewed")], events={"77": "push"})

    def test_rejects_fork_main(self):
        self.rejected([artifact(repository=99)], events={"77": "push"})

    def test_rejects_expired_main(self):
        self.rejected([artifact(expired=True)], events={"77": "push"})

    def test_skips_newer_unreviewed_artifact(self):
        result = self.fetch([artifact(branch="unreviewed", artifact_id=902, run=78),
                             artifact()], {"77": "push", "78": "pull_request"})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.root / "downloaded").read_text().endswith("/901/zip"))
        self.assertEqual((self.root / "queried-run").read_text(), "77")

    def test_rejects_main_non_push_events(self):
        for event in ["pull_request", "pull_request_target", "workflow_dispatch", "workflow_run"]:
            with self.subTest(event=event):
                self.rejected([artifact()], events={"77": event})

    def test_rejects_unknown_event_and_api_failure(self):
        self.rejected([artifact()])
        self.rejected([artifact()], events={"77": "push"}, api_failure=True)

    def test_rejects_missing_producer_run(self):
        self.rejected([artifact(run=None)], events={"77": "push"})

    def test_rejects_missing_artifact(self):
        self.rejected([])

    def test_size_check_still_protects_existing_output(self):
        result = self.fetch([artifact()], {"77": "push"}, bad_size=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.output.read_text(), "existing output")


if __name__ == "__main__":
    unittest.main()
