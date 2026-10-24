// A disposable worker for reply lifecycle tests; never imports IPC or KiCad.
self.onmessage = ({ data }) => {
  if (data.op === "exit") self.close();
  if (data.op === "error") throw new Error("synthetic worker failure");
  if (data.op === "reply") self.postMessage({ op: "reply", id: data.id, bytes: new Uint8Array([42]) });
};
