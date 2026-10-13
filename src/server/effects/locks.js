// The Bun hub twin uses the same POSIX flock as the native hub. Imports are
// lazy so a web/phone bundle can include these effects without touching IO.
const bp_lock_guards = new Map();
let bp_lock_ffi;
function bp_lock_posix() {
  if (!bp_lock_ffi) {
    const { dlopen } = require("bun:ffi");
    bp_lock_ffi = dlopen(process.platform === "darwin" ? "/usr/lib/libSystem.B.dylib" : "libc.so.6", {
      flock: { args: ["i32", "i32"], returns: "i32" },
    });
  }
  return bp_lock_ffi.symbols;
}
function guard_take(name, holder, home, script) {
  if (!/^[A-Za-z0-9_-]{1,64}$/.test(name) || !holder) return { $: "False" };
  const prior = bp_lock_guards.get(name);
  if (prior) return { $: prior.holder === holder ? "True" : "False" };
  const fs = require("node:fs");
  let fd;
  try {
    fd = fs.openSync(`${process.env.BACKPLANE_LOCK_DIR || "/tmp"}/bp-${name}.lock`, "a+", 0o600);
    if (bp_lock_posix().flock(fd, 2 | 4) !== 0) { fs.closeSync(fd); return { $: "False" }; }
    // fd 3 preserves the flock in the captured child. Its stdin pipe closes
    // when the hub dies; the child's cat then exits and releases its copy.
    const child = require("node:child_process").spawn("sh", ["-c", script, "sh", home, holder], { stdio: ["pipe", "ignore", "ignore", fd] });
    child.on("error", () => {}); // the parent fd still guards a failed spawn
    bp_lock_guards.set(name, { holder, fd, child });
    return { $: "True" };
  } catch {
    if (fd !== undefined) fs.closeSync(fd);
    return { $: "False" };
  }
}
function guard_drop(name, holder) {
  const g = bp_lock_guards.get(name);
  if (g && g.holder === holder) {
    bp_lock_guards.delete(name);
    g.child.stdin?.end();
    require("node:fs").closeSync(g.fd);
  }
  return { $: "Unit" };
}
io_eff(CID(Guard.take), guard_take);
io_eff(CID(Guard.drop), guard_drop);
