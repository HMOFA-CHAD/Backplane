package dev.backplane.mobile

import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest

// A bounded picture, separate from the type-keyed canonical state. Its bytes
// never enter Backplane.load or supply cursors, commands, drafts or resends.
class ScreenCache(private val file: File, private val report: (String) -> Unit = {}) {
    private var generation = 0L

    companion object {
        const val LIMIT = 512 * 1024
        fun identity(links: List<String>, profile: String): String? {
            val normalized = links.mapNotNull { Pairing.socket(it) }
            if (links.isEmpty() || normalized.size != links.size) return null
            return MessageDigest.getInstance("SHA-256").digest((listOf(profile) + normalized.sorted()).joinToString("\n").toByteArray())
                .joinToString("") { "%02x".format(it) }
        }
        // Walk at most 8192 Unicode code points from the end. UTF-16 slice
        // offsets can split a surrogate pair at the saved-text boundary.
        private fun textTail(body: String): String {
            var start = body.length
            var left = 8192
            while (start > 0 && left > 0) {
                start -= Character.charCount(body.codePointBefore(start))
                left -= 1
            }
            return body.substring(start)
        }
        private fun tail(rows: JSONArray, n: Int) = JSONArray().also { out ->
            for (i in maxOf(0, rows.length() - n) until rows.length()) out.put(rows.get(i))
        }
        private fun offlineActivity(screen: JSONObject): JSONObject {
            fun rows(values: JSONArray?) {
                if (values == null) return
                for (i in 0 until values.length()) values.optJSONObject(i)?.let { row ->
                    val status = row.optString("status")
                    if (status in setOf("active", "running", "watching", "cancelling", "working", "monitoring") ||
                        (status.isEmpty() && row.optString("state") == "run")) row.put("status", "inactive")
                }
            }
            fun plane(plane: JSONObject?) {
                if (plane == null) return
                plane.put("working", 0)
                for (key in listOf("need", "run", "idle", "bots", "routines", "locks")) plane.optJSONArray(key)?.let { values ->
                    for (i in 0 until values.length()) values.optJSONObject(i)?.let { row ->
                        val state = row.optString("state")
                        if (state in setOf("active", "working", "work", "talk", "think")) row.put("state", if (state == "active") "inactive" else "idle")
                    }
                }
            }
            screen.optJSONObject("thread")?.let { thread ->
                val phase = thread.optString("phase")
                if (phase in setOf("active", "running", "watching", "cancelling", "working", "monitoring") ||
                    (phase.isEmpty() && thread.optString("state") == "run")) thread.put("phase", "inactive")
                thread.put("working", "")
            }
            screen.optJSONArray("projects")?.let { projects ->
                for (i in 0 until projects.length()) projects.optJSONObject(i)?.let { project ->
                    for (key in listOf("threads", "snoozed", "settled", "archived")) rows(project.optJSONArray(key))
                }
            }
            rows(screen.optJSONArray("active"))
            plane(screen.optJSONObject("plane"))
            plane(screen.optJSONObject("bot")?.optJSONObject("plane"))
            screen.optJSONObject("bot")?.optJSONObject("mailroom")?.let { mail ->
                mail.put("online", false)
                mail.optJSONObject("body")?.put("draft", "")?.put("sendState", "")
            }
            screen.optJSONObject("uber")?.remove("counts")
            return screen
        }
        fun prepare(text: String, links: List<String>, profile: String): String? = runCatching {
            val owner = identity(links, profile) ?: return null
            val screen = offlineActivity(JSONObject(text).getJSONObject("screen"))
            if (links.none { Pairing.key(it) == screen.optString("hub") }) return null
            screen.put("online", false).put("making", false)
            for (key in listOf("rowMenu", "deleting", "removing", "renaming", "newBot", "newRoom", "tour", "folders", "find")) screen.remove(key)
            screen.optJSONObject("thread")?.let { thread ->
                thread.put("draft", "").put("sending", JSONArray()).put("attaching", JSONArray()).put("uploading", "")
                val all = thread.optJSONArray("entries") ?: JSONArray()
                val entries = tail(all, 40)
                thread.put("earlier", thread.optInt("earlier") + maxOf(0, all.length() - 40)).put("entries", entries)
                for (i in 0 until entries.length()) {
                    val e = entries.getJSONObject(i)
                    val body = e.optString("text")
                    if (body.toByteArray().size > 32768) {
                        val textTail = textTail(body)
                        e.put("partial", JSONObject().put("version", "").put("cursor", "").put("hasMore", false).put("complete", false))
                        e.put("text", textTail).put("blocks", JSONArray().put(JSONObject().put("tag", "p").put("kids", JSONArray().put(JSONObject().put("text", textTail)))))
                    }
                }
                for (key in listOf("diff", "term", "embs", "asks", "skills", "parent", "subs")) thread.remove(key)
                thread.optJSONArray("live")?.takeIf { it.toString().toByteArray().size > 32768 }?.let { live ->
                    val pending = java.util.ArrayDeque<JSONObject>()
                    for (i in live.length() - 1 downTo 0) pending.addLast(live.getJSONObject(i))
                    var body = ""
                    while (pending.isNotEmpty()) {
                        val node = pending.removeLast()
                        if (node.has("text")) body = textTail(body + node.optString("text"))
                        node.optJSONArray("kids")?.let { kids -> for (i in kids.length() - 1 downTo 0) pending.addLast(kids.getJSONObject(i)) }
                    }
                    thread.put("live", JSONArray().put(JSONObject().put("tag", "p").put("kids", JSONArray().put(JSONObject().put("text", body)))))
                    thread.put("livePartial", JSONObject().put("id", "").put("version", "").put("cursor", "").put("hasMore", false).put("complete", false))
                }
            }
            for (key in listOf("hubs", "usageMachines")) screen.optJSONArray(key)?.let { rows ->
                for (i in 0 until rows.length()) rows.getJSONObject(i).put("online", false)
            }
            val root = JSONObject().put("version", 2).put("identity", owner).put("screen", screen)
            var data = root.toString()
            if (data.toByteArray().size > LIMIT) {
                for (key in listOf("projects", "bots", "rooms", "active", "found", "usageMachines")) screen.put(key, JSONArray())
                screen.remove("plane")
                data = root.toString()
            }
            val thread = screen.optJSONObject("thread")
            while (data.toByteArray().size > LIMIT && thread != null) {
                val entries = thread.optJSONArray("entries") ?: break
                if (entries.length() <= 1) break
                val keep = maxOf(1, entries.length() / 2)
                thread.put("entries", tail(entries, keep)).put("earlier", thread.optInt("earlier") + entries.length() - keep)
                data = root.toString()
            }
            data.takeIf { it.toByteArray().size <= LIMIT }
        }.getOrNull()
    }
    @Synchronized fun save(text: String, links: List<String>, profile: String, generation: Long) {
        if (generation <= this.generation) return
        val data = prepare(text, links, profile) ?: run { report("save_shape_or_size"); return }
        val tmp = File(file.path + ".tmp")
        runCatching {
            tmp.writeText(data)
            check(tmp.renameTo(file))
            this.generation = generation
        }.onFailure { tmp.delete(); report("save_io") }
    }
    @Synchronized fun load(links: List<String>, profile: String): JSONObject? {
        if (!file.exists()) { report("miss_absent"); return null }
        if (file.length() !in 1..LIMIT.toLong()) { report("miss_size"); return null }
        val root = runCatching { JSONObject(file.readText()) }.getOrElse { report("miss_decode"); return null }
        if (root.optInt("version") != 2) { report("miss_schema"); return null }
        val owner = identity(links, profile)
        if (owner == null || root.optString("identity") != owner) { report("miss_identity"); return null }
        val screen = root.optJSONObject("screen")
        if (screen == null || links.none { Pairing.key(it) == screen.optString("hub") }) { report("miss_shape"); return null }
        report("hit")
        return offlineActivity(screen)
    }
    @Synchronized fun clear(through: Long) {
        generation = maxOf(generation, through)
        file.delete()
    }
    @Synchronized fun size(): Long = if (file.exists()) file.length() else 0
}
