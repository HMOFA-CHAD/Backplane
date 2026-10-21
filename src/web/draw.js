// The draw board: a sketch of rectangles to attach to a prompt as an image.
// Drag on empty paper to draw one (each new one takes the next colour);
// drag a rectangle's middle to move it, or one of its sides to resize it;
// click a side to type its length (a number, a unit if you like: "40 mm"),
// which then shows on the picture. Delete removes the one picked, Ctrl+Z
// takes back the last change, Esc closes. Save hands the picture (PNG) to
// `onSave`, which attaches it as a file would be.
//
// Plain DOM and canvas, no Bend: the composer's button opens it (host.js,
// [data-draw]), so it works wherever the web client does.

export const COLORS = ["#e5484d", "#f5a524", "#3e9b4f", "#2f80ed", "#8e4ec6", "#12a594", "#1f2328"];
export const W = 960, H = 600;   // the paper, in its own pixels
export const UNIT = 4;           // paper pixels per unit of a typed length
const EDGE = 7;                  // how near a side counts as on it
const MIN = 6;                   // a smaller drag is a click, not a rectangle

// which part of r a point is on: "l" "r" "t" "b" (a side), "in", or ""
export function hit(r, x, y, edge = EDGE) {
  const inX = x >= r.x - edge && x <= r.x + r.w + edge;
  const inY = y >= r.y - edge && y <= r.y + r.h + edge;
  if (!inX || !inY) return "";
  const d = [["l", Math.abs(x - r.x)], ["r", Math.abs(x - (r.x + r.w))], ["t", Math.abs(y - r.y)], ["b", Math.abs(y - (r.y + r.h))]]
    .filter(([s]) => (s === "l" || s === "r" ? y >= r.y && y <= r.y + r.h : x >= r.x && x <= r.x + r.w))
    .sort((a, b) => a[1] - b[1])[0];
  if (d && d[1] <= edge) return d[0];
  return x > r.x && x < r.x + r.w && y > r.y && y < r.y + r.h ? "in" : "";
}

// the topmost rectangle under a point, and the part of it
export function pick(rects, x, y) {
  for (let i = rects.length - 1; i >= 0; i--) {
    const part = hit(rects[i], x, y);
    if (part) return { i, part };
  }
  return null;
}

// "40", "40 mm", "12.5cm" → { n, unit }; anything else → null
export function parseLength(text) {
  const m = String(text).trim().match(/^(\d+(?:\.\d+)?)\s*([a-zA-Zµ"']{0,4})$/);
  if (!m) return null;
  const n = Number(m[1]);
  return n > 0 ? { n, unit: m[2] } : null;
}

// a rectangle with one side's length set: the side's axis takes n units,
// the opposite side stays where it was; the label is kept for the picture
export function withLength(r, side, len) {
  const px = Math.max(MIN, Math.round(len.n * UNIT));
  const label = len.n + (len.unit ? " " + len.unit : "");
  const o = { ...r, dims: { ...(r.dims || {}) } };
  if (side === "l" || side === "r") {
    if (side === "l") o.x = r.x + r.w - px;
    o.w = px; o.dims.w = label;
  } else {
    if (side === "t") o.y = r.y + r.h - px;
    o.h = px; o.dims.h = label;
  }
  return o;
}

// a side dragged to (x, y): the rectangle with that side there (never
// flipped inside out); a typed length on that axis no longer holds
export function resize(r, side, x, y) {
  const o = { ...r, dims: { ...(r.dims || {}) } };
  if (side === "l") { const right = r.x + r.w; o.x = Math.min(x, right - MIN); o.w = right - o.x; delete o.dims.w; }
  if (side === "r") { o.w = Math.max(MIN, x - r.x); delete o.dims.w; }
  if (side === "t") { const bottom = r.y + r.h; o.y = Math.min(y, bottom - MIN); o.h = bottom - o.y; delete o.dims.h; }
  if (side === "b") { o.h = Math.max(MIN, y - r.y); delete o.dims.h; }
  return o;
}

export function normalize(x0, y0, x1, y1) {
  return { x: Math.min(x0, x1), y: Math.min(y0, y1), w: Math.abs(x1 - x0), h: Math.abs(y1 - y0) };
}

// the picture: white paper, each rectangle filled light and outlined, the
// typed lengths written along their sides
export function paint(ctx, rects, opts = {}) {
  ctx.fillStyle = "#ffffff";
  ctx.fillRect(0, 0, W, H);
  ctx.lineWidth = 3;
  ctx.font = "600 16px system-ui, sans-serif";
  rects.forEach((r, i) => {
    ctx.fillStyle = r.color + "33";
    ctx.fillRect(r.x, r.y, r.w, r.h);
    ctx.strokeStyle = r.color;
    ctx.strokeRect(r.x + 1.5, r.y + 1.5, r.w - 3, r.h - 3);
    if (opts.picked === i) {
      ctx.save(); ctx.setLineDash([6, 4]); ctx.lineWidth = 1.5; ctx.strokeStyle = "#1f2328";
      ctx.strokeRect(r.x - 4, r.y - 4, r.w + 8, r.h + 8); ctx.restore();
    }
    ctx.fillStyle = r.color;
    if (r.dims?.w) { ctx.textAlign = "center"; ctx.textBaseline = "bottom"; ctx.fillText(r.dims.w, r.x + r.w / 2, r.y - 6); }
    if (r.dims?.h) {
      ctx.save(); ctx.translate(r.x - 8, r.y + r.h / 2); ctx.rotate(-Math.PI / 2);
      ctx.textAlign = "center"; ctx.textBaseline = "bottom"; ctx.fillText(r.dims.h, 0, 0); ctx.restore();
    }
  });
  if (opts.hover) {
    const r = rects[opts.hover.i], s = opts.hover.part;
    ctx.save(); ctx.strokeStyle = "#1f2328"; ctx.lineWidth = 5;
    ctx.beginPath();
    if (s === "l") { ctx.moveTo(r.x, r.y); ctx.lineTo(r.x, r.y + r.h); }
    if (s === "r") { ctx.moveTo(r.x + r.w, r.y); ctx.lineTo(r.x + r.w, r.y + r.h); }
    if (s === "t") { ctx.moveTo(r.x, r.y); ctx.lineTo(r.x + r.w, r.y); }
    if (s === "b") { ctx.moveTo(r.x, r.y + r.h); ctx.lineTo(r.x + r.w, r.y + r.h); }
    ctx.stroke(); ctx.restore();
  }
  if (opts.draft) {
    const d = opts.draft;
    ctx.save(); ctx.setLineDash([8, 5]); ctx.strokeStyle = d.color; ctx.lineWidth = 2;
    ctx.strokeRect(d.x, d.y, d.w, d.h); ctx.restore();
  }
}

const CURSOR = { l: "ew-resize", r: "ew-resize", t: "ns-resize", b: "ns-resize", in: "move", "": "crosshair" };

// open the board; t: its words ({ title, hint, save, cancel, length }),
// onSave(file) when saved. Returns a function that closes it.
export function openDraw(t, onSave) {
  let rects = [], undo = [], next = 0, picked = -1, hover = null, drag = null, draft = null;
  const back = document.createElement("div");
  back.className = "draw-back";
  back.innerHTML = `<div class="draw-box" role="dialog" aria-label="${esc(t.title)}">
    <div class="draw-head"><b>${esc(t.title)}</b><span class="draw-hint">${esc(t.hint)}</span></div>
    <div class="draw-paper"><canvas width="${W}" height="${H}"></canvas><input class="draw-len" type="text" spellcheck="false" hidden></div>
    <div class="draw-foot"><span class="draw-swatch"></span>
      <button type="button" data-d="cancel">${esc(t.cancel)}</button>
      <button type="button" class="primary" data-d="save">${esc(t.save)}</button></div></div>`;
  document.body.appendChild(back);
  const cv = back.querySelector("canvas"), ctx = cv.getContext("2d");
  const len = back.querySelector(".draw-len"), sw = back.querySelector(".draw-swatch");
  let editing = null;
  const redraw = () => {
    paint(ctx, rects, { picked, hover: drag ? null : hover, draft });
    sw.style.background = COLORS[next % COLORS.length];
  };
  const keep = () => { undo.push(JSON.stringify({ rects, next })); if (undo.length > 100) undo.shift(); };
  const at = (e) => {
    const b = cv.getBoundingClientRect();
    return [(e.clientX - b.left) * (W / b.width), (e.clientY - b.top) * (H / b.height)];
  };
  const close = () => { document.removeEventListener("keydown", onKey, true); back.remove(); };

  cv.addEventListener("pointerdown", (e) => {
    if (e.button !== 0) return;
    if (editing) commitLength();
    const [x, y] = at(e);
    const p = pick(rects, x, y);
    cv.setPointerCapture(e.pointerId);
    if (p) {
      picked = p.i;
      drag = { ...p, x0: x, y0: y, r0: rects[p.i], moved: false };
    } else {
      picked = -1;
      drag = { part: "new", x0: x, y0: y, moved: false };
    }
    redraw();
  });
  cv.addEventListener("pointermove", (e) => {
    const [x, y] = at(e);
    if (!drag) {
      hover = pick(rects, x, y);
      if (hover && hover.part === "in") hover = null;
      const p = pick(rects, x, y);
      cv.style.cursor = CURSOR[p ? p.part : ""];
      redraw();
      return;
    }
    if (!drag.moved && Math.hypot(x - drag.x0, y - drag.y0) < 3) return;
    if (!drag.moved) { drag.moved = true; if (drag.part !== "new") keep(); }
    if (drag.part === "new") {
      draft = { ...normalize(drag.x0, drag.y0, clampX(x), clampY(y)), color: COLORS[next % COLORS.length] };
    } else if (drag.part === "in") {
      const r = drag.r0;
      rects[drag.i] = { ...r, x: Math.round(Math.min(W - r.w, Math.max(0, r.x + x - drag.x0))), y: Math.round(Math.min(H - r.h, Math.max(0, r.y + y - drag.y0))) };
    } else {
      rects[drag.i] = resize(drag.r0, drag.part, Math.round(clampX(x)), Math.round(clampY(y)));
    }
    redraw();
  });
  const up = (e) => {
    if (!drag) return;
    const d = drag;
    drag = null;
    if (d.part === "new") {
      if (draft && draft.w >= MIN && draft.h >= MIN) {
        keep();
        rects.push({ x: Math.round(draft.x), y: Math.round(draft.y), w: Math.round(draft.w), h: Math.round(draft.h), color: draft.color, dims: {} });
        picked = rects.length - 1;
        next++;
      }
      draft = null;
    } else if (!d.moved && d.part !== "in") {
      editLength(d.i, d.part);
    }
    redraw();
  };
  cv.addEventListener("pointerup", up);
  cv.addEventListener("pointercancel", up);
  cv.addEventListener("pointerleave", () => { if (!drag) { hover = null; redraw(); } });

  // a side's length, typed into a box beside it
  function editLength(i, side) {
    const r = rects[i], b = cv.getBoundingClientRect(), k = b.width / W;
    const horiz = side === "t" || side === "b";
    const mx = horiz ? r.x + r.w / 2 : side === "l" ? r.x : r.x + r.w;
    const my = horiz ? (side === "t" ? r.y : r.y + r.h) : r.y + r.h / 2;
    editing = { i, side };
    len.hidden = false;
    len.placeholder = t.length;
    len.value = (horiz ? r.dims?.w : r.dims?.h) || String(Math.round((horiz ? r.w : r.h) / UNIT));
    len.style.left = `${mx * k}px`;
    len.style.top = `${my * k}px`;
    len.focus();
    len.select();
  }
  function commitLength() {
    const ed = editing;
    editing = null;
    len.hidden = true;
    const v = parseLength(len.value);
    if (!ed || !v) return;
    keep();
    rects[ed.i] = withLength(rects[ed.i], ed.side, v);
    redraw();
  }
  len.addEventListener("keydown", (e) => {
    if (e.key === "Enter") { e.preventDefault(); commitLength(); }
    if (e.key === "Escape") { e.preventDefault(); e.stopPropagation(); editing = null; len.hidden = true; }
  });
  len.addEventListener("blur", () => { if (editing) commitLength(); });

  function onKey(e) {
    if (e.target === len) return;
    if (e.key === "Escape") { e.preventDefault(); e.stopPropagation(); close(); return; }
    if ((e.key === "Delete" || e.key === "Backspace") && picked >= 0) {
      e.preventDefault(); keep(); rects.splice(picked, 1); picked = -1; hover = null; redraw();
    }
    if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === "z") {
      e.preventDefault();
      const s = undo.pop();
      if (s) { ({ rects, next } = JSON.parse(s)); picked = -1; hover = null; redraw(); }
    }
    e.stopPropagation();
  }
  document.addEventListener("keydown", onKey, true);

  back.addEventListener("click", (e) => {
    const b = e.target.closest("[data-d]");
    if (e.target === back || b?.dataset.d === "cancel") { close(); return; }
    if (b?.dataset.d === "save") {
      if (editing) commitLength();
      paint(ctx, rects);
      cv.toBlob((blob) => {
        close();
        if (blob) onSave(new File([blob], `drawing-${stamp()}.png`, { type: "image/png" }));
      }, "image/png");
    }
  });
  redraw();
  return close;
}

const clampX = (x) => Math.min(W, Math.max(0, x));
const clampY = (y) => Math.min(H, Math.max(0, y));
// local time, as the person reads it: 20261021-0253
const stamp = () => { const d = new Date(), z = (n) => String(n).padStart(2, "0"); return `${d.getFullYear()}${z(d.getMonth() + 1)}${z(d.getDate())}-${z(d.getHours())}${z(d.getMinutes())}${z(d.getSeconds())}`; };
function esc(s) {
  return String(s ?? "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);
}
