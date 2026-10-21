const { app, BrowserWindow, Menu, dialog, ipcMain, session, shell } = require('electron');
const path = require('node:path');
const { pathToFileURL } = require('node:url');
const os = require('node:os');
const { Service } = require('./service.cjs');

// Checkout launches always name an isolated home. Packaging supplies its
// explicit product configuration after root's integration review.
const home = process.env.BACKPLANE_HOME;
if (!home || !path.isAbsolute(home)) throw new Error('Set an absolute, isolated BACKPLANE_HOME');
if (!app.isPackaged && path.resolve(home) === path.join(os.homedir(), '.backplane-bend')) throw new Error('Development Electron must use an isolated BACKPLANE_HOME');
app.setPath('userData', path.join(home, 'electron-profile'));
app.setName('Backplane');
const resourceRoot = path.join(process.resourcesPath, 'backplane-service');
const build = app.isPackaged ? require(path.join(resourceRoot, 'BUILD.json')) : {};
const service = new Service({ home, binary: process.env.BACKPLANE_SERVICE || (app.isPackaged ? path.join(resourceRoot, 'backplane-serve') : undefined), web: process.env.BACKPLANE_WEB || (app.isPackaged ? path.join(resourceRoot, 'web') : undefined), expectedVersion: process.env.BACKPLANE_SERVICE_VERSION || build.serviceVersion });
const startupPath = path.join(__dirname, 'startup.html');
const startupURL = pathToFileURL(startupPath).href;
const launchedAtMs = Date.now();
let window, origin, connection, serviceReadyAtMs, firstVisibleAtMs, connecting;
let quitting = false;
if (!app.requestSingleInstanceLock()) app.quit();
else {
  app.on('second-instance', () => { window?.show(); if (window?.isMinimized()) window.restore(); window?.focus(); });
  app.whenReady().then(start).catch(error => { dialog.showErrorBox('Backplane could not start', error.message); app.quit(); });
}
function senderIsWindow(event) {
  return window && event.sender === window.webContents && event.senderFrame === window.webContents.mainFrame;
}
function trusted(event) {
  try { return senderIsWindow(event) && origin && new URL(event.senderFrame.url).origin === origin; } catch { return false; }
}
function external(url) {
  try { const parsed = new URL(url); if (['https:', 'http:', 'mailto:'].includes(parsed.protocol) && !parsed.username && !parsed.password) void shell.openExternal(parsed.href); } catch {}
}
function status(phase, message) {
  if (window && !window.isDestroyed()) window.webContents.send('desktop:connection', { phase, message });
}
async function connect(ses) {
  if (connecting) return connecting;
  connecting = (async () => {
    try {
      connection = await service.start(); origin = connection.origin; serviceReadyAtMs = Date.now();
      // Credential material stays in main and the service's HttpOnly cookie.
      const response = await ses.fetch(`${origin}/auth/pair`, { method: 'POST', credentials: 'include', headers: { Authorization: `Bearer ${await service.token()}` }, redirect: 'error' });
      if (!response.ok) throw new Error('Could not authenticate with the service');
      if (!quitting && window && !window.isDestroyed()) await window.loadURL(origin);
    } catch (error) {
      status('error', error.message);
    } finally { connecting = null; }
  })();
  return connecting;
}
function start() {
  const ses = session.fromPartition('persist:backplane-ui');
  const permitted = (wc, permission, url) => {
    try { return wc === window?.webContents && origin && new URL(url).origin === origin && ['notifications', 'clipboard-sanitized-write'].includes(permission); } catch { return false; }
  };
  ses.setPermissionRequestHandler((wc, permission, callback, details) => callback(permitted(wc, permission, details.requestingUrl)));
  ses.setPermissionCheckHandler((wc, permission, requestingOrigin) => permitted(wc, permission, requestingOrigin));
  ses.webRequest.onHeadersReceived((details, callback) => {
    if (new URL(details.url).origin !== origin) return callback({});
    callback({ responseHeaders: { ...details.responseHeaders, 'Content-Security-Policy': ["default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; font-src 'self'; connect-src 'self'; media-src 'self' blob:; object-src 'none'; frame-src 'none'; base-uri 'none'; form-action 'self'; worker-src 'self' blob:"] } });
  });
  ipcMain.handle('desktop:version', event => {
    if (!trusted(event)) throw new Error('Invalid sender');
    return { electron: process.versions.electron, service: connection.version, launchedAtMs, firstVisibleAtMs, serviceReadyAtMs };
  });
  ipcMain.handle('desktop:retry', event => {
    if (!senderIsWindow(event) || event.senderFrame.url !== startupURL) throw new Error('Invalid sender');
    void connect(ses); return true;
  });
  ipcMain.handle('desktop:choose-folder', async event => {
    if (!trusted(event)) throw new Error('Invalid sender');
    const result = await dialog.showOpenDialog(window, { properties: ['openDirectory'] });
    return result.canceled ? null : result.filePaths[0];
  });
  Menu.setApplicationMenu(Menu.buildFromTemplate([
    ...(process.platform === 'darwin' ? [{ role: 'appMenu' }] : []),
    { label: 'File', submenu: [{ role: 'close' }, { role: 'quit' }] }, { role: 'editMenu' },
    { label: 'View', submenu: [{ role: 'reload' }, { role: 'forceReload' }, { role: 'toggleDevTools' }, { type: 'separator' }, { role: 'resetZoom' }, { role: 'zoomIn' }, { role: 'zoomOut' }, { role: 'togglefullscreen' }] }, { role: 'windowMenu' },
  ]));
  void createWindow(ses).then(() => connect(ses)); // Show before any service/history work.
  app.on('activate', () => { if (!BrowserWindow.getAllWindows().length) void createWindow(ses).then(() => connect(ses)); });
}
function createWindow(ses) {
  window = new BrowserWindow({ width: 1400, height: 940, minWidth: 360, minHeight: 480, title: 'Backplane', backgroundColor: '#111410', show: false,
    webPreferences: { session: ses, preload: path.join(__dirname, 'preload.cjs'), nodeIntegration: false, contextIsolation: true, sandbox: true, webSecurity: true, webviewTag: false, spellcheck: true } });
  const shown = new Promise(resolve => window.once('ready-to-show', () => { firstVisibleAtMs ??= Date.now(); window.show(); resolve(); }));
  window.webContents.setWindowOpenHandler(({ url }) => { external(url); return { action: 'deny' }; });
  window.webContents.on('will-navigate', (event, url) => { if (url !== startupURL && new URL(url).origin !== origin) { event.preventDefault(); external(url); } });
  window.webContents.on('will-attach-webview', event => event.preventDefault());
  let closingWindow = false;
  window.on('close', () => { closingWindow = true; });
  window.webContents.on('render-process-gone', (_event, details) => { if (!quitting && !closingWindow && details.reason !== 'clean-exit' && !window.isDestroyed()) { void window.loadFile(startupPath).then(() => connect(ses)); } });
  void window.loadFile(startupPath);
  return shown;
}
app.on('window-all-closed', () => { if (process.platform !== 'darwin') app.quit(); });
app.on('before-quit', () => { quitting = true; });
// The Bend service belongs to the product, independently of UI windows. Closing,
// reloading, or crashing the renderer must not terminate agents, mail or jobs.
// Explicit service shutdown is a separate service-owned authenticated contract.
