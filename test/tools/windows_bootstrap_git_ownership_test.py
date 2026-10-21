#!/usr/bin/env python3
"""Exercise the actual workflow's process-only Git ownership boundary."""
from pathlib import Path
import os
import re
import subprocess
import tempfile

workflow = Path(__file__).resolve().parents[2] / '.github/workflows/release-bootstrap.yml'
match = re.search(r'cd "\$1" && (env GIT_CONFIG_COUNT=[^\n]+?) python3 build/bootstrap-tools/scripts/release-bootstrap.py run', workflow.read_text())
assert match, 'scoped Windows bootstrap environment missing'
with tempfile.TemporaryDirectory(prefix='bp-git-ownership-日本 ') as temporary:
    home = Path(temporary)
    product = home / 'product source'
    tools = product / 'build/bootstrap-tools'
    other = home / 'unrelated'
    config = home / 'global.gitconfig'
    for repository in (product, tools, other):
        repository.mkdir(parents=True)
        subprocess.run(['git', 'init', '-q', str(repository)], check=True)
    environment = {k: v for k, v in os.environ.items() if not k.startswith('GIT_CONFIG_')}
    environment.update(GIT_TEST_ASSUME_DIFFERENT_OWNER='1', GIT_CONFIG_GLOBAL=str(config), GIT_CONFIG_NOSYSTEM='1')
    before = subprocess.run(['git', 'rev-parse', '--is-inside-work-tree'], cwd=product, env=environment, capture_output=True, text=True)
    assert before.returncode == 128 and 'dubious ownership' in before.stderr
    command = 'cd "$1" && ' + match[1] + ' git -C "$2" rev-parse --is-inside-work-tree'
    for repository in (product, tools):
        result = subprocess.run(['bash', '-c', command, '_', str(product), str(repository)], env=environment, capture_output=True, text=True)
        assert result.returncode == 0 and result.stdout.strip() == 'true', result.stderr
    refused = subprocess.run(['bash', '-c', command, '_', str(product), str(other)], env=environment, capture_output=True, text=True)
    assert refused.returncode == 128 and 'dubious ownership' in refused.stderr
    assert not config.exists(), 'workflow wrote global Git configuration'
print('PASS five actual Git ownership boundaries using exact workflow environment')
