// Register before require() so bun src/main.ts and the compiled helper use
// the same guarded source transform. The compile plugin handles bundling.
import { readFileSync } from "node:fs";
import { plugin } from "bun";
import { patchCefWs } from "./bunws.ts";
plugin({
  name: "cef-cdp-ws",
  setup(build) {
    build.onLoad({ filter: /playwright-core[\\/]lib[\\/]coreBundle\.js$/ }, ({ path }) => ({
      contents: 'const module = { exports: {} };\n' + patchCefWs(readFileSync(path, "utf8")) + '\nexport const inprocess = module.exports.inprocess;\n', loader: "js",
    }));
  },
});
export const { chromium } = require("playwright-core") as typeof import("playwright-core");
