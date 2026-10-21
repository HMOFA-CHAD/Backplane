#!/usr/bin/env python3
"""Build a small C oracle from the actual old/new conversion routines.

No X server, app build, timing assertion, or production runtime substitution.
The term bit layout matches retained Bend 2.0.36 emitted C.
"""
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'build/win-fill-workers'
OUT.mkdir(parents=True, exist_ok=True)
old = subprocess.check_output(['git', 'show', '947b9c346:src/app/effects/win.c'], cwd=ROOT, text=True)
new = (ROOT / 'src/app/effects/win.c').read_text()

def between(source, start, end):
    return source[source.index(start):source.index(end, source.index(start))]

pixels = between(new, 'static inline void win_px(', '// readings for the perf table')
assert pixels == between(old, 'static inline void win_px(', '// readings for the perf table')
walk = between(new, 'static inline u64 win_src(', '// Conversion jobs borrow')
assert walk == between(old, 'static inline u64 win_src(', '// win_fill_diff over the frame, the large changes split over threads')
new_pool = between(new, '// Conversion jobs borrow', '// Frame identity diagnostics (opt-in).' if '// Frame identity diagnostics (opt-in).' in new else '// BACKPLANE_SNAP=')
old_run = between(old, 'static void win_fill_par(', '// BACKPLANE_SNAP=').replace('win_fill_par(', 'win_fill_original(', 1)
header = r'''
#define _GNU_SOURCE
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include <stdatomic.h>
#include <errno.h>
typedef uint64_t u64;
typedef uint32_t u32;
typedef uint8_t u8;
typedef u64 Term;
#define TAG_CTR 2ull
#define RFC_BIT (1ull << 63)
#define LOC_MASK ((1ull << 40) - 1)
static inline u64 term_tag(Term t) { return (t >> 56) & 0x7f; }
static inline bool term_rfc(Term t) { return (t & RFC_BIT) != 0; }
static inline u64 term_loc(Term t) { return t & LOC_MASK; }
static _Atomic unsigned attempts, created, fail_every;
static int counted_create(pthread_t* t, const pthread_attr_t* a, void* (*f)(void*), void* p) {
  unsigned n = atomic_fetch_add(&attempts, 1) + 1;
  unsigned fail = atomic_load(&fail_every);
  if (fail && n % fail == 0) return EAGAIN;
  int rc = pthread_create(t, a, f, p);
  if (!rc) atomic_fetch_add(&created, 1);
  return rc;
}
#define pthread_create counted_create
'''
checks = r'''
static pthread_mutex_t oracle_lock=PTHREAD_MUTEX_INITIALIZER;
static _Atomic int concurrent_checks;
typedef struct { u64* H; size_t used, cap; } Tree;
static u64 put(Tree* b, const u64* values, size_t n) {
  assert(b->used + n < b->cap);
  u64 at = b->used;
  memcpy(b->H + at, values, n * sizeof *values);
  b->used += n;
  return at;
}
static Term ctr(Tree* b, Term a, Term c, Term d, Term e, bool shared) {
  u64 values[] = {a,c,d,e};
  u64 at = put(b, values, 4);
  if (!shared) return (TAG_CTR << 56) | at;
  u64 count = at << 24 | 2;
  return RFC_BIT | (TAG_CTR << 56) | put(b, &count, 1);
}
static Term image(Tree* b, unsigned depth, unsigned seed) {
  if (!depth) return (seed * 2654435761u) & 0xffffff;
  Term a = image(b, depth-1, seed*4+1);
  Term c = image(b, depth-1, seed*4+2);
  Term d = image(b, depth-1, seed*4+3);
  Term e = image(b, depth-1, seed*4+4);
  return ctr(b,a,c,d,e,seed%3==0);
}
static Term changed(Tree* b, Term old, unsigned size, unsigned phase, unsigned x, unsigned y) {
  if (size <= 128 && ((x/128 + y/128*5 + phase)%5 == 0)) return old;
  if (size <= 128) return image(b, phase%2 ? 2 : 1, phase+x+y+1);
  u64 at = win_src(b->H,old); unsigned half=size/2;
  Term a=changed(b,b->H[at],half,phase,x,y);
  Term c=changed(b,b->H[at+1],half,phase,x+half,y);
  Term d=changed(b,b->H[at+2],half,phase,x,y+half);
  Term e=changed(b,b->H[at+3],half,phase,x+half,y+half);
  return ctr(b,a,c,d,e,phase%2==0);
}
static void one(unsigned size, unsigned w, unsigned h, unsigned phase, unsigned mode) {
  Tree tree={calloc(8000000,sizeof(u64)),1,8000000}; assert(tree.H);
  Term old=image(&tree,10,7);
  Term next= mode==0 ? old : mode==1 ? changed(&tree,old,size,phase,0,0) : image(&tree,10,phase+20);
  unsigned dw=(w+63)/64,dh=(h+63)/64;
  size_t pixels=(size_t)w*h,blocks=(size_t)dw*dh;
  u32* before=calloc(pixels,4),*a=malloc(pixels*4),*b=malloc(pixels*4),*fresh=malloc(pixels*4);
  u8* scratch=calloc(blocks,1),*da=calloc(blocks,1),*db=calloc(blocks,1),*df=calloc(blocks,1);
  assert(before&&a&&b&&fresh&&scratch&&da&&db&&df);
  win_fill(tree.H,before,w,h,scratch,dw,old,0,0,size);
  memcpy(a,before,pixels*4);memcpy(b,before,pixels*4);memcpy(fresh,before,pixels*4);
  pthread_mutex_lock(&oracle_lock);
  win_fill_original(tree.H,a,w,h,da,dw,next,old,size);
  pthread_mutex_unlock(&oracle_lock);
  unsigned prior=atomic_load(&created);
  win_fill_par(tree.H,b,w,h,db,dw,next,old,size);
  win_fill(tree.H,fresh,w,h,df,dw,next,0,0,size);
  assert(!memcmp(a,b,pixels*4));assert(!memcmp(a,fresh,pixels*4));
  assert(!memcmp(da,db,blocks));assert(!memcmp(da,df,blocks));
  pthread_mutex_lock(&win_fill_pool.turn);
  for (unsigned i=0;i<8;i++) {
    const unsigned char* p=(const unsigned char*)&win_fill_pool.jobs[i];
    for(size_t j=0;j<sizeof(WinLane);j++)assert(p[j]==0);
  }
  pthread_mutex_unlock(&win_fill_pool.turn);
  if (phase>1 && !atomic_load(&concurrent_checks)) assert(atomic_load(&created)==prior);
  free(tree.H);free(before);free(a);free(b);free(fresh);free(scratch);free(da);free(db);free(df);
}
static void* concurrent(void* arg) {
  unsigned offset=(unsigned)(uintptr_t)arg;
  for(unsigned i=2;i<6;i++)one(1024,1001-offset,777-offset,i,1);
  return NULL;
}
int main(void) {
  unsigned cases=0;
  // Shared and plain nodes, edge clips, identical frames, and part-limit fallback.
  for(unsigned mode=0;mode<3;mode++)for(unsigned phase=1;phase<=6;phase++) {
    one(1024,1001,777,phase,mode);++cases;
  }
  win_fill_workers_stop();
  atomic_store(&fail_every,1);
  for(unsigned i=1;i<5;i++){one(1024,1001,777,i,1);++cases;}
  win_fill_workers_stop();
  atomic_store(&fail_every,3);
  for(unsigned i=1;i<5;i++){one(1024,1001,777,i,1);++cases;}
  win_fill_workers_stop();
  atomic_store(&fail_every,0);
  one(1024,1001,777,1,1);++cases;
  pthread_t a,b;
  atomic_store(&concurrent_checks,1);
  assert(!counted_create(&a,NULL,concurrent,(void*)(uintptr_t)1));
  assert(!counted_create(&b,NULL,concurrent,(void*)(uintptr_t)2));
  pthread_join(a,NULL);pthread_join(b,NULL);cases+=8;
  win_fill_workers_stop();
  atomic_store(&concurrent_checks,0);
  one(1024,97,65,1,1);++cases;
  one(2048,2048,2048,1,2);++cases;
  win_fill_workers_stop();
  puts("PASS exact old/new/fresh pixels+dirty blocks, shared nodes, unchanged/changed/overflow, creation failure, concurrent callers and shutdown/restart");
  printf("{\"cases\":%u,\"thread_attempts\":%u,\"threads_created\":%u,\"timing_acceptance\":false}\n",cases,atomic_load(&attempts),atomic_load(&created));
  return 0;
}
'''
c = OUT / 'conversion-check.c'
c.write_text(header + pixels + walk + new_pool + old_run + checks)
binary = OUT / 'conversion-check'
command = ['/usr/bin/clang-21', '-O3', '-gline-tables-only', '-pthread', '-Wall', '-Wextra', str(c), '-o', str(binary)]
subprocess.run(command, check=True)
provenance = {'base':'947b9c346a35875a19e9e58e926899c0a9aef7f9',
              'original_win_c_sha256':hashlib.sha256(old.encode()).hexdigest(),
              'candidate_win_c_sha256':hashlib.sha256(new.encode()).hexdigest(),
              'fixture_c_sha256':hashlib.sha256(c.read_bytes()).hexdigest(),
              'binary_sha256':hashlib.sha256(binary.read_bytes()).hexdigest(),
              'compiler':command[0], 'flags':command[1:-3],
              'scope':'functional pixel/dirty/lifecycle checks ONLY; no FPS timing'}
(OUT / 'check-provenance.json').write_text(json.dumps(provenance,indent=2)+'\n')
subprocess.run([str(binary)], check=True, timeout=90)
