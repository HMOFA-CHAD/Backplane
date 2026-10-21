#!/usr/bin/env python3
"""Compile the exact opt-in recorder extracted from win.c; no X/app launch."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time

root=Path(__file__).resolve().parents[2]
source=(root/'src/app/effects/win.c').read_text()
code=source[source.index('// Frame identity diagnostics (opt-in).'):source.index('// End frame identity diagnostics.')]
clock=source[source.index('static uint64_t win_us(void) {'):]
clock=clock[:clock.index('\n}')+2]
show=source[source.index('static void win_show_image('):source.index('static void win_show_image(')+6500]
assert show.index('win_fill_par(')<show.index('win_frame_record_before(')<show.index('x_XPutImage(')
assert show.index('x_XFlush(')<show.index('win_frame_record_after(')<show.index('win_snap(')
assert 'undefined' not in source
out=root/'build/frame-record'
out.mkdir(parents=True,exist_ok=False)
prefix='''#define _GNU_SOURCE
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <time.h>
#include <dlfcn.h>
#include <pthread.h>
typedef uint32_t u32;
'''
main=r'''
static void pixels(u32* p) {
  for (u32 i=0;i<12;i++) p[i]=0xaa000000u|(i<<16)|((i+20)<<8)|(i+40);
}
static void* parallel(void* unused) {
  (void)unused;u32 p[12];pixels(p);
  for (int i=0;i<5;i++) { WinFrameSample s=win_frame_record_before(p,4,3);win_frame_record_after(s,19,win_us()); }
  return NULL;
}
int main(int argc,char** argv) {
  if (argc>1 && !strcmp(argv[1],"parallel")) {
    pthread_t ts[4];
    for (int i=0;i<4;i++) if(pthread_create(&ts[i],NULL,parallel,NULL)) return 3;
    for (int i=0;i<4;i++) pthread_join(ts[i],NULL);
    return 0;
  }
  u32 p[12];pixels(p);
  WinFrameSample s=win_frame_record_before(p,4,3);win_frame_record_after(s,17,win_us());
  p[0]^=1; s=win_frame_record_before(p,4,3);win_frame_record_after(s,17,win_us());
  p[6]^=1; s=win_frame_record_before(p,4,3);win_frame_record_after(s,17,win_us());
  s=win_frame_record_before(p,4,3);win_frame_record_after(s,18,win_us());
  p[5]^=0xff000000; s=win_frame_record_before(p,4,3);win_frame_record_after(s,18,win_us());
  return 0;
}
'''
c=out/'exact-recorder.c';c.write_text(prefix+clock+'\n'+code+main)
exe=out/'exact-recorder'
commands=[]
def run(argv,env=None):
    proc=subprocess.Popen(argv,env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
    birth=Path(f'/proc/{proc.pid}/stat').read_text().rsplit(')',1)[1].split()[19]
    try:stdout,stderr=proc.communicate(timeout=25)
    finally:
        if proc.poll() is None:proc.kill();proc.wait(timeout=3)
    commands.append(dict(pid=proc.pid,birth=birth,exit=proc.returncode,gone=not Path(f'/proc/{proc.pid}').exists()))
    assert proc.returncode==0,stderr.decode(errors='replace')
    return stdout,stderr

start=time.time()
run(['/usr/bin/clang-21','-O3','-std=c11','-Wall','-Wextra','-Werror','-fintegrated-cc1',str(c),'-ldl','-pthread','-o',str(exe)])
checks=0
def expect(ok,why):
    global checks
    assert ok,why
    checks+=1

with tempfile.TemporaryDirectory(prefix='bp-frame-record-') as directory:
    d=Path(directory)
    env={k:v for k,v in os.environ.items() if k not in ['BACKPLANE_FRAME_RECORD','BACKPLANE_FRAME_ROI']}
    stdout,stderr=run([str(exe)],env)
    expect(not stdout and not stderr and not list(d.iterdir()),'default disabled is a silent no-op')
    log=d/'frames.jsonl';env.update(BACKPLANE_FRAME_RECORD=str(log),BACKPLANE_FRAME_ROI='timeline:1:1:2:2')
    run([str(exe)],env)
    rows=[json.loads(x) for x in log.read_text().splitlines()]
    expected=bytes(v for i in [5,6,9,10] for v in [i,i+20,i+40])
    changed=bytearray(expected);changed[5]^=1
    h0=hashlib.sha256(expected).hexdigest();h1=hashlib.sha256(changed).hexdigest()
    expect(len(rows)==5 and [r['frame'] for r in rows]==list(range(1,6)),'actual call frame identities')
    expect([r['pixel_sha256'] for r in rows]==[h0,h0,h1,h1,h1],'exact RGB/ROI; outside pixel and alpha ignored')
    expect(all(r['region']=='timeline' and (r['x'],r['y'],r['width'],r['height'])==(1,1,2,2) for r in rows),'exact region binding')
    expect([r['window'] for r in rows]==[17,17,17,18,18],'window identities retained')
    expect(all(r['drawn_us']<=r['flush_return_us'] and r['hash_us']>=0 for r in rows),'draw/flush timestamps ordered')
    expect(all(r['presentation_verified'] is False and 'revision' not in r and 'features' not in r for r in rows),'no invented presentation or semantic labels')
    expect((log.stat().st_mode&0o777)==0o600,'private journal mode')
    for i,roi in enumerate(['timeline:-1:0:2:2','timeline:0:0:0:2','timeline:0:0:2:16385',
                            'timeline:0:0:2:2junk','bad"id:0:0:2:2','timeline:3:2:2:2']):
        path=d/f'bad-{i}';test={**env,'BACKPLANE_FRAME_RECORD':str(path),'BACKPLANE_FRAME_ROI':roi}
        _,error=run([str(exe)],test)
        expect(bool(error) and (not path.exists() or path.stat().st_size==0),'malformed/out-of-frame ROI produces no credited frame')
    target=d/'untouched';target.write_text('retained')
    link=d/'symlink';link.symlink_to(target)
    _,error=run([str(exe)],{**env,'BACKPLANE_FRAME_RECORD':str(link)})
    expect(bool(error) and target.read_text()=='retained','symlink sink refused')
    fifo=d/'fifo';os.mkfifo(fifo)
    _,error=run([str(exe)],{**env,'BACKPLANE_FRAME_RECORD':str(fifo)})
    expect(bool(error),'nonregular sink fails without blocking')
    parallel_log=d/'parallel.jsonl'
    run([str(exe),'parallel'],{**env,'BACKPLANE_FRAME_RECORD':str(parallel_log)})
    parallel_rows=[json.loads(x) for x in parallel_log.read_text().splitlines()]
    expect(len(parallel_rows)==20 and sorted(r['frame'] for r in parallel_rows)==list(range(1,21)),'concurrent record identities unique')
    expect(all(r['pixel_sha256']==h0 for r in parallel_rows),'concurrent buffers hashed exactly')
    (out/'frames.jsonl').write_text(log.read_text())
    (out/'parallel.jsonl').write_text(parallel_log.read_text())

receipt={'pass':True,'checks':checks,'start':start,'end':time.time(),'scope':'exact C recorder unit/integration-order controls ONLY; not app/frame/FPS acceptance',
         'source_sha256':hashlib.sha256(source.encode()).hexdigest(),'extracted_c_sha256':hashlib.sha256(c.read_bytes()).hexdigest(),
         'binary_sha256':hashlib.sha256(exe.read_bytes()).hexdigest(),'commands':commands}
assert all(p['gone'] for p in commands)
(out/'result.json').write_text(json.dumps(receipt,indent=2)+'\n')
print(json.dumps({k:v for k,v in receipt.items() if k!='commands'}))
