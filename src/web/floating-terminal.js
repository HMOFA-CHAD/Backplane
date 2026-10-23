// Window geometry and PTY cell measurement only. Never inspect or log output.
export function installFloatingTerminal({ dispatch, document: doc = document, window: win = window }) {
  let panel, observedScreen, resizeTimer, lastSize = '', drag, previousFocus;
  const positions = new Map();
  let sentFocus;
  const focusState = () => {
    const active = !!doc.activeElement?.closest?.('[data-keys]');
    if (active !== sentFocus) { sentFocus = active;win.backplaneDesktop?.terminalFocus?.(active); }
  };
  doc.addEventListener('focusin', focusState);
  doc.addEventListener('focusout', () => queueMicrotask(focusState));
  win.addEventListener('focus', () => { sentFocus = undefined;focusState(); });
  win.addEventListener('blur', () => { sentFocus = false;win.backplaneDesktop?.terminalFocus?.(false); });
  const clamp = (n, low, high) => Math.max(low, Math.min(n, Math.max(low, high)));
  const fit = () => {
    if (!panel) return;
    const box = panel.getBoundingClientRect();
    panel.style.maxWidth = `${Math.max(220, win.innerWidth - 16)}px`;
    panel.style.maxHeight = `${Math.max(160, win.innerHeight - 16)}px`;
    panel.style.left = `${clamp(box.left, 8, win.innerWidth - panel.offsetWidth - 8)}px`;
    panel.style.top = `${clamp(box.top, 8, win.innerHeight - panel.offsetHeight - 8)}px`;
  };
  const measure = () => {
    if (resizeTimer) return;
    resizeTimer = setTimeout(() => {
      resizeTimer = null;
      if (!panel || !observedScreen) return;
      const style = win.getComputedStyle(observedScreen), context = doc.createElement('canvas').getContext('2d');
      context.font = style.font || `${style.fontSize} ${style.fontFamily}`;
      const cell = context.measureText('0000000000').width / 10;
      const cols = clamp(Math.floor((observedScreen.clientWidth - parseFloat(style.paddingLeft) - parseFloat(style.paddingRight)) / cell), 20, 400);
      const rows = clamp(Math.floor((observedScreen.clientHeight - parseFloat(style.paddingTop) - parseFloat(style.paddingBottom)) / (parseFloat(style.lineHeight) || 17)), 5, 150);
      const size = `${cols}x${rows}`, key = panel.dataset.terminalOwner + ':' + size;
      if (cell > 0 && key !== lastSize) { lastSize = key;dispatch('ws-term-resize', size); }
    }, 120);
  };
  const observer = new ResizeObserver(() => { fit();measure(); });
  const sync = () => {
    focusState();
    const next = doc.querySelector('.floating-terminal');
    if (next !== panel) {
      if (panel) {
        positions.set(panel.dataset.terminalOwner, { left: panel.style.left, top: panel.style.top, width: panel.style.width, height: panel.style.height });
        observer.disconnect();
      }
      panel = next; observedScreen = null;
      if (!panel) {
        if (previousFocus?.isConnected) previousFocus.focus();
        return;
      }
      previousFocus = doc.activeElement;
      Object.assign(panel.style, positions.get(panel.dataset.terminalOwner) || {});
      observedScreen = panel.querySelector('.screen');
      if (observedScreen) observer.observe(observedScreen);
      fit();measure();
    } else if (panel) measure();
    const chosen = doc.querySelector('.workspace-command.on');
    chosen?.scrollIntoView({ block: 'nearest' });
  };
  new MutationObserver(sync).observe(doc.getElementById('root') || doc.body, { childList: true, subtree: true });
  doc.addEventListener('pointerdown', event => {
    const handle = event.target.closest?.('.floating-terminal-handle');
    if (!panel || !handle || event.target.closest('button') || event.button !== 0) return;
    const box = panel.getBoundingClientRect();
    drag = { x: event.clientX - box.left, y: event.clientY - box.top, handle, id: event.pointerId };
    handle.setPointerCapture(event.pointerId);event.preventDefault();
  });
  doc.addEventListener('pointermove', event => {
    if (!drag || !panel || event.pointerId !== drag.id) return;
    panel.style.left = `${event.clientX - drag.x}px`;panel.style.top = `${event.clientY - drag.y}px`;fit();
  });
  const done = event => { if (drag && event.pointerId === drag.id) { drag.handle.releasePointerCapture(drag.id);drag = null; } };
  doc.addEventListener('pointerup', done);doc.addEventListener('pointercancel', done);
  win.addEventListener('resize', () => { fit();measure(); });
  sync();
}
