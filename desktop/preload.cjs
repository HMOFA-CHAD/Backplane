const { contextBridge, ipcRenderer } = require('electron');
contextBridge.exposeInMainWorld('backplaneDesktop', Object.freeze({
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
