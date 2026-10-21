#!/usr/bin/env python3
"""Run the pinned Bend native emitter with Backplane's bounded ID patch.

The ordinary installed Bend still owns checking, proofs and JavaScript. Only
C emission uses this source copy; its Apache-2.0 license is retained in cache.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
import tempfile
import urllib.request


ROOT = Path(__file__).resolve().parent.parent
VERSION = "2.0.36"
SOURCE_URL = f"https://codeload.github.com/bendlang/bend/tar.gz/refs/tags/v{VERSION}"
SOURCE_SHA256 = "cbcd6f4b75897a05065872efac9b8d43595a467118331461eb1b92429b9e1689"
COMP_SHA256 = "4e5ee824d2624eb8eb3ba408fd99671239e72759371e562f1a83d50bb614649a"
PATCH = ROOT / "patches/bend-native-ids.patch"
MAX_ARCHIVE_BYTES = 128 * 1024 * 1024


def digest(path: Path) -> str:
    """Hash a file without reading the full archive or executable into RAM."""
    with path.open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


def files(root: Path) -> dict[str, str]:
    """Identify every retained compiler, Base, effect and license input."""
    return {str(p.relative_to(root)): digest(p) for p in sorted(root.rglob("*"))
            if p.is_file() and p.name != "native-compiler.json"}


def valid(root: Path, patch_hash: str) -> bool:
    """Reuse only a complete cache whose inputs still match its receipt."""
    try:
        receipt = json.loads((root / "native-compiler.json").read_text())
        return (receipt["source"] == SOURCE_SHA256
                and receipt["patch"] == patch_hash
                and receipt["files"] == files(root))
    except (OSError, ValueError, KeyError, TypeError):
        return False


def download(path: Path) -> None:
    """Fetch one size-bounded, checksum-pinned source archive."""
    size = 0
    with urllib.request.urlopen(SOURCE_URL, timeout=60) as response, path.open("wb") as out:
        while chunk := response.read(1024 * 1024):
            size += len(chunk)
            if size > MAX_ARCHIVE_BYTES:
                raise ValueError("Bend source archive exceeds 128 MiB")
            out.write(chunk)
    if digest(path) != SOURCE_SHA256:
        raise ValueError("Bend source archive SHA-256 mismatch")


def prepare(cache: Path, archive: Path | None = None) -> Path:
    """Atomically stage verified upstream source plus the reviewed patch."""
    patch_hash = digest(PATCH)
    target = cache / f"{VERSION}-{patch_hash[:16]}"
    if valid(target, patch_hash):
        return target
    if target.exists():
        raise ValueError(f"modified or incomplete compiler cache: remove {target} and retry")
    cache.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".stage-", dir=cache) as staging:
        stage = Path(staging)
        source = stage / "source.tar.gz"
        if archive is None:
            download(source)
        else:
            if digest(archive) != SOURCE_SHA256:
                raise ValueError("Bend source archive SHA-256 mismatch")
            shutil.copyfile(archive, source)
        prefix = f"bend-{VERSION}/"
        with tarfile.open(source, "r:gz") as tar:
            members = [m for m in tar.getmembers()
                       if m.name.startswith(prefix + "bend2/")
                       or m.name in (prefix + "LICENSE", prefix + "NOTICE")]
            tar.extractall(stage, members=members, filter="data")
        tree = stage / f"bend-{VERSION}"
        if digest(tree / "bend2/comp.ts") != COMP_SHA256:
            raise ValueError("Bend emitter does not match the pinned source")
        subprocess.run(["patch", "-t", "-N", "-F", "0", "-p1",
                        "-i", str(PATCH)], cwd=tree, check=True, stdout=sys.stderr)
        receipt = {"version": VERSION, "source": SOURCE_SHA256,
                   "patch": patch_hash, "files": files(tree)}
        (tree / "native-compiler.json").write_text(json.dumps(receipt, sort_keys=True) + "\n")
        try:
            tree.rename(target)
        except OSError:
            if not valid(target, patch_hash):
                raise
    return target


def metadata(tree: Path, out: Path, bun: str) -> None:
    """Retain native toolchain identity, upstream license and local patch."""
    out.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(tree / "LICENSE", out / "LICENSE")
    shutil.copyfile(PATCH, out / PATCH.name)
    record = {"bend": VERSION, "source_url": SOURCE_URL,
              "source_sha256": SOURCE_SHA256, "patch_sha256": digest(PATCH),
              "license_sha256": digest(tree / "LICENSE"),
              "bun": subprocess.check_output([bun, "--version"], text=True).strip(),
              "bun_sha256": digest(Path(bun)), "function_id_bits": 20,
              "constructor_id_bits": 16, "heap_location_bits": 40}
    (out / "native-compiler.json").write_text(json.dumps(record, indent=2) + "\n")


def verify_metadata(out: Path) -> None:
    """Check transferred emitter provenance without needing the emitting Bun."""
    record = json.loads((out / "native-compiler.json").read_text())
    expected = {"bend": VERSION, "source_url": SOURCE_URL,
                "source_sha256": SOURCE_SHA256, "patch_sha256": digest(PATCH),
                "function_id_bits": 20, "constructor_id_bits": 16,
                "heap_location_bits": 40}
    if (any(record.get(k) != value for k, value in expected.items())
            or record.get("license_sha256") != digest(out / "LICENSE")
            or digest(out / PATCH.name) != digest(PATCH)):
        raise ValueError(f"prebuilt native compiler provenance mismatch: {out}")


def main() -> None:
    """Prepare the native compiler or emit C using its unchanged CLI."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", nargs="?")
    parser.add_argument("-o", "--output")
    parser.add_argument("--prepare", action="store_true")
    parser.add_argument("--metadata", type=Path)
    parser.add_argument("--verify-metadata", type=Path)
    args = parser.parse_args()
    if args.verify_metadata:
        verify_metadata(args.verify_metadata)
        return
    if not args.prepare and (not args.source or not args.output or not args.output.endswith(".c")):
        parser.error("native emission requires SOURCE -o OUTPUT.c")
    bun = shutil.which("bun")
    if bun is None:
        parser.error("Bun is required for the pinned native emitter (CI uses Bun 1.4.3)")
    cache = Path(os.environ.get("XDG_CACHE_HOME", str(Path.home() / ".cache")))
    tree = prepare(cache / "backplane-bend/compiler")
    if args.metadata:
        metadata(tree, args.metadata, bun)
    if args.prepare:
        print(tree)
        return
    print(f"native emitter: Bend {VERSION}, 20-bit function IDs, patch {digest(PATCH)[:16]}",
          file=sys.stderr)
    os.execv(bun, [bun, str(tree / "bend2/main.ts"), args.source, "-o", args.output])


if __name__ == "__main__":
    main()
