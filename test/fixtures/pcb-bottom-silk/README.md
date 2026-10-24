This fixture checks PCB silkscreen orientation against KiCad, rather than
making all bottom text readable regardless of its authored settings.

`before.png` and `after.png` are actual native PCB face renders, seen from
below with the same camera. The normal mirrored `BOTTOM R37`, deliberately
unmirrored `UNMIRRORED`, rotated `ROT90`, offset front/back footprints,
asymmetric silk graphics, mask openings, pads, drills and chamfered outline
provide controls. `BACK180` is authored at 180 degrees with `(unlocked yes)`:
KiCad preserves that angle, so it must remain upside down in this bottom
view. Before the fix, Backplane incorrectly forced it upright. This is a
reproduced native-renderer case; the originally reported board was not
provided, so this evidence does not identify that board's exact cause.

The source correction is in `src/core/pcb3d.bend`'s shared PCB text layout.
KiCad's unlocked/keep-upright setting is independent of the text's mirror
flag. Modern `(unlocked yes/no)` and the legacy token inside `(at ...)` are
supported. The GLB export/loader, camera, graphics, copper, mask and drill
transforms are unchanged. The active KiCad-to-GLB viewer already matches
KiCad for this fixture; this patch changes the native PCB face renderer
and the 2D text parser that shares its text layout.

`kicad-bottom.svg` (trailing whitespace removed) is the independent reference from the selected Backplane
KiCad 10.99.0-bp.4 runtime, source revision
`5dbc22d292704d02b609d5b7a0edc971f1b7f08b`. Its
`pcbnew/pcb_text.cpp::GetDrawRotation` applies keep-upright only when enabled;
`pcbnew/pcb_io/kicad_sexpr/pcb_io_kicad_sexpr_parser.cpp::parsePCB_TEXT_effects`
reads `unlocked` as its inverse. The reference SVG and GLB both preserve
BACK180's authored rotation.

Reproduce the regression and corrected native renders from the repo root:

```sh
TEST_FILES='test/pcb_text_test.bend test/pcb_bottom_silk_test.bend' scripts/test.sh
bend test/pcb_bottom_silk_test.bend -o build/pcb-bottom-silk/renderer.mjs
bun test/tools/pcb_bottom_silk.mjs build/pcb-bottom-silk/renderer.mjs
```

The driver compares parsed footprint strokes with independently authored
board text at the same absolute pose on both layers, with asymmetric anchors,
mirrored/unmirrored text, legacy/TRS footprint poses, four rotated angles,
properties and fp_text, plus enabled/default and legacy upright controls.
It also compares actual native 3D pixels against a fixture where only BACK180
is expressed as equivalent board text. It fails against the pre-fix source
(first geometry mismatch: 11.5 versus 13).

Authoritative exports (set CLI to the selected runtime's kicad-cli):

```sh
"$CLI" pcb export svg --layers B.SilkS,B.Cu,Edge.Cuts --mirror \
  --fit-page-to-board --exclude-drawing-sheet --mode-single \
  -o build/pcb-bottom-silk/kicad-bottom.svg \
  test/fixtures/pcb-bottom-silk/asymmetric.kicad_pcb
"$CLI" pcb export glb --no-components --include-pads --include-soldermask \
  --include-silkscreen -f -o build/pcb-bottom-silk/fixture.glb \
  test/fixtures/pcb-bottom-silk/asymmetric.kicad_pcb
```

Verification on 2026-10-24: both focused tests pass (0.3/0.4 GB peak RSS).
Before/after images were inspected, and only 815 bottom pixels change, inside
BACK180's rectangle x=460..539, y=335..348. Top PPM is byte-identical, SHA-256
`cbabbac5b9a6e6c3421d66052bf7821d45787cbb2e04236903604eb69858362d`.
All pixels outside the affected label are identical, including graphics,
copper, mask, pads, holes and edges.

The full `scripts/check.sh` and `bend PROOF.bend` were attempted but fail
identically in a pristine archive of base `9fa67791e`: LAWS.bend:12128 has
an import after declarations; test/native/side_bench.bend:70 passes a thread
list where Side.rows.go expects State. These unrelated files were not edited.
No service build, installation, restart, user board edit or GUI change was made.
