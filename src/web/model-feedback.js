// Pending visibility only. The model rows/actions remain server-rendered and
// every original click still goes once through the ordered authenticated path.
export class ModelFeedback {
  constructor(changed) { this.changed = changed;this.revision = 0;this.open = null; }
  choice(action, value, visible) {
    // a choice leaves the menu open (another may follow); only the chip and
    // the shade around the menu toggle it
    if (!(action === 'flag' && value === 'models')) return undefined;
    const revision = ++this.revision;
    this.open = !visible;
    this.changed();
    return () => { if (revision === this.revision) { this.open = null;this.changed(); } };
  }
  project(session) {
    return this.open === null ? session : { ...session, open: { ...session.open, models: this.open } };
  }
  clear() { this.revision++;this.open = null; }
}
