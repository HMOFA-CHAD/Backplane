// Images are decoded by the native window only.
function imgfx_decode(path, maxw, maxh) {
  return io_fail(38);
}

function imgfx_tree(path, maxw, maxh) {
  return io_fail(38);
}

io_eff(CID(Imgfx.decode), imgfx_decode);
io_eff(CID(Imgfx.tree), imgfx_tree);
