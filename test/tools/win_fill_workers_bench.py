#!/usr/bin/env python3
"""One total-conversion comparison using retained screenshots as pixel inputs.

The image trees are reconstructed from pixels, not captured Bend heap nodes.
This component does not measure layout, rasterization, X, or app FPS.
"""
import collections
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'build/win-fill-workers'
SHOTS = Path('/home/h/Documents/i2cjak/bp-perf/chat-combined/build/chat-combined/telemetry-preview/profile/resume1/shots')
CHECK = json.loads((OUT / 'check-provenance.json').read_text())
sha = lambda p: hashlib.sha256(Path(p).read_bytes()).hexdigest()
assert sha(ROOT / 'src/app/effects/win.c') == CHECK['candidate_win_c_sha256']
assert sha(OUT / 'conversion-check.c') == CHECK['fixture_c_sha256']
source_records = []
for name in ['bub-chat-before', 'bub_chat', 'bub_scroll-before', 'bub_scroll-after']:
    source = SHOTS / (name + '.png')
    with Image.open(source) as image:
        assert image.size == (2556, 1398)
        image.convert('RGB').save(OUT / (name + '.ppm'))
    source_records.append({'name': name, 'png_sha256': sha(source),
                           'ppm_sha256': sha(OUT / (name + '.ppm'))})
source = r'''
#define main functional_main
#include "conversion-check.c"
#undef main
#include <time.h>

typedef struct { unsigned w,h; u32* pixels; } Frame;
static Frame frame(const char* path) {
  FILE* f=fopen(path,"rb");assert(f);unsigned w,h,max;
  assert(fscanf(f,"P6 %u %u %u",&w,&h,&max)==3 && max==255);
  assert(fgetc(f)=='\n');
  Frame out={w,h,malloc((size_t)w*h*4)};assert(out.pixels);
  for(size_t i=0;i<(size_t)w*h;i++) {
    unsigned char p[3];assert(fread(p,1,3,f)==3);
    out.pixels[i]=(u32)p[0]<<16|(u32)p[1]<<8|p[2];
  }
  assert(fgetc(f)==EOF);fclose(f);return out;
}
static Term from_frame(Tree* b, Frame f, unsigned x, unsigned y, unsigned n, Term old, bool reuse) {
  if(x>=f.w || y>=f.h)return 0;
  if(n==1)return f.pixels[(size_t)y*f.w+x];
  unsigned m=n/2;u64 at=0;
  bool branch=reuse && term_tag(old)==TAG_CTR;
  if(branch)at=win_src(b->H,old);
  Term oa=branch?b->H[at]:old,oc=branch?b->H[at+1]:old;
  Term od=branch?b->H[at+2]:old,oe=branch?b->H[at+3]:old;
  Term a=from_frame(b,f,x,y,m,oa,reuse),c=from_frame(b,f,x+m,y,m,oc,reuse);
  Term d=from_frame(b,f,x,y+m,m,od,reuse),e=from_frame(b,f,x+m,y+m,m,oe,reuse);
  if(a==c && a==d && a==e && term_tag(a)!=TAG_CTR)return a;
  if(branch && a==oa && c==oc && d==od && e==oe)return old;
  return ctr(b,a,c,d,e,false);
}
static uint64_t ns(void) {
  struct timespec t;assert(!clock_gettime(CLOCK_MONOTONIC,&t));
  return (uint64_t)t.tv_sec*1000000000ull+t.tv_nsec;
}
static void scenario(const char* label,const char* before,const char* after) {
  Frame a=frame(before),b=frame(after);assert(a.w==b.w&&a.h==b.h);
  Tree tree={calloc(32000000,8),1,32000000};assert(tree.H);
  unsigned n=1;while(n<a.w||n<a.h)n*=2;
  Term old=from_frame(&tree,a,0,0,n,0,false);
  Term next=!strcmp(before,after)?old:from_frame(&tree,b,0,0,n,old,true);
  unsigned dw=(a.w+63)/64,dh=(a.h+63)/64;
  size_t bytes=(size_t)a.w*a.h*4,blocks=(size_t)dw*dh;
  u32* pix=malloc(bytes),*oracle=malloc(bytes);u8* dirty=calloc(blocks,1),*expected=calloc(blocks,1);
  assert(pix&&oracle&&dirty&&expected);
  memcpy(oracle,a.pixels,bytes);
  win_fill(tree.H,oracle,a.w,a.h,expected,dw,next,0,0,n);
  assert(!memcmp(oracle,b.pixels,bytes));
  for(unsigned pair=0;pair<40;pair++)for(unsigned part=0;part<4;part++) {
    bool pooled=part==1||part==2;
    memcpy(pix,a.pixels,bytes);memset(dirty,0,blocks);
    unsigned prior=atomic_load(&created);
    uint64_t start=ns();
    if(pooled)win_fill_par(tree.H,pix,a.w,a.h,dirty,dw,next,old,n);
    else win_fill_original(tree.H,pix,a.w,a.h,dirty,dw,next,old,n);
    uint64_t elapsed=ns()-start;
    assert(!memcmp(pix,oracle,bytes));assert(!memcmp(dirty,expected,blocks));
    printf("{\"scenario\":\"%s\",\"path\":\"%s\",\"pair\":%u,\"part\":%u,\"ns\":%llu,\"threads_created\":%u,\"exact_pixels_dirty\":true}\n",
           label,pooled?"pool":"original",pair,part,(unsigned long long)elapsed,atomic_load(&created)-prior);
  }
  free(a.pixels);free(b.pixels);free(tree.H);free(pix);free(oracle);free(dirty);free(expected);
}
int main(void) {
  scenario("unchanged","bub-chat-before.ppm","bub-chat-before.ppm");
  scenario("stream","bub-chat-before.ppm","bub_chat.ppm");
  scenario("scroll","bub_scroll-before.ppm","bub_scroll-after.ppm");
  win_fill_workers_stop();return 0;
}
'''
(OUT / 'conversion-bench.c').write_text(source)
command = ['/usr/bin/clang-21', '-O3', '-gline-tables-only', '-pthread',
           str(OUT / 'conversion-bench.c'), '-o', str(OUT / 'conversion-bench')]
subprocess.run(command, check=True)
receipt = {'start': time.time(), 'load_before': Path('/proc/loadavg').read_text().strip(),
           'affinity': sorted(os.sched_getaffinity(0)),
           'scope': 'Reconstructed screenshot image trees; total dispatch+conversion ONLY, not app FPS',
           'base': CHECK['base'], 'candidate_win_c_sha256': CHECK['candidate_win_c_sha256'],
           'compiler': command[0], 'compiler_sha256': sha(command[0]), 'flags': command[1:5],
           'binary_sha256': sha(OUT / 'conversion-bench'), 'inputs': source_records}
(OUT / 'timing-receipt.json').write_text(json.dumps(receipt, indent=2)+'\n')
with (OUT / 'timing-samples.jsonl').open('w') as log:
    process = subprocess.Popen([str(OUT / 'conversion-bench')], cwd=OUT, stdout=log)
    receipt['captured_pid'] = process.pid
    try:
        rc = process.wait(timeout=90)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait()
        raise
receipt.update(end=time.time(), exit=rc, captured_pid_gone=not Path('/proc', str(process.pid)).exists(),
               load_after=Path('/proc/loadavg').read_text().strip(), fps_accepted=False)
cg=Path('/sys/fs/cgroup')/Path('/proc/self/cgroup').read_text().split('::')[-1].strip().lstrip('/')
receipt['resources']={n:(cg/n).read_text().strip() for n in ['memory.max','memory.peak','memory.events','memory.swap.max'] if (cg/n).exists()}
(OUT / 'timing-receipt.json').write_text(json.dumps(receipt, indent=2)+'\n')
assert rc==0,rc
groups=collections.defaultdict(list)
for line in (OUT/'timing-samples.jsonl').open():
    value=json.loads(line);assert value['exact_pixels_dirty']
    groups[(value['scenario'],value['path'])].append(value)
summary={}
for (scenario,path),values in groups.items():
    times=sorted(v['ns']/1000 for v in values)
    assert len(times)==80
    summary.setdefault(scenario,{})[path]={'n':len(times),'mean_us':sum(times)/len(times),
      'p50_us':times[len(times)//2],'p95_us':times[int(len(times)*.95)-1],
      'max_us':times[-1],'thread_creations':sum(v['threads_created'] for v in values)}
for values in summary.values():
    values['percent_mean_lower']=100*(1-values['pool']['mean_us']/values['original']['mean_us'])
(OUT/'timing-summary.json').write_text(json.dumps(summary,indent=2)+'\n')
print(json.dumps({'receipt':receipt,'summary':summary},indent=2))
