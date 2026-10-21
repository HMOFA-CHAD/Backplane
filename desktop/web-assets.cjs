'use strict';
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict'),{gunzipSync}=require('node:zlib');

// Follow the emitted graph and carry its verified gzip representations too.
// Old/unreferenced build chunks never enter the package.
function packageWebAssets(web,output){
 const seen=new Set();
 function asset(file){
  assert(!path.isAbsolute(file)&&!file.split('/').includes('..'),'Unsafe web asset path');
  if(seen.has(file))return;seen.add(file);
  const source=path.join(web,file),target=path.join(output,file);
  assert(fs.lstatSync(source).isFile(),'Web assets must be regular files');
  const bytes=fs.readFileSync(source);fs.mkdirSync(path.dirname(target),{recursive:true});fs.copyFileSync(source,target);
  const compressed=source+'.gz';
  if(fs.existsSync(compressed)){
   assert(fs.lstatSync(compressed).isFile(),'Compressed assets must be regular files');
   assert(gunzipSync(fs.readFileSync(compressed)).equals(bytes),'Compressed asset differs from '+file);
   fs.copyFileSync(compressed,target+'.gz');seen.add(file+'.gz');
  }
  if(/\.(html|js|css)$/.test(file)){
   const refs=[...bytes.toString('utf8').matchAll(/(?:["'(])(?:\.\/)?((?:chunk-|favicon-|apple-touch-icon-)[\w.-]+\.(?:js|css|svg|png))["')]/g)];
   for(const ref of refs)asset(ref[1]);
  }
 }
 asset('index.html');if(fs.existsSync(path.join(web,'sw.js')))asset('sw.js');
 return seen;
}
module.exports={packageWebAssets};
