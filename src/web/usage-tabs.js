// Keyboard/focus transport only; enabled providers and selection live in Bend.
export function installUsageTabs(root = document) {
  root.addEventListener('keydown', event => {
    const tab = event.target.closest?.('.usage-tabs [role="tab"]');
    if (!tab || event.altKey || event.ctrlKey || event.metaKey) return;
    const tabs = [...tab.closest('[role="tablist"]').querySelectorAll('[role="tab"]')];
    const index = tabs.indexOf(tab);
    let next;
    if (event.key === 'ArrowRight') next = (index + 1) % tabs.length;
    else if (event.key === 'ArrowLeft') next = (index + tabs.length - 1) % tabs.length;
    else if (event.key === 'Home') next = 0;
    else if (event.key === 'End') next = tabs.length - 1;
    else return;
    event.preventDefault();
    tabs[next].focus();
    tabs[next].click();
  });
}
