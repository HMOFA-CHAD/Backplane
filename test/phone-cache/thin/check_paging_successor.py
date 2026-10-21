"""Source boundary checks only; does not claim Swift/UIKit/Compose runtime proof."""
from pathlib import Path
import os

root = Path(os.environ.get('BP_PAGING_SOURCE_ROOT', Path(__file__).resolve().parents[3]))
ios = root / 'mobile/ios/Backplane'
android = root / 'mobile/android/app/src/main/java/dev/backplane/mobile'
scroll = (ios/'TimelineScroll.swift').read_text()
views = (ios/'Views.swift').read_text()
model = (ios/'AppModel.swift').read_text()
engine = (ios/'Engine.swift').read_text()
assert 'earlierGate.configure(enabled: enabled)' in scroll
assert 'earlierGate.request(earlier, perform: loadEarlier)' in scroll
assert 'earlierGate.beginDrag()' in scroll.split('func scrollViewWillBeginDragging',1)[1].split('func scrollViewDidScroll',1)[0]
assert 'initialized, top < 400, earlier > 0, !following' in scroll
assert 'guard !correcting, scroll.isDragging || scroll.isDecelerating else { return }' in scroll
assert 'loadEarlier: { live && model.loadEarlier(thread.id) }' in views
assert 'earlierEnabled: live && model.contentReady && model.screen?.thread?.id == thread.id' in views
assert 'guard contentReady, screen?.thread?.id == thread else { return false }' in model
assert 'self.owe = self.owe || carriedOwe' in engine
assert 'metadata?.inert != true && (withheld || stale)' in engine
kengine = (android/'Engine.kt').read_text()
assert 'Backplane.recv(${q(key)}, ${q(data)}, ${q(epoch)}, $quiet, $owed)' in kengine
assert 'if (inert && carriedOwe) owe.set(true)' in kengine
ui = (android/'Ui.kt').read_text()
assert 'LaunchedEffect(m.contentReady, s.hub, t.id)' in ui
assert 'snapshotFlow { userDragging && !pageAcceptedForDrag && m.contentReady && m.screen?.hub == s.hub && m.screen?.thread?.id == t.id }.first { it }' in ui
assert 'if (userDragging) pageAcceptedForDrag = false' in ui
assert 'pageAcceptedForDrag = true\n                    keepAt' in ui
print('PASS native source boundaries: strict current-ready real gesture, decline-safe gate, owed preservation, tagged Android epoch; not app/runtime acceptance')
