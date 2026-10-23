const { contextBridge, ipcRenderer } = require('electron');
// Only the selected desktop shell advertises native Browser support. The
// renderer gets geometry/intents and bounded UI events, never the private
// bearer, debugger, guest WebContents or service grants.
const listenBrowser = (channel, accept) => callback => {
  if (typeof callback !== 'function') throw new TypeError('Expected a callback');
  const listener = (_event, value) => { const safe = accept(value); if (safe) callback(safe); };
  ipcRenderer.on(channel, listener);
  return () => ipcRenderer.removeListener(channel, listener);
};
const owner = value => typeof value === 'string' && value.length > 0 && value.length <= 512 && !/[\x00-\x1f]/.test(value);
const browser = process.argv.includes('--backplane-direct-browser=1') ? Object.freeze({
  present: value => ipcRenderer.invoke('desktop:browser-present', value),
  hide: () => ipcRenderer.invoke('desktop:browser-hide'),
  reconnect: () => ipcRenderer.invoke('desktop:browser-reconnect'),
  state: () => ipcRenderer.invoke('desktop:browser-state'),
  onState: listenBrowser('desktop:browser-state', value => {
    if (!['connecting', 'ready', 'error'].includes(value?.phase)) return null;
    return {phase:value.phase, message:String(value.message || '').slice(0,240), ...(owner(value.owner)?{owner:value.owner}:{})};
  }),
  onTakeover: listenBrowser('desktop:browser-takeover', value => owner(value?.owner) ? {owner:value.owner} : null),
  onFocusAddress: callback => {
    if (typeof callback !== 'function') throw new TypeError('Expected a callback');
    const listener = () => callback();
    ipcRenderer.on('desktop:browser-focus-address', listener);
    return () => ipcRenderer.removeListener('desktop:browser-focus-address', listener);
  },
}) : null;
contextBridge.exposeInMainWorld('backplaneDesktop', Object.freeze({
  terminalFocus: active => ipcRenderer.send('desktop:terminal-focus', active === true),
  ...(browser ? {browser} : {}),
  chooseFolder: () => ipcRenderer.invoke('desktop:choose-folder'),
  version: () => ipcRenderer.invoke('desktop:version'),
  retry: () => ipcRenderer.invoke('desktop:retry'),
  onFocusAddress: callback => {
    if (typeof callback !== 'function') throw new TypeError('Expected a callback');
    const listener = () => callback();
    ipcRenderer.on('desktop:browser-focus-address', listener);
    return () => ipcRenderer.removeListener('desktop:browser-focus-address', listener);
  },
  onConnection: callback => {
    if (typeof callback !== 'function') throw new TypeError('Expected a callback');
    const listener = (_event, data) => {
      if (['error', 'connecting'].includes(data?.phase) && typeof data.message === 'string') callback({phase:data.phase,message:data.message});
    };
    ipcRenderer.on('desktop:connection', listener);
    return () => ipcRenderer.removeListener('desktop:connection', listener);
  },
}));
