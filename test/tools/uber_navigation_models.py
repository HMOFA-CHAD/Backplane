#!/usr/bin/env python3
"""Execute production Android JSON decoders on a host JVM; no Android build."""
from pathlib import Path
import glob, os, subprocess
root = Path(__file__).resolve().parents[2]
out = root / 'build/navigation/jvm'
out.mkdir(parents=True, exist_ok=True)
source = root / 'mobile/android/app/src/main/java/dev/backplane/mobile'
plane = (source/'Plane.kt').read_text()
space = (source/'SpaceView.kt').read_text()
# Copy only pure, byte-identical production model/decoder definitions.
pure = ('package dev.backplane.mobile\nimport org.json.JSONArray\nimport org.json.JSONObject\n' +
        plane[plane.index('data class UberCard('):plane.index('// a thread row\'s dot')] +
        space[space.index('data class SpaceBlock('):space.index('@Composable')])
pure += next(line for line in (source/'SpacePage.kt').read_text().splitlines(True) if line.startswith('data class SpacePageModel('))
(out/'PureViews.kt').write_text(pure)
for name in ['Screen.kt', 'MailroomModel.kt']:
    (out/name).write_bytes((source/name).read_bytes())
(out/'Check.kt').write_text(r'''
package dev.backplane.mobile
import org.json.JSONObject
fun main() {
    var n=0
    fun check(name: String, value: Boolean) { require(value) { name }; println("ok $name"); n++ }
    fun bot(o: JSONObject) = parseScreen(JSONObject().put("bot", o)).bot!!
    val old = JSONObject().put("kind","bot").put("id","b").put("name","Kit").put("tab","tasks")
    check("old cached route remains Tasks", bot(old).tab == "tasks")
    check("old payload parent falls back to route", bot(old).navTab == "tasks")
    check("old payload has no invented child panels", bot(old).subtabs.isEmpty())
    check("old payload has safe missing Mailroom", bot(old).mailroom == null && !bot(old).mailroomLoading)
    val current = JSONObject(old.toString()).put("navTab","browser").put("subtabs", org.json.JSONArray("[{\"id\":\"browser\",\"label\":\"Browser\"},{\"id\":\"tasks\",\"label\":\"Tasks\"}]"))
    check("new selected panel remains Tasks", bot(current).tab == "tasks")
    check("new parent decoded from Bend", bot(current).navTab == "browser")
    check("new nested panels decoded in order", bot(current).subtabs.map { it.id } == listOf("browser","tasks"))
    val hooks=JSONObject(old.toString()).put("tab","hooks").put("hooks",org.json.JSONArray("[{\"id\":\"h\",\"path\":\"/hook/h\"}]"))
    check("legacy hooks body retained", bot(hooks).hooks.single().path == "/hook/h")
    val settings=JSONObject(old.toString()).put("tab","settings").put("settings",JSONObject().put("persona","hello"))
    check("legacy settings retained", bot(settings).settings!!.persona == "hello")
    val unicode="α🍵\nFull body".repeat(300)
    val model=JSONObject().put("hub","phone:3787").put("origin","instance-1").put("owner","b").put("machine","Phone").put("online",true)
        .put("body",JSONObject().put("id","room:a|b").put("draft","keep draft").put("sendState","ack").put("to","bot:receiver")
            .put("messages",org.json.JSONArray().put(JSONObject().put("id","m").put("text",unicode).put("sourceURI","bp:thread/t")))
            .put("targets",org.json.JSONArray().put(JSONObject().put("address","bot:receiver").put("label","Receiver"))))
    val mail=mailroomModel(model)
    check("opaque conversation retains separator",mail.body!!.id == "room:a|b")
    check("Unicode body is complete",mail.body!!.messages.single().text == unicode)
    check("authoritative recipient retained",mail.body!!.targets.single().address == "bot:receiver")
    val decoded = bot(JSONObject(old.toString()).put("tab","mail").put("mailroom",model))
    check("parent Mailroom decodes real body",decoded.mailroom!!.body!!.id == "room:a|b")
    val request=JSONObject(MailroomAction.request(mail,"mail-send",draft="keep draft",recipient="bot:receiver"))
    check("hub kept separate from opaque ID",request.getString("hub") == "phone:3787" && request.getString("conversation") == "room:a|b")
    check("one send envelope contains exact draft and recipient",request.getString("draft") == "keep draft" && request.getString("recipient") == "bot:receiver")
    check("constructing request never clears draft",mail.body!!.draft == "keep draft")
    check("ACK remains busy",MailroomAction.busy("ack"))
    check("unknown outcome remains busy",MailroomAction.busy("unknown"))
    check("sending remains busy",MailroomAction.busy("sending"))
    check("error permits explicit retry",!MailroomAction.busy("error"))
    check("cached projection cannot become writable",MailroomAction.waiting(false,true,false))
    check("offline projection cannot become writable",MailroomAction.waiting(true,false,false))
    check("loading projection cannot become writable",MailroomAction.waiting(true,true,true))
    check("ready connected loaded projection writable",!MailroomAction.waiting(true,true,false))
    val link=JSONObject(MailroomAction.sourceRequest(mail,"bp:thread/t"))
    check("source uses qualified JSON routing",link.getString("hub") == mail.hub && link.getString("uri") == "bp:thread/t")
    check("current matching ready model allows action", MailroomAction.currentReady(true,true,mail,mail))
    check("captured ready click rejects current offline model", !MailroomAction.currentReady(true,true,mail,mail.copy(online=false)))
    check("captured ready click rejects current list loading", !MailroomAction.currentReady(true,true,mail,mail.copy(loading=true)))
    check("captured ready click rejects current body loading", !MailroomAction.currentReady(true,true,mail,mail.copy(body=mail.body!!.copy(loading=true))))
    check("captured ready click rejects missing current model", !MailroomAction.currentReady(true,true,mail,null))
    check("captured ready click rejects changed current origin", !MailroomAction.currentReady(true,true,mail,mail.copy(origin="other")))
    check("captured ready click rejects changed current owner", !MailroomAction.currentReady(true,true,mail,mail.copy(owner="other")))
    check("captured ready click rejects changed current conversation", !MailroomAction.currentReady(true,true,mail,mail.copy(body=mail.body!!.copy(id="other"))))
    check("captured ready click rejects unpaired hub", !MailroomAction.currentReady(true,false,mail,mail))
    val readyMail = mail.copy(body=mail.body!!.copy(sendState=""))
    check("current recipient menu accepts current target",MailroomAction.actionAllowed(readyMail,"mail-to","bot:receiver"))
    check("stale menu rejects target removed from current model",!MailroomAction.actionAllowed(readyMail.copy(body=readyMail.body!!.copy(targets=emptyList())),"mail-to","bot:receiver"))
    check("stale send rejects target removed from current model",!MailroomAction.actionAllowed(readyMail.copy(body=readyMail.body!!.copy(targets=emptyList())),"mail-send",recipient="bot:receiver"))
    check("current send accepts authoritative current target",MailroomAction.actionAllowed(readyMail,"mail-send",recipient="bot:receiver"))
    check("stale send rejects actual current ACK",!MailroomAction.actionAllowed(mail,"mail-send",recipient="bot:receiver"))
    check("stale send rejects actual current unknown outcome",!MailroomAction.actionAllowed(readyMail.copy(body=readyMail.body!!.copy(sendState="unknown")),"mail-send",recipient="bot:receiver"))
    check("stale recipient callback rejects missing current body",!MailroomAction.actionAllowed(null,"mail-to","bot:receiver"))
    println("PASS $n executed Android production model/action checks; no Android app build, install, live mailbox or send")
}
''')
lib=Path('/opt/gradle/gradle-8.14.3/lib')
jsonjar=glob.glob(str(Path.home()/'.gradle/caches/modules-2/files-2.1/org.json/json/*/*/*.jar'))[0]
ann=glob.glob(str(Path.home()/'.gradle/caches/modules-2/files-2.1/org.jetbrains/annotations/*/*/*.jar'))[0]
cp=os.pathsep.join([str(lib/'kotlin-stdlib-2.0.21.jar'),jsonjar,ann])
java='/usr/lib/jvm/java-17-openjdk-amd64/bin/java'
subprocess.run([java,'-Xmx768m','-cp',str(lib/'*'),'org.jetbrains.kotlin.cli.jvm.K2JVMCompiler','-no-stdlib','-no-reflect','-jvm-target','17','-classpath',cp,'-d',str(out/'classes'),*[str(out/n) for n in ['Screen.kt','MailroomModel.kt','PureViews.kt','Check.kt']]],check=True)
subprocess.run([java,'-cp',str(out/'classes')+os.pathsep+cp,'dev.backplane.mobile.CheckKt'],check=True)
