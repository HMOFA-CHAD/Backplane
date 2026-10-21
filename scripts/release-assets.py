#!/usr/bin/env python3
"""Collect/verify immutable candidate bytes. Does not certify product gates or publish."""
import argparse
import gzip
import io
import posixpath
import tarfile
import hashlib
import json
import os
from pathlib import Path
import re
import sys
import zipfile

SOURCE_RE = re.compile(r"[0-9a-f]{40}")
TAG_RE = re.compile(r"v(0|[1-9][0-9]{0,3})\.(0|[1-9][0-9]{0,3})\.(0|[1-9][0-9]{0,3})(-nightly\.[0-9]{8}\.[1-9][0-9]*)?")

# Coverage is independent of archive format and producer implementation. A local
# Linux desktop receipt cannot stand in for another desktop, web, or mobile row.
RELEASE_TARGETS = {
    "linux-x64": "desktop", "linux-arm64": "desktop",
    "darwin-arm64": "desktop", "windows-x64": "desktop",
    "web": "web", "android": "mobile", "ios": "mobile",
}
COMMON_GATES = {"runtime", "auth-security", "product-parity",
                "response-content", "telemetry-privacy"}


def target_gates(surface):
    gates = COMMON_GATES | ({"package-identity"} if surface != "web" else set())
    return gates | ({"os-sandbox"} if surface == "desktop" else set())


def version_identity(tag):
    if not isinstance(tag, str) or not TAG_RE.fullmatch(tag):
        raise ValueError("full source commit and stable/nightly package tag required")
    if len(tag[1:]) > 40 or ("-nightly." in tag and len(tag.split("-nightly.", 1)[1]) > 24):
        raise ValueError("package version exceeds native stamp or telemetry suffix limit")
    return tag[1:], "nightly" if "-nightly." in tag else "release"


def identity(source, tag):
    if not isinstance(source, str) or not SOURCE_RE.fullmatch(source):
        raise ValueError("full source commit and stable/nightly package tag required")
    return version_identity(tag)


def coverage_plan(source, tag):
    version, channel = identity(source, tag) if source is not None else version_identity(tag)
    return {
        "schema": 1, "kind": "backplane-release-coverage",
        "sourceCommit": source, "tag": tag, "version": version, "channel": channel,
        "files": {},
        "targets": {name: {"surface": surface, "state": "pending", "artifacts": [],
                           "gates": {gate: None for gate in sorted(target_gates(surface))}}
                    for name, surface in RELEASE_TARGETS.items()},
        "scope": "Artifact and owner-receipt bindings only; root reviews actual gate scope and alone publishes. No builds or product acceptance from this template.",
    }


def bound_coverage_file(directory, name, item):
    # Do not follow manifest-controlled paths outside the candidate directory.
    if (not isinstance(name, str) or not name or "\\" in name or ":" in name
            or name.startswith("/") or any(p in ("", ".", "..") for p in name.split("/"))):
        raise ValueError("unsafe coverage file path")
    path = directory
    for part in name.split("/"):
        path = path / part
        if path.is_symlink():
            raise ValueError("coverage evidence must not use symlinks")
    if (not isinstance(item, dict) or item.get("kind") not in ("asset", "owner-receipt")
            or type(item.get("bytes")) is not int or item["bytes"] <= 0
            or not isinstance(item.get("sha256"), str)
            or not re.fullmatch(r"[0-9a-f]{64}", item["sha256"])):
        raise ValueError("invalid coverage file binding")
    targets = item.get("targets")
    if (not isinstance(targets, list) or not targets
            or not all(isinstance(t, str) and t in RELEASE_TARGETS for t in targets)
            or len(set(targets)) != len(targets)):
        raise ValueError("coverage file requires explicit target scopes")
    if not path.is_file() or item["bytes"] != path.stat().st_size or digest(path) != item["sha256"]:
        raise ValueError("coverage asset or receipt changed")


def verify_coverage(directory, manifest, source, tag):
    """Check declared coverage and immutable references, not receipt truth."""
    version, channel = identity(source, tag)
    if not isinstance(manifest, dict):
        raise ValueError("coverage manifest must be an object")
    if (manifest.get("schema"), manifest.get("kind"), manifest.get("sourceCommit"),
            manifest.get("tag"), manifest.get("version"), manifest.get("channel")) != (
            1, "backplane-release-coverage", source, tag, version, channel):
        raise ValueError("coverage source/version/channel mismatch")
    targets, files = manifest.get("targets"), manifest.get("files")
    if not isinstance(targets, dict) or set(targets) != set(RELEASE_TARGETS):
        raise ValueError("coverage requires every desktop, web and mobile target exactly once")
    if not isinstance(files, dict) or not files:
        raise ValueError("coverage requires actual asset and owner-receipt bindings")
    if not all(isinstance(name, str) for name in files) or len({name.casefold() for name in files}) != len(files):
        raise ValueError("duplicate or case-colliding coverage file paths")
    for name, item in files.items():
        bound_coverage_file(directory, name, item)
    used = set()
    for name, surface in RELEASE_TARGETS.items():
        row = targets[name]
        if not isinstance(row, dict) or row.get("surface") != surface or row.get("state") != "accepted":
            raise ValueError("target owner acceptance remains pending: " + name)
        artifacts, gates = row.get("artifacts"), row.get("gates")
        if (not isinstance(artifacts, list) or not artifacts
                or not all(isinstance(a, str) for a in artifacts)
                or len(set(artifacts)) != len(artifacts)):
            raise ValueError("target requires explicit, unique artifact references: " + name)
        if not isinstance(gates, dict) or set(gates) != target_gates(surface):
            raise ValueError("target gate coverage incomplete: " + name)
        for reference in artifacts:
            if (reference not in files or files[reference]["kind"] != "asset"
                    or name not in files[reference]["targets"]):
                raise ValueError("target artifact reference missing or wrong kind")
        for reference in gates.values():
            if (not isinstance(reference, str) or reference not in files
                    or files[reference]["kind"] != "owner-receipt"
                    or name not in files[reference]["targets"]):
                raise ValueError("target gate requires an actual owner-receipt reference")
        used.update(artifacts)
        used.update(gates.values())
    if used != set(files):
        raise ValueError("unreferenced coverage file binding")


def check_bake(env, channel):
    # Validate presence/format only. Actual server/key agreement is an ingest gate.
    # Unbaked CI never calls this release-only preflight; development generators
    # retain their intentionally empty shared-client defaults.
    if env.get("BACKPLANE_GOOGLE_BAKE") != "1":
        raise ValueError("final release compile requires shared Google bake enabled")
    if not all(env.get(name, "").strip() for name in
               ("BACKPLANE_GOOGLE_CLIENT_ID", "BACKPLANE_GOOGLE_CLIENT_SECRET")):
        raise ValueError("final release compile requires shared Google client input pair")
    if env.get("BACKPLANE_TELEMETRY_BAKE") != "1":
        raise ValueError("final release compile requires telemetry BAKE1")
    if env.get("BACKPLANE_TELEMETRY_URL") != "https://backplane.works/api/v1/events":
        raise ValueError("approved telemetry endpoint input missing or different")
    if not re.fullmatch(r"rel-[a-z0-9-]{1,28}", env.get("BACKPLANE_TELEMETRY_KID", "")):
        raise ValueError("release telemetry KID missing or invalid")
    if not re.fullmatch(r"[0-9a-f]{64}", env.get("BACKPLANE_TELEMETRY_KEY", "")):
        raise ValueError("release telemetry KEY missing or invalid")
    if env.get("BACKPLANE_TELEMETRY_CHANNEL", channel) != channel:
        raise ValueError("telemetry channel does not match immutable version")


def digest(path):
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


# Electron candidate input is a root-selected index of producer archives and
# receipts, not an instruction to build, install, sign or publish anything.
FONT_EXT = {".ttf", ".otf", ".ttc", ".otc", ".woff", ".woff2", ".dfont", ".pfb", ".pfa"}
FONT_MAGIC = (b"wOFF", b"wOF2", b"OTTO", b"ttcf", b"\x00\x01\x00\x00", b"%!PS-AdobeFont")
PRIVATE_NAMES = {"bp_google.h", "bp_telemetry.h", ".env", "signing.env"}


def safe_name(name):
    if (not isinstance(name, str) or not name or "\\" in name or ":" in name
            or name.startswith("/") or any(x in ("", ".", "..") for x in name.split("/"))
            or any(ord(c) < 32 for c in name)):
        raise ValueError("unsafe candidate member path")
    return name


def load_json(data):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError("duplicate JSON field")
            result[key] = value
        return result
    return json.loads(data, object_pairs_hook=unique)


def file_binding(directory, item):
    if not isinstance(item, dict):
        raise ValueError("producer file binding required")
    name = safe_name(item.get("path"))
    bound_coverage_file(directory, name, dict(item, kind="asset", targets=["web"]))
    return name


class Package:
    """Inspect without extracting. Preserve audited internal framework symlinks."""
    def __init__(self, path):
        self.handle = None
        self.entries = {}
        self.links = {}
        self._inventory = None
        if str(path).endswith((".zip", ".apk", ".aab", ".ipa")):
            self.handle = zipfile.ZipFile(path)
            members = [(x.filename.rstrip("/"), x.is_dir(),
                        ((x.external_attr >> 16) & 0o170000) == 0o120000, x)
                       for x in self.handle.infolist()]
            self.open_member = self.handle.open
        elif str(path).endswith(".tar.gz"):
            self.handle = tarfile.open(path, "r:gz")
            members = []
            for x in self.handle.getmembers():
                if not (x.isdir() or x.isfile() or x.issym()):
                    raise ValueError("archive contains unsupported special member")
                members.append((x.name.rstrip("/"), x.isdir(), x.issym(), x))
            self.open_member = self.handle.extractfile
        else:
            raise ValueError("unsupported producer archive format")
        folded = set()
        for name, directory, symlink, member in members:
            safe_name(name)
            if name.casefold() in folded:
                raise ValueError("duplicate or case-colliding archive member")
            folded.add(name.casefold())
            if directory:
                continue
            self.entries[name] = member
            if symlink:
                target = (member.linkname if isinstance(member, tarfile.TarInfo)
                          else self.read(name, limit=4096).decode("utf-8"))
                if not target or target.startswith("/") or "\\" in target or ":" in target:
                    raise ValueError("unsafe archive symlink")
                resolved = posixpath.normpath(posixpath.join(posixpath.dirname(name), target))
                safe_name(resolved)
                # Links may not leave their producer's top-level archive root.
                if resolved.split("/")[0] != name.split("/")[0]:
                    raise ValueError("archive symlink escapes package root")
                self.links[name] = target
        if any(name.startswith(link + "/") for link in self.links for name in self.entries):
            raise ValueError("archive member traverses a symlink parent")
        for name in self.links:
            seen = set()
            current = name
            while current in self.links:
                if current in seen:
                    raise ValueError("archive symlink cycle")
                seen.add(current)
                current = posixpath.normpath(posixpath.join(posixpath.dirname(current), self.links[current]))
            if current not in self.entries and not any(x.startswith(current + "/") for x in self.entries):
                raise ValueError("archive symlink target absent")

    def close(self):
        if self.handle:
            self.handle.close()

    def read(self, name, limit=8 * 1024 * 1024):
        if name not in self.entries or name in self.links:
            raise ValueError("required package member absent or symlinked")
        with self.open_member(self.entries[name]) as stream:
            data = stream.read(limit + 1)
        if len(data) > limit:
            raise ValueError("package metadata exceeds bounded read")
        return data

    def mode(self, name):
        member = self.entries[name]
        return (member.mode if isinstance(member, tarfile.TarInfo) else member.external_attr >> 16) & 0o777

    def inventory(self):
        if self._inventory is not None:
            return self._inventory
        result = {}
        for name in self.entries:
            parts = name.lower().split("/")
            if (Path(name).suffix.lower() in FONT_EXT or parts[-1] in PRIVATE_NAMES
                    or any(x in {"fonts", "fontconfig", "font-cache", "glyph-cache", "glyph-cache-v2", ".cache", ".git", "__pycache__"} for x in parts)
                    or parts[-1].startswith(".env.") or Path(name).suffix.lower() in {".p8", ".p12", ".pfx", ".pem", ".key", ".keystore", ".h", ".c"}):
                raise ValueError("font, cache or private compile/signing input in package")
            if name in self.links:
                result[name] = {"symlink": self.links[name]}
                continue
            member = self.entries[name]
            mode = member.mode if isinstance(member, tarfile.TarInfo) else member.external_attr >> 16
            if mode & 0o7000:
                raise ValueError("archive cannot qualify privileged sandbox ownership through mode bits")
            sha, size, prefix = hashlib.sha256(), 0, b""
            with self.open_member(self.entries[name]) as stream:
                while block := stream.read(1024 * 1024):
                    if not prefix:
                        prefix = block[:64]
                    sha.update(block)
                    size += len(block)
            if name.endswith(".gz"):
                if Path(name[:-3]).suffix.lower() in FONT_EXT:
                    raise ValueError("compressed font payload")
                with self.open_member(self.entries[name]) as stream:
                    with gzip.GzipFile(fileobj=stream) as compressed:
                        if compressed.read(64).startswith(FONT_MAGIC):
                            raise ValueError("compressed font format signature")
            if prefix.startswith(FONT_MAGIC):
                raise ValueError("font format signature in package")
            if Path(name).suffix.lower() in {".css", ".html", ".js", ".cjs", ".mjs"}:
                # Text is bounded by archive member size; inspect in chunks so a
                # huge generated bridge need not be retained as a second copy.
                with self.open_member(self.entries[name]) as stream:
                    tail = b""
                    while block := stream.read(1024 * 1024):
                        if re.search(rb"berkeley[\s_-]*mono", tail + block, re.I):
                            raise ValueError("prohibited font selection in package")
                        tail = block[-64:]
            result[name] = {"sha256": sha.hexdigest(), "bytes": size}
        self._inventory = result
        return result


def configured_service(receipt, version, channel):
    if (receipt.get("entrypoint", receipt.get("entry")) != "src/server/main.bend"
            or receipt.get("serviceVersion", receipt.get("version")) != version
            or receipt.get("versionStamp") != version
            or receipt.get("telemetryChannel") != channel):
        raise ValueError("final genuine service version/stamp/channel required")
    config = receipt.get("compileInputs", {})
    for label in ("google", "telemetry"):
        item = config.get(label, {})
        if item.get("requested") is not True or item.get("requiredInputsPresent") is not True:
            raise ValueError("final configured service requires native Google and telemetry bake")
    if config.get("telemetry", {}).get("endpoint") != "https://backplane.works/api/v1/events":
        raise ValueError("actual native compile endpoint differs from approved input")
    if (config.get("version"), config.get("versionStamp"), config.get("telemetryChannel")) != (version, version, channel):
        raise ValueError("native compile identity differs from package")


def require_signing(receipt, target, expected_signer=None):
    signing = receipt.get("signing", {})
    if target == "android":
        if (not isinstance(expected_signer, str) or not re.fullmatch(r"[0-9a-f]{64}", expected_signer)
                or signing.get("certificateSha256") != expected_signer
                or signing.get("signatureVerified") is not True or signing.get("debuggable") is not False):
            raise ValueError("explicit approved Android signer and non-debuggable Release required")
        # The existing installed cohort used a historical Debug-DN certificate.
        # Exact root-approved fingerprint continuity governs, not the DN text.
    else:
        if (not isinstance(expected_signer, str) or not re.fullmatch(r"[0-9a-f]{64}", expected_signer)
                or signing.get("certificateSha256") != expected_signer
                or signing.get("signatureVerified") is not True or signing.get("debuggable") is not False
                or not signing.get("teamId")):
            raise ValueError("verified approved iOS distribution signature required")
        products = signing.get("products", {})
        if set(products) != {"app", "island"}:
            raise ValueError("iOS app and extension signatures required")
        for key, product in products.items():
            if (product.get("signatureVerified") is not True or product.get("debuggable") is not False
                    or product.get("certificateSha256") != expected_signer or not product.get("profileUuid")
                    or product.get("bundleId") != receipt.get("package", "") + (".island" if key == "island" else "")):
                raise ValueError("iOS embedded profile/extension signature mismatch")
    number = receipt.get("buildNumber")
    if isinstance(number, bool) or not isinstance(number, (str, int)) or not re.fullmatch(r"[1-9][0-9]*", str(number)):
        raise ValueError("mobile monotonic build number required")
    if receipt.get("configuration") != "Release" or receipt.get("actualNativeVersion", receipt.get("nativeVersion")) != receipt["version"]:
        raise ValueError("mobile debug/old native version cannot be relabeled")


def desktop_acceptance(package, root, receipt, target, source, tree, version):
    freeze_ref = receipt.get("release", {}).get("freezeReceipt", {})
    freeze_path = safe_name(freeze_ref.get("path"))
    freeze = package.read(root + "/" + freeze_path)
    if hashlib.sha256(freeze).hexdigest() != freeze_ref.get("sha256") or len(freeze) != freeze_ref.get("bytes"):
        raise ValueError("desktop freeze receipt changed")
    frozen = load_json(freeze)
    policy = frozen.get("signingPolicy", {}).get(target)
    if policy not in {"required", "unsigned-portable-allowed"}:
        raise ValueError("explicit target signing policy required")
    kinds = {"signing": "desktop-signing", "sandbox": "desktop-sandbox",
             "lifecycle": "desktop-lifecycle", "runtimeAcceptance": "desktop-runtime-acceptance"}
    proofs = {}
    for key, kind in kinds.items():
        ref = receipt.get(key, {})
        name = safe_name(ref.get("path"))
        raw = package.read(root + "/" + name)
        proof = load_json(raw)
        if (hashlib.sha256(raw).hexdigest(), len(raw), ref.get("status")) != (ref.get("sha256"), ref.get("bytes"), "PASS"):
            raise ValueError("desktop acceptance reference mismatch")
        if (proof.get("schema"), proof.get("kind"), proof.get("status"), proof.get("target"), proof.get("commit"), proof.get("tree"), proof.get("version")) != (1, kind, "PASS", target, source, tree, version):
            raise ValueError("desktop target-scoped acceptance missing")
        if proof.get("payloadManifestSha256") != receipt.get("payloadManifestSha256") or proof.get("freezeReceiptSha256") != freeze_ref["sha256"]:
            raise ValueError("desktop acceptance does not bind final payload/freeze")
        proofs[key] = proof
    if not isinstance(proofs["signing"].get("signed"), bool) or policy == "required" and not proofs["signing"]["signed"]:
        raise ValueError("desktop signing disposition mismatch")
    if proofs["sandbox"].get("osEnforced") is not True or "--no-sandbox" in proofs["sandbox"].get("flags", []):
        raise ValueError("production OS sandbox remains unqualified")
    life = proofs["lifecycle"]
    if any(life.get(k) is not True for k in ("nativeChildIdentity", "authBound", "singleInstance", "reconnect")):
        raise ValueError("desktop lifecycle unqualified")
    resident = {"mode": "resident-service", "managedStop": False, "managedUpdate": False}
    lifecycle = frozen.get("lifecyclePolicy", {}).get(target)
    if lifecycle == resident:
        if receipt.get("lifecyclePolicy") != resident:
            raise ValueError("desktop resident policy differs from root freeze")
        if any(life.get(k) is not True for k in ("startup", "closePreservesService")) or any(
                life.get(k) is not False for k in ("managedStopAdvertised", "managedUpdateAdvertised")):
            raise ValueError("resident service startup/close policy unqualified")
        if life.get("windowClose") != "resident-service" or life.get("shutdown") != "unsupported":
            raise ValueError("resident service may not claim managed stop")
    elif life.get("shutdown") != ("approved-service-protocol" if target == "windows-x64" else "owned-native-child"):
        raise ValueError("desktop shutdown contract unqualified")
    if target == "windows-x64" and life.get("nativeToPosixPaths") is not True:
        raise ValueError("Windows path mapping unqualified")
    if proofs["runtimeAcceptance"].get("scope") != "desktop-release":
        raise ValueError("local synthetic runtime cannot qualify desktop release")
    payload = {}
    for name, item in package.inventory().items():
        n = name[len(root) + 1:]
        if n in {"DESKTOP.json", "MANIFEST.json", "STAGE.json"} or n.startswith("PROVENANCE/"):
            continue
        payload[n] = ({"type": "symlink", "target": item["symlink"]} if "symlink" in item else
                      dict(item, type="file", mode=package.mode(name)))
    actual = hashlib.sha256(json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()).hexdigest()
    if actual != receipt.get("payloadManifestSha256"):
        raise ValueError("actual desktop payload differs from accepted payload")


def verify_web(package, web, source, tree):
    if (web.get("schema"), web.get("kind"), web.get("sourceCommit"), web.get("sourceTree"),
            web.get("entrypoint")) != (1, "matching-generated-web", source, tree, "src/web/index.html"):
        raise ValueError("matching generated web source required")
    members = web.get("members", {})
    root = safe_name(web.get("root"))
    if "index.html" not in members or not members:
        raise ValueError("generated web index missing")
    actual = {p[len(root) + 1:]: x for p, x in package.inventory().items() if p.startswith(root + "/")}
    if actual != members:
        raise ValueError("web manifest does not match exact packaged members")
    for name in members:
        safe_name(name)
        if name.endswith((".html", ".js", ".css")) and name + ".gz" not in members:
            raise ValueError("packaged web text requires matching gzip")
        if name.endswith(".gz"):
            plain = name[:-3]
            if plain not in members:
                raise ValueError("orphan compressed web asset")
            raw = package.read(root + "/" + plain, 32 * 1024 * 1024)
            with gzip.GzipFile(fileobj=io.BytesIO(package.read(root + "/" + name, 32 * 1024 * 1024))) as stream:
                inflated = stream.read(len(raw) + 1)
            if inflated != raw:
                raise ValueError("packaged gzip differs from matching web")
    return root


def verify_target(directory, target, row, source, tree, tag):
    version, channel = identity(source, tag)
    archive_name = file_binding(directory, row.get("archive"))
    receipt_name = file_binding(directory, row.get("receipt"))
    receipt = load_json((directory / receipt_name).read_bytes())
    package = Package(directory / archive_name)
    try:
        inventory = package.inventory()
        if target == "windows-x64" and package.links:
            raise ValueError("Windows package reparse/symlink indirection refused")
        if RELEASE_TARGETS[target] == "desktop":
            root = "backplane-" + target
            suffix = ".zip" if target == "windows-x64" else ".tar.gz"
            if Path(archive_name).name != f"backplane-{tag}-{target}{suffix}":
                raise ValueError("desktop archive name differs from producer v2")
            release = receipt.get("release", {})
            if (receipt.get("schema"), receipt.get("kind"), receipt.get("target"),
                    release.get("commit"), release.get("tree"), release.get("version"),
                    release.get("tag"), release.get("channel")) != (
                    1, "backplane-electron-desktop-package", target, source, tree, version, tag, channel):
                raise ValueError("desktop DESKTOP1 frozen identity mismatch")
            if package.read(root + "/DESKTOP.json") != (directory / receipt_name).read_bytes():
                raise ValueError("exposed DESKTOP receipt differs from archive")
            outer = load_json(package.read(root + "/MANIFEST.json"))
            members = outer.get("members", outer.get("files"))
            if not member_map_matches(members, inventory, root, {root + "/MANIFEST.json"}, package):
                raise ValueError("desktop MANIFEST differs from archive")
            if not member_map_matches(receipt.get("members"), inventory, root,
                                      {root + "/MANIFEST.json", root + "/DESKTOP.json"}, package):
                raise ValueError("desktop DESKTOP member closure mismatch")
            if (receipt.get("electronVersion"), receipt.get("serviceVersion"), receipt.get("shellVersion")) != ("44.9.2", version, version):
                raise ValueError("pinned Electron and genuinely versioned shell/service required")
            if target == "darwin-arm64":
                resources = root + "/Backplane.app/Contents/Resources"
                launcher = root + "/Backplane.app/Contents/MacOS/Backplane"
            else:
                resources = root + ("/resources" if target == "windows-x64" else "/runtime/resources")
                launcher = root + ("/Backplane.exe" if target == "windows-x64" else "/backplane-open")
            service_root = resources + "/backplane-service"
            service = service_root + ("/backplane-serve.exe" if target == "windows-x64" else "/backplane-serve")
            for member in (launcher, service, service_root + "/LICENSE.Backplane"):
                if member not in inventory or member in package.links:
                    raise ValueError("actual desktop launcher/service/license missing")
            app = load_json(package.read(resources + "/app/package.json"))
            if app.get("version") != version or app.get("main") != "main.cjs":
                raise ValueError("packaged shell package.json must have actual stable version")
            for basename in ("LICENSE", "LICENSES.chromium.html"):
                if not any(p.endswith("/" + basename) and p not in package.links and inventory[p].get("bytes", 0) > 0 for p in inventory):
                    raise ValueError("Electron redistribution notices missing")
            notices = package.read(root + "/NOTICES.json")
            if hashlib.sha256(notices).hexdigest() != receipt.get("noticesManifestSha256"):
                raise ValueError("desktop notices manifest mismatch")
            build = load_json(package.read(service_root + "/BUILD.json"))
            configured_service(build, version, channel)
            if (build.get("commit", build.get("source_commit")), build.get("tree", build.get("source_tree"))) != (source, tree):
                raise ValueError("service build source mismatch")
            web_data = package.read(service_root + "/WEB.json")
            if hashlib.sha256(web_data).hexdigest() != receipt.get("webManifestSha256"):
                raise ValueError("desktop web receipt changed")
            verify_web(package, dict(load_json(web_data), root=service_root + "/web"), source, tree)
            if target == "windows-x64":
                verify_windows_members(package, service_root + "/BUILD.json", source, tree, tag)
                control = build.get("managedControl", {})
                resident = {"mode": "resident-service", "managedStop": False, "managedUpdate": False}
                if receipt.get("lifecyclePolicy") == resident:
                    if not isinstance(control, dict) or control.get("status") != "UNSUPPORTED" or control.get("protocol") is not None:
                        raise ValueError("resident Windows policy requires truthful unsupported control")
                else:
                    if (not isinstance(control, dict) or control.get("status") != "IMPLEMENTED"
                            or not control.get("protocol") or not control.get("validationReceiptSha256")):
                        raise ValueError("Windows managed service control remains unsupported")
                    name = safe_name(control.get("validationReceipt"))
                    data = package.read(service_root + "/" + name)
                    if hashlib.sha256(data).hexdigest() != control["validationReceiptSha256"]:
                        raise ValueError("Windows managed-control acceptance changed")
            desktop_acceptance(package, root, receipt, target, source, tree, version)
        else:
            if (receipt.get("schema"), receipt.get("kind"), receipt.get("target"),
                    receipt.get("sourceCommit"), receipt.get("sourceTree"), receipt.get("version"),
                    receipt.get("channel")) != (1, "backplane-target-package", receipt.get("target") if target in {"android", "ios"} else target, source, tree, version, channel):
                raise ValueError("web/mobile producer source/version/channel mismatch")
            if target == "android" and receipt.get("target") not in {"android-apk", "android-aab"}:
                raise ValueError("Android target must identify APK or AAB")
            if target == "ios" and receipt.get("target") not in {"ios-ipa", "ios-xcarchive"}:
                raise ValueError("iOS target must identify device IPA or archive")
            declared_archive = receipt.get("archive", {})
            bound = dict(row["archive"])
            bound.pop("path", None)
            declared_hash = dict(declared_archive)
            declared_hash.pop("path", None)
            declared_hash.pop("name", None)
            declared_members = receipt.get("members")
            if isinstance(declared_members, list):
                records = declared_members
                declared_members = {x["path"]: ({"symlink": x["target"]} if x.get("type") == "symlink" else
                                               {k: x[k] for k in ("sha256", "bytes")}) for x in records}
                if len(declared_members) != len(records):
                    raise ValueError("duplicate mobile producer member")
            if declared_hash != bound or inventory != declared_members:
                raise ValueError("web/mobile receipt must bind the exact archive and members")
            if target == "web":
                verify_web(package, receipt["web"], source, tree)
            else:
                bridge = safe_name(receipt.get("bridgeMember"))
                if inventory.get(bridge, {}).get("sha256") != receipt.get("bridgeSha256"):
                    raise ValueError("mobile qualified bridge mismatch")
        if target in {"android", "ios"}:
            require_signing(receipt, target, row.get("expectedSignerSha256"))
            if target == "ios" and (not row.get("expectedPackageId") or not row.get("expectedTeamId")
                                    or receipt.get("package") != row["expectedPackageId"]
                                    or receipt.get("signing", {}).get("teamId") != row["expectedTeamId"]):
                raise ValueError("iOS package must preserve root-configured public bundle/team identity")
            floor = row.get("publishedBuildFloor")
            if isinstance(floor, bool) or not isinstance(floor, (str, int)) or not re.fullmatch(r"[0-9]+", str(floor)) or int(receipt["buildNumber"]) <= int(floor):
                raise ValueError("root-observed mobile build floor required")
    finally:
        package.close()
    used = {archive_name, receipt_name}
    checksum = row.get("checksum")
    if target in {"linux-x64", "linux-arm64", "darwin-arm64", "windows-x64"} and checksum is None:
        raise ValueError("desktop producer digest sidecar required")
    if checksum is not None:
        checksum_name = file_binding(directory, checksum)
        if (directory / checksum_name).read_text().split() != [row["archive"]["sha256"], Path(archive_name).name]:
            raise ValueError("producer archive digest sidecar mismatch")
        used.add(checksum_name)
    for item in row.get("support", []):
        name = file_binding(directory, item)
        if target not in {"linux-x64", "linux-arm64", "darwin-arm64", "windows-x64"}:
            raise ValueError("unsupported extra target output")
        member = "backplane-" + target + "/" + safe_name(item.get("member", Path(name).name))
        check = Package(directory / archive_name)
        try:
            if check.read(member) != (directory / name).read_bytes():
                raise ValueError("exposed producer support receipt differs from archive")
        finally:
            check.close()
        used.add(name)
    return used


def member_map_matches(declared, inventory, root, excluded, package=None):
    if not isinstance(declared, dict):
        return False
    actual = {p: v for p, v in inventory.items() if p not in excluded}
    normalized = {}
    for name, value in declared.items():
        safe_name(name)
        path = name if name.startswith(root + "/") else root + "/" + name
        if path in normalized or not isinstance(value, dict):
            return False
        # Modes are audited by the target producer. Aggregate binds bytes/links;
        # it does not infer production sandbox/signing from executable bits.
        if value.get("type") == "symlink":
            normalized[path] = {"symlink": value.get("target")}
        else:
            normalized[path] = {k: v for k, v in value.items() if k in {"sha256", "bytes", "symlink"}}
            if package is not None and "mode" in value and (path not in inventory or value["mode"] != package.mode(path)):
                return False
    return actual == normalized


def verify_windows_members(package, build_path, source, tree, tag):
    version, channel = identity(source, tag)
    build = load_json(package.read(build_path))
    root = posixpath.dirname(build_path)
    emitted = load_json(package.read(root + "/SOURCE.json"))
    web = load_json(package.read(root + "/WEB.json"))
    if (build.get("schema"), build.get("kind"), emitted.get("schema"), emitted.get("kind")) != (
            3, "windows-service-resources", 3, "windows-service-emission"):
        raise ValueError("Windows genuine service SOURCE3/BUILD3 required")
    for r in (build, emitted):
        if (r.get("commit"), r.get("tree"), r.get("entrypoint"), r.get("target")) != (
                source, tree, "src/server/main.bend", "windows-x64"):
            raise ValueError("Windows service frozen source/entry mismatch")
        if r.get("versionStamp") != version:
            raise ValueError("Windows source stamp mismatch")
    if (emitted.get("version"), emitted.get("telemetry_channel"), build.get("serviceVersion"), build.get("telemetryChannel")) != (version, channel, version, channel):
        raise ValueError("Windows source/version/channel mismatch")
    for key, name in (("sourceReceiptSha256", "SOURCE.json"), ("webManifestSha256", "WEB.json"),
                      ("runtimeManifestSha256", "RUNTIME.json"), ("closureSha256", "CLOSURE.json")):
        if build.get(key) != hashlib.sha256(package.read(root + "/" + name)).hexdigest():
            raise ValueError("Windows raw producer receipt changed")
    configured_service(build, version, channel)
    inventory = package.inventory()
    actual = {p[len(root) + 1:]: x for p, x in inventory.items() if p.startswith(root + "/") and p != build_path}
    if (build.get("sha256") != {p: x.get("sha256") for p, x in actual.items()}
            or build.get("sizes") != {p: x.get("bytes") for p, x in actual.items()}):
        raise ValueError("Windows service resource closure mismatch")
    if build.get("roles", {}).get("service") != "backplane-serve.exe":
        raise ValueError("Windows service role mismatch")
    verify_web(package, dict(web, root=root + "/web"), source, tree)


def verify_inputs(directory, inputs, source, tag):
    version, channel = identity(source, tag)
    if (inputs.get("schema"), inputs.get("kind"), inputs.get("sourceCommit"), inputs.get("tag"),
            inputs.get("version"), inputs.get("channel")) != (1, "backplane-electron-release-inputs", source, tag, version, channel):
        raise ValueError("Electron release input identity mismatch")
    if inputs.get("rootFrozen") is not True:
        raise ValueError("root source freeze is not declared")
    tree = inputs.get("sourceTree")
    if not isinstance(tree, str) or not SOURCE_RE.fullmatch(tree):
        raise ValueError("actual full frozen source tree required")
    rows = inputs.get("targets", {})
    if set(rows) != set(RELEASE_TARGETS):
        raise ValueError("all four desktops, web, Android and iOS packages required")
    used = set()
    for target, row in rows.items():
        if not isinstance(row, dict):
            raise ValueError("target producer archive and receipt required")
        refs = verify_target(directory, target, row, source, tree, tag)
        if target == "android":
            main = load_json((directory / row["receipt"]["path"]).read_bytes())
            variants = row.get("variants", [])
            if main.get("target") != "android-apk" or not isinstance(variants, list) or len(variants) != 1:
                raise ValueError("Android requires main APK and same-build AAB variant")
            variant = variants[0]
            if variant.get("expectedSignerSha256") != row.get("expectedSignerSha256"):
                raise ValueError("Android APK/AAB approved signer differs")
            extra = verify_target(directory, target, variant, source, tree, tag)
            other = load_json((directory / variant["receipt"]["path"]).read_bytes())
            if (other.get("target") != "android-aab" or other.get("buildNumber") != main.get("buildNumber")
                    or other.get("bridgeSha256") != main.get("bridgeSha256") or extra & refs):
                raise ValueError("Android APK/AAB tuple differs")
            refs |= extra
        if target == "ios":
            primary = load_json((directory / row["receipt"]["path"]).read_bytes())
            if primary.get("target") != "ios-ipa":
                raise ValueError("iOS release row requires actual device IPA")
        for binding in row.get("evidence", []):
            name = file_binding(directory, binding)
            if not name.endswith(".json") or binding["bytes"] > 8 * 1024 * 1024:
                raise ValueError("additional producer evidence must be bounded JSON")
            load_json((directory / name).read_bytes())
            if name in refs:
                raise ValueError("duplicate producer evidence reference")
            refs.add(name)
        if used & refs:
            raise ValueError("producer artifacts may not substitute for another target")
        used |= refs
    return used


def candidate_members(directory):
    found = set()
    for p in directory.rglob("*"):
        if p.is_symlink():
            raise ValueError("indirect candidate member")
        if p.is_dir():
            continue
        if not p.is_file():
            raise ValueError("nonregular candidate member")
        found.add(safe_name(p.relative_to(directory).as_posix()))
    if len({n.casefold() for n in found}) != len(found):
        raise ValueError("case-colliding candidate files")
    return found


def collect(directory, source, tag, manifest, **unused):
    inputs = load_json(manifest.read_bytes())
    files = verify_inputs(directory, inputs, source, tag)
    if manifest.resolve().parent != directory.resolve() or manifest.name != "release-inputs.json":
        raise ValueError("canonical in-directory release-inputs.json required")
    files.add(manifest.name)
    if candidate_members(directory) != files:
        raise ValueError("unexpected or missing candidate files")
    version, channel = identity(source, tag)
    output = {"schema": 2, "kind": "backplane-electron-candidate", "sourceCommit": source,
              "sourceTree": inputs["sourceTree"], "tag": tag, "version": version, "channel": channel,
              "buildRunId": os.environ.get("GITHUB_RUN_ID"),
              "publicAssets": [inputs["targets"][t]["archive"]["path"] for t in RELEASE_TARGETS],
              "files": {n: {"sha256": digest(directory / n), "bytes": (directory / n).stat().st_size} for n in sorted(files)},
              "productAcceptance": "PENDING all seven target-scoped owner gates; root alone publishes"}
    for name in ("release-assets.json", "SHA256SUMS", "release-coverage.json"):
        if (directory / name).exists():
            raise ValueError("collection must not overwrite inventory or acceptance")
    (directory / "release-assets.json").write_text(json.dumps(output, indent=2) + "\n")
    (directory / "release-coverage.json").write_text(json.dumps(coverage_plan(source, tag), indent=2) + "\n")
    names = files | {"release-assets.json", "release-coverage.json"}
    (directory / "SHA256SUMS").write_text("".join(f"{digest(directory / n)}  {n}\n" for n in sorted(names)))
    verify(directory, source, tag)


def verify(directory, source, tag, run_id=None):
    version, channel = identity(source, tag)
    manifest = load_json((directory / "release-assets.json").read_bytes())
    if (manifest.get("schema"), manifest.get("kind"), manifest.get("sourceCommit"), manifest.get("tag"),
            manifest.get("version"), manifest.get("channel")) != (2, "backplane-electron-candidate", source, tag, version, channel):
        raise ValueError("Electron candidate inventory identity mismatch")
    if run_id is not None and manifest.get("buildRunId") != run_id:
        raise ValueError("candidate collection run mismatch")
    inputs = load_json((directory / "release-inputs.json").read_bytes())
    names = verify_inputs(directory, inputs, source, tag) | {"release-inputs.json"}
    if manifest.get("sourceTree") != inputs["sourceTree"] or set(manifest.get("files", {})) != names:
        raise ValueError("candidate inventory/source tree mismatch")
    if manifest.get("publicAssets") != [inputs["targets"][t]["archive"]["path"] for t in RELEASE_TARGETS]:
        raise ValueError("public asset list must include every target primary package")
    for n in names:
        if manifest["files"][n] != {"sha256": digest(directory / n), "bytes": (directory / n).stat().st_size}:
            raise ValueError("candidate bytes changed after collection")
    expected = names | {"release-assets.json", "release-coverage.json", "SHA256SUMS"}
    if candidate_members(directory) != expected:
        raise ValueError("unexpected or indirect candidate member")
    lines = (directory / "SHA256SUMS").read_text().splitlines()
    hashes = {}
    for line in lines:
        sha, name = line.split("  ", 1)
        if name in hashes or name not in expected - {"SHA256SUMS"} or not re.fullmatch(r"[0-9a-f]{64}", sha):
            raise ValueError("invalid aggregate checksum member")
        hashes[name] = sha
    if set(hashes) != expected - {"SHA256SUMS"} or any(digest(directory / n) != h for n, h in hashes.items()):
        raise ValueError("aggregate checksum inventory mismatch")


def verify_final(directory, qualification, manifest, source, tag):
    if tag != "v0.12.0":
        raise ValueError("current stable publication target is v0.12.0")
    verify(directory, source, tag)
    coverage = load_json(manifest.read_bytes())
    verify_coverage(qualification, coverage, source, tag)
    inputs = load_json((directory / "release-inputs.json").read_bytes())
    for target, row in inputs["targets"].items():
        archives = [row["archive"], *[v["archive"] for v in row.get("variants", [])]]
        bound = [coverage["files"][n] for n in coverage["targets"][target]["artifacts"]]
        if not all(any((x["sha256"], x["bytes"]) == (archive["sha256"], archive["bytes"]) for x in bound) for archive in archives):
            raise ValueError("accepted target does not bind sealed candidate archive: " + target)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["collect", "verify", "check-bake", "coverage-plan", "check-coverage", "check-inputs", "check-windows-resources", "check-final"])
    parser.add_argument("--directory", type=Path)
    parser.add_argument("--source")
    parser.add_argument("--tag", required=True)
    parser.add_argument("--run-id")
    parser.add_argument("--manifest", type=Path)
    parser.add_argument("--archive", type=Path)
    parser.add_argument("--tree")
    parser.add_argument("--qualification-directory", type=Path)
    args = parser.parse_args()
    try:
        if args.command == "coverage-plan":
            result = json.dumps(coverage_plan(args.source, args.tag), indent=2) + "\n"
            if args.manifest:
                with args.manifest.open("x") as output:
                    output.write(result)
            else:
                print(result, end="")
            return
        _, channel = identity(args.source, args.tag)
        if args.command == "check-bake":
            check_bake(os.environ, channel)
        elif args.command == "check-windows-resources":
            if args.archive is None or not args.tree or not SOURCE_RE.fullmatch(args.tree):
                raise ValueError("Windows resource archive and full tree required")
            package = Package(args.archive)
            try:
                package.inventory()
                verify_windows_members(package, "backplane-service/BUILD.json", args.source, args.tree, args.tag)
            finally:
                package.close()
        elif args.command == "check-final":
            if args.directory is None or args.qualification_directory is None or args.manifest is None:
                raise ValueError("candidate and qualification directories/manifest required")
            verify_final(args.directory, args.qualification_directory, args.manifest, args.source, args.tag)
        elif args.command in ("check-inputs", "check-coverage", "collect"):
            if args.directory is None or args.manifest is None:
                raise ValueError("candidate directory and explicit manifest required")
            if args.command == "check-coverage":
                verify_coverage(args.directory, load_json(args.manifest.read_bytes()), args.source, args.tag)
            elif args.command == "check-inputs":
                verify_inputs(args.directory, load_json(args.manifest.read_bytes()), args.source, args.tag)
            else:
                collect(args.directory, args.source, args.tag, args.manifest)
        else:
            if args.directory is None:
                raise ValueError("candidate directory required")
            verify(args.directory, args.source, args.tag, args.run_id)
    except (ValueError, KeyError, TypeError, AttributeError, OSError, EOFError, zipfile.BadZipFile, tarfile.TarError) as error:
        parser.exit(1, f"release-assets: {error}\n")
    print("PASS candidate inputs/bytes only; root must review actual gate evidence before publication")


if __name__ == "__main__":
    main()
