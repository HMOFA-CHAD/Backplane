const path = require('node:path');
// Generated from assets/icon/backplane-desktop.svg; packaged with the shell.
const png = path.join(__dirname, 'backplane.png');
const ico = path.join(__dirname, 'backplane.ico');
const icns = path.join(__dirname, 'backplane.icns');
module.exports = { iconPath: (platform = process.platform) => platform === 'win32' ? ico : png, png, ico, icns };
