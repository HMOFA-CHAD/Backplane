// Keyboard dismissal for the thread's inline inspector. Bend owns the choice
// and its persistence; use the same head button as pointer activation.
export function installSubagentInspector(root = document) {
  const keydown = event => {
    if (event.key !== "Escape" || event.defaultPrevented || event.isComposing || event.altKey || event.ctrlKey || event.metaKey || event.shiftKey) return;
    const dock = event.target.closest?.(".thread-view .subs");
    const head = dock?.querySelector('.subs-head[aria-expanded="true"]');
    if (!head) return;
    event.preventDefault();
    event.stopImmediatePropagation();
    head.click();
    head.focus({ preventScroll: true });
  };
  root.addEventListener("keydown", keydown);
  return () => root.removeEventListener("keydown", keydown);
}
