import { validatePresentation } from './startup.js';

// A cached, unfiltered server menu needs only its normal actor state ACK.
// Model/provider/effort selection and filtered menus retain full pictures.
export function modelMenuRequest(action, value, ready) {
  return ready && action === 'flag' && value === 'models' ? { modelMenuInput: true } : {};
}
export function modelMenuReply(result, input) {
  try {
    if (input?.modelMenuInput !== true || input.action !== 'flag' || input.value !== 'models' ||
        result.modelMenuInput !== true || result.renderer !== 'web' || result.remoteReady !== true ||
        Object.hasOwn(result, 'terminalInput') || ['shown', 'window', 'nextTarget'].some(k => Object.hasOwn(result, k)) ||
        result.session?.sel !== input.session?.sel || result.session?.open?.models !== !input.session?.open?.models ||
        !Array.isArray(result.cmds) || result.cmds.length > 2) return false;
    validatePresentation({ session: result.session, view: { type: 'text', text: '' }, cmds: result.cmds });
    if (result.session.rid >= 2 ** 47) return false;
    let refresh = 0, focus = 0;
    return result.cmds.every(command => {
      if (command.type === 'focus') return ++focus <= 1 && ['composer', 'model-q'].includes(command.id);
      if (command.type !== 'send' || ++refresh > 1) return false;
      const rpc = JSON.parse(command.text);
      return rpc.m === 'models.refresh' && Number.isSafeInteger(rpc.id) && rpc.id > 0 && rpc.id < 2 ** 47 &&
        rpc.p && typeof rpc.p === 'object' && !Array.isArray(rpc.p) && Object.keys(rpc.p).length === 0;
    });
  } catch { return false; }
}
