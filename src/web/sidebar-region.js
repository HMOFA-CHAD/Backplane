// A transport reference can restore only the immutable sidebar acknowledged
// by this request on its surviving ThinViews link. Never persisted or global.
const object = x => x !== null && typeof x === 'object' && !Array.isArray(x);
const token = x => typeof x === 'string' && /^[1-9][0-9]{0,9}$/.test(x) && Number(x) <= 2 ** 32 - 1;
const region = (n, tag) => object(n) && n.type === 'element' && n.tag === tag && n.key === 'sidebar';
const fields = (o, names) => object(o) && Object.keys(o).length === names.length && names.every(n => Object.hasOwn(o, n));

export function sidebarOffer(cache) { return { version: 1, token: cache?.token || '', exactContent: true }; }

export function sidebarPicture(result, input, base) {
  if (!Object.hasOwn(result, 'sidebarRegion')) return { result, cache: null };
  const r = result.sidebarRegion;
  if (!fields(r, ['version','token','base']) || r.version !== 1 || !token(r.token) || typeof r.base !== 'string'
      || input.sidebarRegion?.version !== 1 || result.nextTarget || !result.shown || result.remoteReady !== true)
    throw Error('Invalid sidebar region');
  if (r.base && (r.base !== r.token || r.base !== input.sidebarRegion.token || base?.token !== r.base))
    throw Error('Unacknowledged sidebar region');
  if (!r.base && r.token !== String(input.requestRevision)) throw Error('Invalid sidebar seed');
  let sidebars = 0, references = 0, node = null, remaining = 20000;
  const walk = (n, depth = 0) => {
    if (!object(n) || --remaining < 0 || depth >= 64) throw Error('Invalid sidebar picture');
    if (region(n, 'bp-sidebar-ref')) {
      if (++references !== 1 || !r.base || !fields(n, ['type','tag','key','attrs','kids'])
          || !Array.isArray(n.attrs) || n.attrs.length || !Array.isArray(n.kids) || n.kids.length
          || !region(base?.node, 'aside')) throw Error('Invalid sidebar reference');
      return base.node;
    }
    if (region(n, 'aside')) { sidebars++;node = n;return n; }
    if (n.type === 'text') return n;
    if (n.type !== 'element' || !Array.isArray(n.kids)) throw Error('Invalid sidebar tree');
    const kids = n.kids.map(k => walk(k, depth + 1));
    return kids.some((k, i) => k !== n.kids[i]) ? { ...n, kids } : n;
  };
  const shown = walk(result.shown);
  if (r.base ? references !== 1 || sidebars !== 0 : references !== 0 || sidebars !== 1)
    throw Error('Ambiguous sidebar region');
  return { result: shown === result.shown ? result : { ...result, shown }, cache: { token: r.token, node: r.base ? base.node : node } };
}
