"""Read-only PCB plot regression: inherited hub marker + child 8 MiB stack.

Run with the combined candidate binary and an existing board fixture:
    python3 test/tools/plot_stack_child_test.py BINARY BOARD.kicad_pcb
Output and info files stay in a temporary folder; BOARD is never written.
"""
import json
import os
from pathlib import Path
import resource
import subprocess
import sys
import tempfile
import time

binary, board = (Path(arg).resolve(strict=True) for arg in sys.argv[1:3])
if sys.platform not in ('linux', 'darwin'):
    raise SystemExit('POSIX stack regression only')

def child_stack():
    _, hard = resource.getrlimit(resource.RLIMIT_STACK)
    resource.setrlimit(resource.RLIMIT_STACK, (8 * 1024 * 1024, hard))

env = dict(os.environ, BACKPLANE_STACK_SET=str(os.getpid()),
           BUN_JSC_maxPerThreadStackUsage='4000000000', BACKPLANE_TELEMETRY='off')
with tempfile.TemporaryDirectory(prefix='bp-plot-stack-') as folder:
    out = Path(folder)
    began = time.monotonic()
    with (out / 'board.plot').open('wb') as stdout:
        result = subprocess.run([str(binary), '--plot', '0', str(board), str(out / 'board.info')],
            env=env, preexec_fn=child_stack, stdout=stdout, stderr=subprocess.PIPE, timeout=25)
    size = (out / 'board.plot').stat().st_size
    assert result.returncode == 0, result.stderr.decode(errors='replace')[:1000]
    assert size > 0 and (out / 'board.info').stat().st_size > 0, 'missing real board plot/info'
    print(json.dumps({'state':'passed','scope':'real PCB plot child with inherited parent marker',
        'plot_bytes':size,'seconds':round(time.monotonic()-began,3)}))
