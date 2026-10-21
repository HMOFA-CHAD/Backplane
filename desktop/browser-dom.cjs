'use strict';
// Exact first-party helper DOM scripts, reused without loading the helper or
// launching another browser. Source tools/browser/src/main.ts SHA256 f1828f45bd83ddaf514cca174325b5bc6cd1b971d4ff49fce6d83804cfaf9b5c.
const MAX_ELEMENTS=200,MAX_VISIBLE_TEXT=20000;
const SNAPSHOT_SCRIPT = `(() => {
  const selectorFor = (element) => {
    if (element.id) return "#" + CSS.escape(element.id);
    for (const attribute of ["data-testid", "name"]) {
      const value = element.getAttribute(attribute);
      if (value) return element.tagName.toLowerCase() + "[" + attribute + "=" + JSON.stringify(value) + "]";
    }
    const parts = [];
    for (let cur = element; cur && cur.nodeType === 1 && parts.length < 8; cur = cur.parentElement) {
      const parent = cur.parentElement;
      const same = parent ? Array.from(parent.children).filter((c) => c.tagName === cur.tagName) : [];
      const base = cur.tagName.toLowerCase();
      parts.unshift(same.length > 1 ? base + ":nth-of-type(" + (same.indexOf(cur) + 1) + ")" : base);
    }
    return parts.join(" > ");
  };
  const visible = (el) => {
    const s = getComputedStyle(el);
    const r = el.getBoundingClientRect();
    return s.visibility !== "hidden" && s.display !== "none" && r.width > 0 && r.height > 0;
  };
  const elements = Array.from(document.querySelectorAll("a[href],button,input,textarea,select,[role],[tabindex]"))
    .filter(visible).slice(0, ${MAX_ELEMENTS}).map((el) => {
      const r = el.getBoundingClientRect();
      return {
        tag: el.tagName.toLowerCase(),
        role: el.getAttribute("role"),
        name: (el.getAttribute("aria-label") || el.innerText || el.getAttribute("name") || el.getAttribute("placeholder") || "").trim().slice(0, 200),
        selector: selectorFor(el),
        x: Math.round(r.x), y: Math.round(r.y), width: Math.round(r.width), height: Math.round(r.height),
      };
    });
  return {
    loading: document.readyState !== "complete",
    visibleText: (document.body ? document.body.innerText : "").slice(0, ${MAX_VISIBLE_TEXT}),
    interactiveElements: elements,
  };
})()`;

// the page's readable text: its main or article when that holds most of
// the words, else the body; blank runs squeezed
const TEXT_SCRIPT = `(() => {
  const body = document.body ? document.body.innerText : "";
  const main = document.querySelector("main, [role=main], article");
  const m = main ? main.innerText : "";
  const t = m.length > 200 && m.length > body.length / 3 ? m : body;
  return t.split("\\n").map((l) => l.replace(/[ \\t\\u00a0]+/g, " ").trim()).join("\\n").replace(/\\n{3,}/g, "\\n\\n").trim();
})()`;
module.exports={SNAPSHOT_SCRIPT,TEXT_SCRIPT};
