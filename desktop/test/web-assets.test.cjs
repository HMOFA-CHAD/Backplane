'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict');
const fs=require('node:fs'),path=require('node:path'),os=require('node:os'),{gzipSync}=require('node:zlib');
const {packageWebAssets}=require('../web-assets.cjs');
function fixture(t){const root=fs.mkdtempSync(path.join(os.tmpdir(),'bp-web-assets-'));t.after(()=>fs.rmSync(root,{recursive:true,force:true}));const web=path.join(root,'web'),out=path.join(root,'out');fs.mkdirSync(web);return{web,out};}
function put(web,name,value,gzip=false){fs.writeFileSync(path.join(web,name),value);if(gzip)fs.writeFileSync(path.join(web,name+'.gz'),gzipSync(value));}
test('packages the referenced graph and exact gzip siblings, excluding stale chunks',t=>{
 const {web,out}=fixture(t);put(web,'index.html','<script src="./chunk-main.js"></script>',true);put(web,'chunk-main.js','import "./chunk-style.css";',true);put(web,'chunk-style.css','body{color:red}',true);put(web,'sw.js','self.addEventListener("fetch",()=>{});',true);put(web,'chunk-old.js','obsolete',true);
 const files=packageWebAssets(web,out);assert.equal(files.size,8);for(const file of files)assert(fs.readFileSync(path.join(web,file)).equals(fs.readFileSync(path.join(out,file))));assert(!fs.existsSync(path.join(out,'chunk-old.js')));
});
test('rejects a stale compressed sibling rather than shipping different content',t=>{
 const {web,out}=fixture(t);put(web,'index.html','current');fs.writeFileSync(path.join(web,'index.html.gz'),gzipSync('old'));assert.throws(()=>packageWebAssets(web,out),/Compressed asset differs/);
});
test('supports older plain-only web artifacts',t=>{const {web,out}=fixture(t);put(web,'index.html','plain');assert.deepEqual([...packageWebAssets(web,out)],['index.html']);});
test('rejects symlinked gzip inputs',t=>{const {web,out}=fixture(t);put(web,'index.html','plain');fs.writeFileSync(path.join(web,'other'),gzipSync('plain'));fs.symlinkSync('other',path.join(web,'index.html.gz'));assert.throws(()=>packageWebAssets(web,out),/regular files/);});
