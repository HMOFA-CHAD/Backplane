// A bounded in-memory picture of validated server views for smooth switching.
// It never restores sessions, cursors or authority. The host overlays the
// current draft and still refuses actions until the new view is ready.
export class ViewTransition {
  constructor({limit = 8, bytes = 512 * 1024} = {}) { this.limit = limit;this.bytes = bytes;this.views = new Map();this.positions = new Map(); }
  key(scope) {
    if (!scope?.identity || !scope.epoch || !scope.target?.kind) return '';
    return JSON.stringify([scope.origin, scope.identity, scope.language, scope.epoch, scope.target, scope.selected, scope.settings === true, scope.route || null]);
  }
  put(scope, shown) {
    const key = this.key(scope);
    const conversation = n => n?.type === 'element' && (
      n.tag === 'main' && n.attrs.some(a => a.name === 'data-thread' && a.value === scope.selected)
        && n.kids.some(c => c.type === 'element' && c.attrs.some(a => a.name === 'class' && a.value.split(/\s+/).includes('composer')))
      || n.kids.some(conversation));
    // Settings, Mailroom and other forms retain their existing field ownership;
    // never restore their mutable fields as a conversation picture.
    if (!key || !scope.selected || !conversation(shown) || new TextEncoder().encode(JSON.stringify(shown)).length > this.bytes) return false;
    this.views.delete(key);this.views.set(key, shown);
    while (this.views.size > this.limit) { const old=this.views.keys().next().value;this.views.delete(old);this.positions.delete(old); }
    return true;
  }
  get(scope) { return this.views.get(this.key(scope)) || null; }
  savePosition(scope, position) {
    const key=this.key(scope);
    if (this.views.has(key)) this.positions.set(key, position);
  }
  position(scope) { return this.positions.get(this.key(scope)) || null; }
  clear() { this.views.clear();this.positions.clear(); }
}

// Keep the known sidebar while a never-seen target loads. The main area comes
// from the current selection, never the departing thread's body or fields.
export function loadingShell(previous, waiting, title) {
  const find = (n, tag) => n?.type === 'element' ? n.tag === tag ? n : n.kids.map(c => find(c, tag)).find(Boolean) : null;
  const sidebar = find(previous, 'aside');
  const walk = n => {
    if (n?.type !== 'element') return n;
    if (n.tag === 'aside' && sidebar) return sidebar;
    if (n.tag === 'main') {
      const composer = n.kids.filter(c => c.type === 'element' && c.attrs?.some(a => a.name === 'class' && a.value.split(/\s+/).includes('composer')));
      const el = (tag, key, attrs, kids) => ({type:'element', tag, key, attrs, kids});
      return {...n, attrs:[...n.attrs, {name:'aria-busy', value:'true'}], kids:[
        el('header','',[{name:'class',value:'thread-head'}],[el('span','',[{name:'class',value:'title'}],[{type:'text',text:title}])]),
        el('div','timeline',[{name:'class',value:'timeline'},{name:'id',value:'timeline'},{name:'role',value:'status'}],[{type:'text',text:'Loading conversation…'}]),
        ...composer
      ]};
    }
    return {...n, kids:n.kids.map(walk)};
  };
  return walk(waiting);
}

// Light or dark is one fact for the whole page (the hub's ui.theme), never a
// thread's. A retained picture keeps the app root's class it was drawn with,
// so before one is shown again its root takes the theme of the newest
// authoritative frame; everything else in it is left exactly as it was.
const appRoot = (n, depth = 0) => n?.type !== 'element' || depth > 4 ? null
  : n.key === 'app' ? n : n.kids.map(c => appRoot(c, depth + 1)).find(Boolean) || null;
export function themeOf(shown) {
  const app = appRoot(shown);
  if (!app) return '';
  return (app.attrs.find(a => a.name === 'class')?.value || '').split(/\s+/).includes('light') ? 'light' : 'dark';
}
export function withTheme(shown, theme) {
  if (theme !== 'light' && theme !== 'dark') return shown;
  const app = appRoot(shown);
  if (!app || themeOf(shown) === theme) return shown;
  const recolor = n => {
    if (n?.type !== 'element') return n;
    if (n !== app) return {...n, kids: n.kids.map(recolor)};
    const words = (n.attrs.find(a => a.name === 'class')?.value || '').split(/\s+/).filter(w => w && w !== 'light');
    // the hub writes "light" before the tour's words (view.bend's View.page.b.sidebar)
    if (theme === 'light') { const at = words.findIndex(w => w.startsWith('tour')); words.splice(at < 0 ? words.length : at, 0, 'light'); }
    const attrs = n.attrs.some(a => a.name === 'class') ? n.attrs.map(a => a.name === 'class' ? {...a, value: words.join(' ')} : a)
      : [...n.attrs, {name: 'class', value: words.join(' ')}];
    return {...n, attrs};
  };
  return recolor(shown);
}
