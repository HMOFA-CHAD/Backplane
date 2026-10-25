import { utf8Bytes } from './thin.js';

const sameTarget = (a, b) => a?.kind === b?.kind && a?.id === b?.id;
const integer = value => typeof value === 'string' && /^(0|[1-9][0-9]{0,14})$/.test(value) && Number(value) <= 281474976710655;
const attr = (pane, name) => pane?.attrs?.find(a => a.name === name)?.value;

// A display-only fragment. It cannot settle requests, establish readiness,
// navigate, execute commands or replace any part of the conversation.
export function terminalOutputFrame(frame, link, session) {
  try {
  if (!frame || frame.t !== 'view.terminal' || frame.version !== 1 || !link?.viewId ||
      ['cmds','session','window','shown','nextTarget'].some(key => Object.hasOwn(frame, key)) ||
      frame.epoch !== link.greeting.epoch || frame.generation !== link.greeting.generation ||
      frame.viewId !== link.viewId || frame.target?.kind !== link.target?.kind || frame.target?.id !== link.target?.id ||
      session?.open?.term !== true || !frame.owner || frame.owner !== session.drafts?.['@terminal.owner'] ||
      !integer(frame.sequence) || Number(frame.sequence) === 0 || !integer(frame.incarnation) || Number(frame.incarnation) === 0 ||
      typeof frame.pid !== 'string' || !/^(0|[1-9][0-9]{0,9})$/.test(frame.pid) || Number(frame.pid) > 4294967295 ||
      frame.pane?.type !== 'element' || frame.pane.tag !== 'section' || frame.pane.key !== 'term-pane' ||
      !Array.isArray(frame.pane.attrs) || !frame.pane.attrs.some(a => a.name === 'class' && a.value === 'term-pane') ||
      attr(frame.pane, 'data-terminal-sequence') !== frame.sequence || attr(frame.pane, 'data-terminal-incarnation') !== frame.incarnation || attr(frame.pane, 'data-terminal-pid') !== frame.pid ||
      utf8Bytes(JSON.stringify(frame)) > 262144) return false;
  return true;
  } catch { return false; }
}

// Keep the newest accepted fragment across an older in-flight full reply.
// Keyed patching touches the pane only, retaining its input node and focus.
export class TerminalOutputPane {
  constructor({ document, patch, current }) { this.document = document;this.patch = patch;this.current = current;this.clear(); }
  clear() { this.frame = null;this.pane = null;this.binding = '';this.retired = '';this.releaseRetirement = false; }
  rebind() { this.releaseRetirement = true; }
  key(current) { return JSON.stringify([current.generation, current.epoch, current.viewId, current.target?.kind, current.target?.id, current.owner]); }
  retire() {
    const current = this.current(), pane = this.document.querySelector('.floating-terminal .term-pane');
    this.frame = null;this.releaseRetirement = false;
    this.retired = current && pane ? this.key(current) + ':' + pane.getAttribute('data-terminal-incarnation') : '';
  }
  receive(node, frame) {
    if (!this.apply()) return false;
    const current = this.current(), previous = this.frame;
    if (!previous || frame.generation !== current.generation || frame.epoch !== current.epoch || frame.viewId !== current.viewId ||
        !sameTarget(frame.target, current.target) || frame.owner !== current.owner || frame.incarnation !== previous.incarnation ||
        previous.pid && previous.pid !== '0' && frame.pid !== previous.pid) return false;
    if (Number(frame.sequence) <= Number(previous.sequence)) return true;
    this.frame = { ...frame, node };this.patch(this.pane, node);return true;
  }
  apply(full = false) {
    const current = this.current();
    if (!current || current.open !== true) { this.clear();return false; }
    const pane = this.document.querySelector('.floating-terminal .term-pane');
    if (!pane || pane.parentElement?.getAttribute('data-terminal-owner') !== current.owner) return false;
    this.pane = pane;
    const binding = this.key(current), incarnation = pane.getAttribute('data-terminal-incarnation') || '0';
    if (binding + ':' + incarnation === this.retired && !(full && this.releaseRetirement)) return false;
    if (binding !== this.binding) { this.frame = null;this.binding = binding; }
    const sequence = pane.getAttribute('data-terminal-sequence') || '0', previous = this.frame;
    if (!integer(incarnation) || !integer(sequence) || !pane.__v) return false;
    if (!previous || Number(incarnation) > Number(previous.incarnation) || incarnation === previous.incarnation && Number(sequence) >= Number(previous.sequence)) {
      this.frame = { ...current, incarnation, sequence, pid: pane.getAttribute('data-terminal-pid') || '', node: pane.__v };
      this.retired = '';
      if (full) this.releaseRetirement = false;
    } else this.patch(pane, previous.node);
    return true;
  }
}
