import { validatePresentation } from './startup.js';

// Transport opt-in only. The connection-owned Bend actor still encodes keys
// and pastes with its authoritative VT modes and retained terminal owner.
const inputAction = action => action === 'term-key' || action === 'term-paste';
const ownerString = owner => typeof owner === 'string' && owner.length > 0 && new TextEncoder().encode(owner).length <= 1024;
export function terminalInputRequest(action, session) {
  const owner = session?.drafts?.['@terminal.owner'];
  return inputAction(action) && session?.open?.term === true && ownerString(owner)
    ? { terminalInput: true, terminalOwner: owner } : {};
}

// An ACK cannot carry a picture, advance its revision, establish readiness,
// navigate or issue another kind of effect. Validate before ANY command runs.
export function terminalInputReply(result, input) {
  try {
    if (input?.terminalInput !== true || !inputAction(input.action) || input.session?.open?.term !== true || !ownerString(input.terminalOwner) ||
        result.terminalInput !== true || result.renderer !== 'web' || result.remoteReady !== true ||
        result.terminalOwner !== input.terminalOwner || ['shown', 'window', 'nextTarget'].some(k => Object.hasOwn(result, k)) ||
        result.session?.open?.term !== true || result.session?.drafts?.['@terminal.owner'] !== input.terminalOwner ||
        !Array.isArray(result.cmds) || result.cmds.length > 1) return false;
    validatePresentation({ session: result.session, view: { type: 'text', text: '' }, cmds: result.cmds });
    if (result.session.rid >= 2 ** 47) return false;
    return result.cmds.every(command => {
      if (command.type !== 'send') return false;
      const rpc = JSON.parse(command.text), bytes = rpc.p?.b;
      return rpc.m === 'term.input' && Number.isSafeInteger(rpc.id) && rpc.id > 0 && rpc.id < 2 ** 47 &&
        rpc.p?.thread === input.terminalOwner && Array.isArray(bytes) && bytes.length <= 65536 &&
        bytes.every(byte => Number.isInteger(byte) && byte >= 0 && byte <= 255);
    });
  } catch { return false; }
}
