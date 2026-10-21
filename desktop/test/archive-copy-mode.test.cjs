'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),os=require('node:os'),vm=require('node:vm');
const file=process.env.BP_COPY_PRODUCER||path.join(__dirname,'../produce-release.cjs'),source=fs.readFileSync(file,'utf8'),context={require,module:{exports:{}},process,Buffer,__dirname:path.dirname(file)};
vm.runInNewContext(source+'\nmodule.exports.copyForTest=copy;',context);const producer=context.module.exports;
test('archive copy preserves exact Unix modes, bytes and relative symlink under restrictive umask',()=>{
 if(process.platform==='win32')return;
 const root=fs.mkdtempSync(path.join(os.tmpdir(),'bp-archive-copy-test-')),src=path.join(root,'source'),dst=path.join(root,'dest');fs.mkdirSync(src);fs.mkdirSync(path.join(src,'nested'));
 for(const [name,mode]of [['group-write',0o664],['readonly',0o444],['executable',0o755]]){const f=path.join(src,'nested',name);fs.writeFileSync(f,'exact_日本語');fs.chmodSync(f,mode);}fs.symlinkSync('nested/group-write',path.join(src,'link'));
 const old=process.umask(0o077);try{producer.copyForTest(src,dst,true);assert.deepEqual(producer.inventory(dst,'darwin-arm64'),producer.inventory(src,'darwin-arm64'));}finally{process.umask(old);fs.rmSync(root,{recursive:true,force:true});}
});
test('only final archive copy requests preserving per-file path; exact payload guard remains',()=>{
 assert.equal((source.match(/copy\(stageDir,finalRoot,true\)/g)||[]).length,1);
 assert(source.includes("check(contentDigest(content(finalRoot,s.target))===payloadHash,'Payload changed while archiving')"));
 assert(source.includes('dereference:false,verbatimSymlinks:true,errorOnExist:true,force:false'));
});
