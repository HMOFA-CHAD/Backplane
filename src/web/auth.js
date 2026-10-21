// Exchange pairing material once. The durable browser credential belongs in an
// HttpOnly cookie; fragments and legacy localStorage never enter socket URLs.
export async function pairBrowser({ location, history, storage, fetch, timeoutMs = 2000 }) {
  const fragment = new URLSearchParams(location.hash.slice(1));
  const supplied = fragment.get("token");
  const legacy = storage.getItem("backplane-token");
  const token = supplied ?? legacy;
  if (supplied !== null) history.replaceState(null, "", location.pathname + location.search);
  if (!token) return true;
  if (!/^[0-9a-f]{32}$/.test(token)) return false;
  const controller = new AbortController();let timer;
  let response;
  try { response = await Promise.race([fetch("/auth/pair", {
    method: "POST", credentials: "same-origin", cache: "no-store",
    headers: { Authorization: `Bearer ${token}` },
    signal: controller.signal,
  }), new Promise(resolve => { timer = setTimeout(() => { controller.abort();resolve(null); }, timeoutMs); })]); }
  catch { return false; }
  finally { clearTimeout(timer); }
  if (!response) return false;
  if (!response.ok) return false;
  storage.removeItem("backplane-token");
  return true;
}
