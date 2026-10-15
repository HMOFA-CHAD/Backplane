// Exercise the actual host paste listener, with both browser clipboard shapes.
// bun test/tools/paste_web_test.ts
import { readFileSync } from "node:fs";
const host = readFileSync("src/web/host.js", "utf8");
const start = host.indexOf('document.addEventListener("paste",');
const end = host.indexOf('// text typed into a key field', start);
let paste: (event: any) => void;
const uploads: any[] = [];
const actions: any[] = [];
const document = { addEventListener(_: string, fn: any) { paste = fn; } };
new Function("document", "upload", "dispatch", "forKey", host.slice(start, end))(
  document, async (action: string, file: any) => { uploads.push({ action, file }); },
  (...args: any[]) => actions.push(args), () => "",
);
function check(name: string, ok: boolean) {
  if (!ok) throw new Error(name);
  console.log(`ok ${name}`);
}
async function run(cd: any, terminal = false) {
  uploads.length = 0;
  actions.length = 0;
  let prevented = false;
  paste!({ clipboardData: cd, preventDefault() { prevented = true; }, target: {
    closest(selector: string) {
      if (selector === "[data-keys]") return terminal ? { getAttribute() { return "term-paste"; } } : null;
      return { getAttribute() { return "attach"; } };
    },
  }});
  await new Promise((resolve) => setTimeout(resolve, 0));
  return prevented;
}
const screenshot = { name: "screenshot.png", type: "image/png", size: 100 };
check("screenshot in files attaches", await run({ files: [screenshot] }) && uploads[0]?.file === screenshot);
check("image item fallback attaches", await run({ files: [], items: [{ kind: "file", type: "image/png", getAsFile() { return screenshot; } }] }) && uploads[0]?.file === screenshot);
await run({ files: [screenshot], items: [{ kind: "file", type: "image/png", getAsFile() { return screenshot; } }] });
check("files and items do not duplicate", uploads.length === 1);
check("text paste left to field", !(await run({ files: [], items: [{ kind: "string", type: "text/plain" }] })) && uploads.length === 0);
check("null file ignored", !(await run({ files: [], items: [{ kind: "file", type: "image/png", getAsFile() { return null; } }] })));
await run({ files: [screenshot], getData() { return "plain"; } }, true);
check("terminal receives only text", uploads.length === 0 && actions[0]?.[1] === "plain");
check("composer exposes data-paste", readFileSync("src/web/view.bend", "utf8").includes('D.At{"data-paste", "attach"}'));
