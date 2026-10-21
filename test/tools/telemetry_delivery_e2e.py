#!/usr/bin/env python3
"""Telemetry-only native worker -> pinned real ingest -> temporary SQLite/report.

Uses generated credentials, loopback HTTP and temporary homes only. No hub,
provider, production request, event-log replay or product build is involved.
Run with the backend's existing Python environment (Flask/Werkzeug installed).
"""
import argparse
import base64
from datetime import datetime, timezone
import hashlib
import importlib
import io
import json
import os
from pathlib import Path
import secrets
import sqlite3
import subprocess
import sys
import tarfile
import tempfile
import threading

from flask import Flask
from werkzeug.serving import WSGIRequestHandler, make_server
from werkzeug.wrappers import Response


def check(ok, name):
    if not ok:
        raise AssertionError(name)
    print("ok " + name, flush=True)


class Quiet(WSGIRequestHandler):
    def log(self, *args, **kwargs):
        pass


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--backend", type=Path, required=True)
    parser.add_argument("--revision", required=True)
    parser.add_argument("--worker", type=Path, required=True)
    parser.add_argument("--receipt", type=Path, required=True)
    args = parser.parse_args()
    revision = subprocess.check_output(["git", "-C", str(args.backend), "rev-parse", args.revision], text=True).strip()
    worker = args.worker.resolve()
    with tempfile.TemporaryDirectory(prefix="bp-telemetry-delivery-") as temp:
        root = Path(temp)
        backend = root / "backend"
        backend.mkdir()
        archive = subprocess.check_output(["git", "-C", str(args.backend), "archive", revision])
        with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
            tar.extractall(backend, filter="data")
        sys.path.insert(0, str(backend))
        telemetry = importlib.import_module("telemetry")
        key, admin = secrets.token_hex(32), secrets.token_hex(32)
        dbfile = root / "events.sqlite3"
        app = Flask(__name__, template_folder=str(backend / "templates"))
        app.config.update(TESTING=True, SECRET_KEY=secrets.token_hex(32),
                          TELEMETRY_DATABASE=str(dbfile), TELEMETRY_GITHUB_DOWNLOADS=False,
                          TELEMETRY_KEYS={"dev-test": {"secret": key, "channels": ["dev"], "versions": ["*"]}},
                          TELEMETRY_ADMIN_TOKEN=admin, TELEMETRY_TRUST_PROXY=False)
        telemetry.init_app(app)
        mode = None
        requests = []  # synthetic wire events in memory only, never saved
        trap = []

        def gateway(environ, start_response):
            if environ["PATH_INFO"] != "/api/v1/events":
                trap.append(environ["PATH_INFO"])
                return Response("{}", status=404)(environ, start_response)
            raw = environ["wsgi.input"].read(int(environ.get("CONTENT_LENGTH", 0)))
            environ["wsgi.input"] = io.BytesIO(raw)
            body = json.loads(raw)
            check(environ["REQUEST_METHOD"] == "POST" and not environ.get("HTTP_X_INJECTED"), "curl ignores user request/header config")
            check(len(raw) <= 16384 and 1 <= len(body["events"]) <= 50, "actual wire batch is bounded")
            requests.append(body)
            if mode is not None:
                return Response("{}", status=mode, headers={"Retry-After": "7200", "Location": "/trap"})(environ, start_response)
            return app(environ, start_response)

        server = make_server("127.0.0.1", 0, gateway, threaded=True, request_handler=Quiet)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        endpoint = f"http://127.0.0.1:{server.server_port}/api/v1/events"
        env = {k: v for k, v in os.environ.items() if not k.startswith("BACKPLANE_TELEMETRY")}
        env.update(HOME=str(root), CURL_HOME=str(root), CI="", DO_NOT_TRACK="", BACKPLANE_SANDBOX="",
                   BACKPLANE_TELEMETRY="on", BACKPLANE_TELEMETRY_TEST="1", BACKPLANE_TELEMETRY_CHANNEL="dev",
                   BACKPLANE_TELEMETRY_URL=endpoint, BACKPLANE_TELEMETRY_KID="dev-test", BACKPLANE_TELEMETRY_KEY=key,
                   BEND_NO_TELEMETRY="1")
        # The worker must ignore all of these, and must not follow redirects.
        trace = root / "forbidden.trace"
        (root / ".curlrc").write_text(f'location\nrequest = "DELETE"\nheader = "X-Injected: user-config"\ntrace = "{trace}"\n')
        now = int(datetime.now(timezone.utc).timestamp())
        day = datetime.fromtimestamp(now, timezone.utc).date().isoformat()

        def run(home, *, ver="0.11.3", action="idle", share="on", asked="1", view_day=day, overrides=None):
            home.mkdir(exist_ok=True)
            result = subprocess.run([str(worker), str(home), ver, view_day, str(now), share, asked, "0", action],
                                    env={**env, **(overrides or {})}, capture_output=True, timeout=45)
            # Never print subprocess output: failures could contain private curl bytes.
            check(result.returncode == 0, "native telemetry worker completed")
            check(key.encode() not in result.stdout + result.stderr, "credentials absent from worker output")
            check(not (home / "telemetry/request.curl").exists() and not (home / "telemetry/response.headers").exists(), "private request files removed")

        def state(home):
            return json.loads((home / "telemetry/state.json").read_text())

        def save(home, value):
            (home / "telemetry/state.json").write_text(json.dumps(value))

        def counts():
            with sqlite3.connect(dbfile) as db:
                return [dict(e=e, share=share, n=n, verified=verified, anonymous=anonymous) for e, share, n, verified, anonymous in
                        db.execute("SELECT e,share,COUNT(*),MIN(verified),SUM(install_id IS NULL) FROM events GROUP BY e,share ORDER BY e,share")]

        def count(kind, share):
            return next((r["n"] for r in counts() if r["e"] == kind and r["share"] == share), 0)

        try:
            home = root / "main"
            run(home)
            check(count("install", 1) == 1 and counts()[0]["verified"] == 1, "real ingest validates signature and 18-bit registration proof")
            check(count("active", 1) == 0, "idle worker generates no DAU")
            run(home, view_day="2099-01-01")
            check(count("active", 1) == 0, "idle date rollover generates no DAU or invalid batch")
            before_action = state(home)
            run(home, action="human")
            check(count("active", 1) == 1, "eligible action stored in SQLite")
            run(home, action="human")
            check(count("active", 1) == 1, "repeated same-day action adds no DAU")
            save(home, before_action)
            run(home, action="human")
            check(count("active", 1) == 1, "lost acknowledgement retry is deduplicated by id/day")
            check(len({r["nonce"] for r in requests}) == len(requests), "every actual attempt uses a fresh nonce")
            check((home / "telemetry").stat().st_mode & 0o777 == 0o700 and
                  (home / "telemetry/state.json").stat().st_mode & 0o777 == 0o600, "private state permissions preserved")
            before_out = state(home)
            run(home, ver="0.11.4", share="off")
            check(state(home)["id"] == "" and count("update", 0) == 1, "opt-out update stored without identity")
            save(home, before_out)
            run(home, ver="0.11.4", share="off")
            check(count("update", 0) == 2, "anonymous ambiguous retry can count twice (no dedupe identity)")
            check(all(r["anonymous"] == r["n"] for r in counts() if r["share"] == 0), "all opted-out rows are identifier-free")
            with app.app_context():
                stats = telemetry.aggregate(include_dev=True)
            check(stats["installs"]["verified"] == 1 and stats["updates"] == 2 and stats["dau"] == [{"day": day, "count": 1}], "actual report aggregates match persisted counts")
            check(len(stats["wau"]) == 1 and stats["wau"][0]["count"] == 1 and stats["by_client"] == {}, "weekly unique count without invented client-kind data")
            with app.test_client() as client:
                check(client.get("/admin/telemetry.json").status_code == 401, "report remains authenticated")
                response = client.get("/admin/telemetry.json", headers={"Authorization": "Basic " + base64.b64encode(("test:" + admin).encode()).decode()})
                check(response.status_code == 200 and response.json["dau"] == [] and response.json["updates"] == 0, "default production report excludes synthetic dev channel")
            for status in (200, 302, 408, 429, 500, 400):
                mode = status
                hh = root / f"status-{status}"
                run(hh, share="off")
                st = state(hh)
                check((len(st["queue"]) == 0 if status == 400 else len(st["queue"]) == 1 and st["next"] >= now + 7200), f"HTTP {status}: correct actual queue/backoff")
                if status != 400:
                    sent = len(requests)
                    run(hh, share="off")
                    check(len(requests) == sent, f"HTTP {status}: no retry during backoff")
            check(not trap and not trace.exists(), "no redirect or user-config credential trace")
            mode = None
            for label, overrides in (("disabled", {"BACKPLANE_TELEMETRY": "0"}), ("dnt", {"DO_NOT_TRACK": "1"}),
                                     ("ci", {"CI": "1"}), ("sandbox", {"BACKPLANE_SANDBOX": "1"}),
                                     ("missing-key", {"BACKPLANE_TELEMETRY_KEY": ""}), ("unbaked", {"BACKPLANE_TELEMETRY_TEST": ""})):
                hh, sent = root / label, len(requests)
                run(hh, action="human", overrides=overrides)
                check(not (hh / "telemetry").exists() and len(requests) == sent, f"{label}: no telemetry writes or delivery")
            args.receipt.parent.mkdir(parents=True, exist_ok=True)
            args.receipt.write_text(json.dumps({"backend_revision": revision,
                "backend_module_sha256": hashlib.sha256((backend / "telemetry.py").read_bytes()).hexdigest(),
                "worker_sha256": hashlib.sha256(worker.read_bytes()).hexdigest(),
                "scope": "telemetry-only native worker; generated dev key; temporary DB; no product/hub/UI dispatch validation",
                "counts": counts(), "dau": stats["dau"], "wau": stats["wau"], "attempts": len(requests),
                "anonymous_retry_duplicates": True, "passed": True}, indent=2) + "\n")
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=5)


if __name__ == "__main__":
    main()
