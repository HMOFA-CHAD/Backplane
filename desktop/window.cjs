// Keep native window decorations and shortcuts without an application menu bar.
function applicationMenu(Menu, platform) {
  return platform === 'darwin' ? Menu.buildFromTemplate([{label:'Backplane', submenu:[
    {role:'about'}, {type:'separator'}, {role:'hide'}, {role:'hideOthers'}, {role:'unhide'},
    {type:'separator'}, {role:'quit'}
  ]}]) : null;
}
function installShortcuts(window, electron, browser = () => null, platform = process.platform) {
  const bind = contents => contents.on('before-input-event', (event, input) => {
    if (contents !== window.webContents && contents.getOwnerBrowserWindow?.() !== window) return;
    if (input.type !== 'keyDown' || input.alt || input.isComposing) return;
    const key = input.key.toLowerCase();
    if (platform === 'darwin' && input.control && input.meta && key === 'f') { event.preventDefault(); window.setFullScreen(!window.isFullScreen()); return; }
    const command = platform === 'darwin' ? input.meta && !input.control : input.control && !input.meta;
    if (!command && key !== 'f11') return;
    const focused = electron.webContents.getFocusedWebContents();
    const edit = {z:input.shift?'redo':'undo', y:'redo', x:'cut', c:'copy', v:'paste', a:'selectAll'}[key];
    if (command && edit) {
      event.preventDefault();
      if (focused === window.webContents) focused[edit](); else browser()?.edit(edit);
    } else if (key === 'f11') {
      event.preventDefault(); window.setFullScreen(!window.isFullScreen());
    } else if (command && platform === 'darwin' && key === 'm') {
      event.preventDefault();window.minimize();
    } else if (command && key === 'i' && input.shift) {
      event.preventDefault();window.webContents.toggleDevTools();
    } else if (command && ['l','r','0','+','=','-','w','q'].includes(key)) {
      event.preventDefault();
      if (key === 'l') { window.webContents.focus(); window.webContents.send('desktop:browser-focus-address', {}); }
      if (key === 'r') input.shift ? window.webContents.reloadIgnoringCache() : window.webContents.reload();
      if (['0','+','=','-'].includes(key)) window.webContents.setZoomLevel(key === '0' ? 0 : Math.max(-5, Math.min(8, window.webContents.getZoomLevel() + (key === '-' ? -0.5 : 0.5))));
      if (key === 'w') window.close();
      if (key === 'q') electron.app.quit();
    }
  });
  bind(window.webContents);
  const created = (_event, contents) => bind(contents);
  electron.app.on?.('web-contents-created', created);
  window.once?.('closed', () => electron.app.removeListener?.('web-contents-created', created));
}
module.exports = { applicationMenu, installShortcuts };
