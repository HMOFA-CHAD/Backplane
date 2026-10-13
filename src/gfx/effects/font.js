// System fonts are native-only: the JS target keeps the bitmap font.
function font_find(pattern) {
  return io_fail(38);
}
function font_open(path, index, px) {
  return io_fail(38);
}
function font_metrics(face) {
  return { $: "Nil" };
}
function font_glyph(face, cp) {
  return { $: "Nil" };
}
function font_kern(face, a, b) {
  return 32768;
}

io_eff(CID(Font.find), font_find);
io_eff(CID(Font.open), font_open);
io_eff(CID(Font.metrics), font_metrics);
io_eff(CID(Font.glyph), font_glyph);
io_eff(CID(Font.kern), font_kern);
