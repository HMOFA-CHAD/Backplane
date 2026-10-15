// Exercise the production persistence hooks with a browser-local store.
// No hub or DOM needed: only the same Ui actions the browser dispatches.
import { readFileSync } from "node:fs";
import { strict as assert } from "node:assert";
const source = readFileSync("src/web/host.js", "utf8");
const restore = source.slice(source.indexOf('const SUBS_CHOICE ='), source.indexOf('let socket = null;'));
const start = source.indexOf('function dispatch(action, value, timer)');
const dispatch = source.slice(start, source.indexOf('  const did =', start));
const harness = new Function(`
  let ui = {};
  const store = new Map();
  const localStorage = {
    get length() { return store.size; },
    key: i => Array.from(store.keys())[i],
    getItem: k => store.get(k),
    setItem: (k, v) => store.set(k, v)
  };
  const App = { act: (u, a, v) => {
    const sep = v.indexOf("\\t");
    if (a === "subs-open") return {ui: {...u, [v]: "1"}};
    if (a === "subs-shut") return {ui: {...u, [v.slice(0, sep)]: "0" + v.slice(sep + 1)}};
    return {ui: u};
  }};
  ${restore}
  ${dispatch}
  }
  return {
    dispatch,
    reload() { ui = {}; restoreSubs(); return ui; },
    reset() { ui = {}; },
    restoreSubs,
    state: () => ui,
    store
  };
`)();
harness.dispatch("subs-shut", "thread-a\tlive:agent-a\u001fattention:agent-b");
harness.dispatch("subs-open", "thread-b");
assert.deepEqual(harness.reload(), {"thread-a": "0live:agent-a\u001fattention:agent-b", "thread-b": "1"});
harness.reset();
harness.restoreSubs();
assert.equal(harness.state()["thread-a"], "0live:agent-a\u001fattention:agent-b");
harness.dispatch("subs-open", "thread-a");
assert.equal(harness.reload()["thread-a"], "1");
assert.match(source, /if \(t === "log" && Number\(field\(j, "since"\) \?\? 0\) === 0\) restoreSubs\(\);/);
console.log("PASS: browser panel choices persist per thread through reload and full-log reset");
