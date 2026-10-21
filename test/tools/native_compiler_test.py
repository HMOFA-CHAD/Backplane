"""Check the actual patched emitter's ID bounds and native term ABI."""

import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("native_compiler", ROOT / "scripts/native-compiler.py")
assert SPEC is not None and SPEC.loader is not None
COMPILER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(COMPILER)


class NativeCompilerTest(unittest.TestCase):
    """Use upstream source plus the real patch, not a copied implementation."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.bun = shutil.which("bun")
        cls.cc = shutil.which(os.environ.get("CC", "clang"))
        if cls.bun is None or cls.cc is None:
            raise RuntimeError("native compiler tests require Bun and clang")
        cache = Path(os.environ.get("XDG_CACHE_HOME", str(Path.home() / ".cache")))
        cls.tree = COMPILER.prepare(cache / "backplane-bend/compiler")

    def test_cache_rejects_corruption_and_bad_archive(self) -> None:
        patch_hash = COMPILER.digest(COMPILER.PATCH)
        self.assertTrue(COMPILER.valid(self.tree, patch_hash))
        with patch.object(COMPILER, "download", side_effect=AssertionError("network")):
            self.assertEqual(COMPILER.prepare(self.tree.parent), self.tree)
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            broken = root / "broken"
            broken.mkdir()
            shutil.copyfile(self.tree / "native-compiler.json", broken / "native-compiler.json")
            self.assertFalse(COMPILER.valid(broken, patch_hash))
            archive = root / "wrong.tar.gz"
            archive.write_bytes(b"wrong source")
            with self.assertRaisesRegex(ValueError, "SHA-256 mismatch"):
                COMPILER.prepare(root / "cache", archive)

    def test_packaged_provenance_keeps_license_patch_and_bun_identity(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp)
            COMPILER.metadata(self.tree, out, self.bun)
            self.assertEqual((out / "LICENSE").read_bytes(), (self.tree / "LICENSE").read_bytes())
            self.assertEqual((out / COMPILER.PATCH.name).read_bytes(), COMPILER.PATCH.read_bytes())
            record = json.loads((out / "native-compiler.json").read_text())
            self.assertEqual(record["source_sha256"], COMPILER.SOURCE_SHA256)
            self.assertEqual(record["patch_sha256"], COMPILER.digest(COMPILER.PATCH))
            self.assertEqual(record["bun_sha256"], COMPILER.digest(Path(self.bun)))
            self.assertEqual(record["function_id_bits"], 20)
            COMPILER.verify_metadata(out)
            # A receiving compile host need not have the emitting Bun installed.
            subprocess.run([sys.executable, str(ROOT / "scripts/native-compiler.py"),
                            "--verify-metadata", str(out)], env=dict(os.environ, PATH=""),
                           check=True, timeout=15)
            record["function_id_bits"] = 16
            (out / "native-compiler.json").write_text(json.dumps(record))
            with self.assertRaisesRegex(ValueError, "provenance mismatch"):
                COMPILER.verify_metadata(out)

    def test_constructor_and_function_identifier_bounds(self) -> None:
        source = (self.tree / "bend2/comp.ts").read_text()
        code = source[source.index("  const defs = [[...cids.keys()]"):source.index("  const resw =")]
        # Execute the actual emitter's table allocation with controlled sizes.
        probe = """
const cid_mac = k => k;
const die = message => { throw Error(message); };
function emit(constructors, functions) {
  const cids = new Map(Array.from({length:constructors}, (_,i)=>['C'+i,0]));
  const entries = Array.from({length:functions}, (_,i)=>({fid:'F'+i}));
CODE
  return defs;
}
const assert = (b, name) => { if(!b) throw Error(name); };
assert(emit(1,69676).includes('#define F65536 65536'), 'app crosses old limit');
assert(emit(65536,0).includes('#define C65535 65535'), 'constructor boundary');
assert(emit(0,1048574).at(-1)==='#define FID_ENTER 1048575','function boundary');
for(const [c,f,want] of [[65537,0,'constructor'],[0,1048575,'function']]) {
  let error=''; try { emit(c,f); } catch(e) { error=e.message; }
  assert(error.includes(want+' id over'), 'overflow must be explicit');
}
console.log('ok native ID table bounds');
""".replace("CODE", code)
        subprocess.run([self.bun, "--eval", probe], check=True, timeout=60)

    def test_native_term_bits_and_original_small_id_layout(self) -> None:
        with tempfile.TemporaryDirectory(dir=ROOT / "build") as tmp:
            root = Path(tmp)
            program = root / "tiny.bend"
            emitted = root / "tiny.c"
            program.write_text('import Base\ndef main() -> IO(Unit):\n  IO.print("ok native emitter")\n')
            subprocess.run([self.bun, str(self.tree / "bend2/main.ts"), str(program),
                            "-o", str(emitted)], check=True, timeout=60)
            source = emitted.read_text()
            constants = source[source.index("#define TAG_PAK"):source.index("#define ERR_RING")]
            terms = source[source.index("#define term_make"):source.index("INLINE bool term_triv")]
            oracle = root / "oracle.c"
            oracle.write_text("""
#include <stdint.h>
#include <stdbool.h>
#include <assert.h>
#include <stdio.h>
typedef uint64_t u64;
typedef uint32_t u32;
typedef u64 Term;
#define INLINE static inline
""" + constants + terms + """
int main(void) {
  const u64 ids[] = {0,1,65535,65536,69677,1048575};
  const u64 locs[] = {0,1,0x123456789aull,LOC_MASK};
  for(u64 tag=1;tag<=6;tag++) for(unsigned i=0;i<6;i++) for(unsigned j=0;j<4;j++) {
    Term t=term_make(tag,ids[i],locs[j]);
    assert(term_tag(t)==tag && term_aux(t)==ids[i] && term_loc(t)==locs[j]);
    assert(!term_rfc(t));
    assert(term_tag(t|RFC_BIT)==tag && term_aux(t|RFC_BIT)==ids[i]);
    assert(term_loc(t|RFC_BIT)==locs[j] && term_rfc(t|RFC_BIT));
    if(ids[i]<=65535) assert(t==((tag<<56)|(ids[i]<<40)|locs[j]));
  }
  assert(term_tag(term_blk(false,4,23))==TAG_BUF);
  assert(term_tag(term_blk(true,4,23))==TAG_ARR);
  assert(term_loc(term_blk(true,4,23))==23);
  puts("ok native term ID/location/reference-count boundaries and old ABI");
}
""")
            binary = root / "oracle"
            subprocess.run([self.cc, "-std=c11", "-Wall", "-Wextra", "-Werror",
                            str(oracle), "-o", str(binary)], check=True, timeout=60)
            subprocess.run([str(binary)], check=True, timeout=10)
            # Also compile and execute the complete emitted runtime.
            binary = root / "tiny"
            subprocess.run([self.cc, "-O1", str(emitted), "-lpthread", "-lm", "-o", str(binary)],
                           check=True, timeout=60)
            result = subprocess.run([str(binary), "--threads", "2", "--gpu", "off"],
                                    check=True, capture_output=True, text=True, timeout=15)
            self.assertIn("ok native emitter", result.stdout)
            # A split/prebuilt compile must carry its emitting toolchain's
            # receipt, and must not need Bun on the receiving compile host.
            prebuilt = root / f"prebuilt-{root.name}"
            work = ROOT / "build/cc" / prebuilt.name
            work.mkdir(parents=True)
            self.addCleanup(shutil.rmtree, work)
            shutil.copyfile(emitted, work / "all.c")
            meta = work / "compiler"
            COMPILER.metadata(self.tree, meta, self.bun)
            record = json.loads((meta / "native-compiler.json").read_text())
            record["source_sha256"] = "wrong"
            (meta / "native-compiler.json").write_text(json.dumps(record))
            blocked = root / "no-bun"
            blocked.mkdir()
            (blocked / "bun").write_text("#!/bin/sh\nexit 97\n")
            (blocked / "bun").chmod(0o755)
            env = dict(os.environ, PATH=f"{blocked}{os.pathsep}{os.environ['PATH']}",
                       CC=self.cc, BACKPLANE_PREBUILT="1",
                       BACKPLANE_CPUS="", BACKPLANE_UNITS="1", BACKPLANE_JOBS="1",
                       BACKPLANE_CFLAGS="-O1", BACKPLANE_GOOGLE_BAKE="0",
                       BACKPLANE_OBJ_CACHE="0", BACKPLANE_EMIT_CACHE="0")
            command = ["sh", "scripts/build-app.sh", str(program), str(prebuilt)]
            rejected = subprocess.run(command, cwd=ROOT, env=env, capture_output=True,
                                      text=True, timeout=60)
            self.assertNotEqual(rejected.returncode, 0)
            self.assertIn("provenance mismatch", rejected.stdout + rejected.stderr)
            COMPILER.metadata(self.tree, meta, self.bun)
            subprocess.run(command, cwd=ROOT, env=env, check=True,
                           capture_output=True, text=True, timeout=60)
            result = subprocess.run([str(prebuilt), "--gpu", "off"], check=True,
                                    capture_output=True, text=True, timeout=15)
            self.assertIn("ok native emitter", result.stdout)


if __name__ == "__main__":
    unittest.main()
