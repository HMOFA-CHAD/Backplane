// Native links are shipped as C. The JS twin uses the same deadline and
// preserves every byte when a response head shares a read with a CBOR frame.
function link_connect(host, port, ms, k) {
  const sys = io_sys();
  const at = performance.now() + Number(ms);
  let address = host;
  // Bend's JS runner polls synchronously; a Node DNS callback cannot wake
  // its parked work. Use the platform resolver as a bounded subprocess in
  // this quick-check twin. The native effect resolves off the event loop.
  if (!/^\d+\.\d+\.\d+\.\d+$/.test(host)) {
    try {
      const exec = require("node:child_process").execFileSync;
      const text = sys.mac
        ? exec("dscacheutil", ["-q", "host", "-a", "name", host], { timeout: Number(ms), encoding: "utf8" })
        : exec("getent", ["ahostsv4", host], { timeout: Number(ms), encoding: "utf8" });
      const match = text.match(/\b\d+\.\d+\.\d+\.\d+\b/);
      if (!match) return io_fail(113);
      address = match[0];
    } catch (_) { return io_fail(113); }
  }
  if (performance.now() >= at) return io_fail(110);
  const addr = io_addr(address, Number(port));
  if (addr === null) return io_fail(22);
  const fd = sys.socket(2, 1, 0);
  if (fd < 0) return io_fail(sys.errno());
  const end = (code) => {
    if (code) { sys.close(fd); return io_fail(code); }
    return io_done(fd);
  };
  const go = () => {
    if (performance.now() >= at) return end(110);
    const error = new Int32Array([0]);
    const len = new Uint32Array([4]);
    const result = sys.getsockopt(fd, sys.mac ? 0xffff : 1, sys.mac ? 0x1007 : 4, sys.ptr(error), sys.ptr(len));
    return end(result < 0 ? sys.errno() : error[0]);
  };
  const flags = sys.fcntl(fd, 4, sys.fcntl(fd, 3, 0) | (sys.mac ? 4 : 0x800));
  if (flags < 0) return end(sys.errno());
  const result = sys.connect(fd, sys.ptr(addr), 16);
  if (result >= 0) return end(0);
  const code = sys.errno();
  if (code !== (sys.mac ? 36 : 115)) return end(code);
  io_park_on(fd, true, k, go, at);
  return undefined;
}

function link_poll(socket, ms, k) {
  const sys = io_sys();
  const buf = new Uint8Array(65536);
  const at = performance.now() + Number(ms);
  const list = (n) => {
    let xs = { $: "Nil" };
    for (let i = n; i > 0; i--) xs = { $: "Con", head: buf[i - 1], tail: xs };
    return xs;
  };
  const go = () => {
    const n = Number(sys.recv(socket, sys.ptr(buf), buf.length, 0));
    if (n >= 0) return io_tup(socket, io_done({ $: "Some", value: list(n) }));
    const code = sys.errno();
    if (code !== (sys.mac ? 35 : 11)) return io_tup(socket, io_fail(code));
    if (performance.now() >= at) return io_tup(socket, io_done({ $: "None" }));
    io_park_on(socket, false, k, go, at);
    return undefined;
  };
  return go();
}
