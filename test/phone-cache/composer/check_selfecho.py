#!/usr/bin/env python3
"""Exercise production ImageComposer effect bodies with deterministic fast-edit order.

Host JVM control, not an Android IME or UI runtime claim.
"""
from pathlib import Path
import subprocess,os,argparse
p=argparse.ArgumentParser();p.add_argument('source',type=Path);p.add_argument('output',type=Path);a=p.parse_args()
s=a.source.read_text();start=s.index('private fun ImageComposer(');s=s[start:]
def body(marker):
 i=s.index(marker)+len(marker);depth=1;j=i
 while depth:
  if s[j]=='{':depth+=1
  elif s[j]=='}':depth-=1
  j+=1
 return s[i:j-1]
model=body('LaunchedEffect(m.composer) {')
field=body('snapshotFlow { field.text.toString() }.collect { text ->')
a.output.mkdir(parents=True,exist_ok=True)
code='''class Field(var text: String) {
 var cursor = text.length
 var writes = 0
 fun setTextAndPlaceCursorAtEnd(value: String) { text=value; cursor=value.length; writes++ }
}
class Model(var composer: String) { var calls=0; fun draft(text:String) { calls++;composer=text } }
class Harness(initial:String) {
 val m=Model(initial); val field=Field(initial); var forwardedDraft=initial
 fun modelEffect() { MODEL }
 fun fieldEffect() { val text=field.text; FIELD }
}
fun main() {
 val fast=Harness("an")
 fast.field.text="and";fast.fieldEffect()
 fast.field.text="andr";fast.field.cursor=2
 fast.modelEffect()
 check(fast.field.text=="andr" && fast.field.cursor==2 && fast.field.writes==0) { "self echo must not overwrite newer field or cursor" }
 fast.fieldEffect();check(fast.m.composer=="andr")
 fast.modelEffect();check(fast.field.writes==0)
 fast.m.composer="";fast.modelEffect();check(fast.field.text=="" && fast.forwardedDraft=="") { "external clear must update both field and echo marker" }
 fast.fieldEffect();check(fast.m.calls==2) { "external clear cannot echo a draft action" }
 fast.m.composer="andr";fast.modelEffect();check(fast.field.text=="andr") { "restore previous draft after clear must apply" }
 fast.m.composer="other thread draft";fast.modelEffect();check(fast.field.text=="other thread draft" && fast.forwardedDraft=="other thread draft")
 fast.m.composer="";fast.modelEffect();check(fast.field.text=="")
 val fresh=Harness("cached draft");fresh.modelEffect();fresh.fieldEffect();check(fresh.field.writes==0 && fresh.m.calls==0)
 println("PASS production ImageComposer effect bodies: fast field ahead/self echo retains text+cursor; external clear, restore previous, navigation, send clear, initial restore; no extra draft dispatch")
}
'''.replace('MODEL',model).replace('FIELD',field)
kt=a.output/'SelfEcho.kt';kt.write_text(code)
cache=Path.home()/'.gradle/caches/modules-2/files-2.1'
def jar(group,name,version):
 files=list((cache/group/name/version).glob('*/*.jar'));assert len(files)==1,(name,files);return str(files[0])
compiler=[jar('org.jetbrains.kotlin',n,'2.0.21') for n in ['kotlin-compiler-embeddable','kotlin-stdlib','kotlin-script-runtime','kotlin-reflect']]
compiler += [jar('org.jetbrains.intellij.deps','trove4j','1.0.20200330'),jar('org.jetbrains.kotlinx','kotlinx-coroutines-core-jvm','1.6.4')]
cp=[compiler[1],str(sorted((cache/'org.jetbrains/annotations').glob('*/*/*.jar'))[-1])]
classes=a.output/'classes';classes.mkdir(exist_ok=True)
java='/usr/lib/jvm/java-17-openjdk-amd64/bin/java'
subprocess.run([java,'-Xmx512m','-cp',os.pathsep.join(compiler+cp),'org.jetbrains.kotlin.cli.jvm.K2JVMCompiler','-no-stdlib','-no-reflect','-classpath',os.pathsep.join(cp),'-d',str(classes),str(kt)],check=True)
subprocess.run([java,'-cp',os.pathsep.join([str(classes)]+cp),'SelfEchoKt'],check=True)
