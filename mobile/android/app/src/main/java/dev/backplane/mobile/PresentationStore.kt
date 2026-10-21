package dev.backplane.mobile

import org.json.JSONObject
import java.io.File

// Shared loadPresentation validates the choices schema. No canonical file,
// body, draft, command or cursor is loaded by this separate bounded store.
class PresentationStore(private val file: File) {
    private var generation = 0L
    @Synchronized fun load(links: List<String>, profile: String): String? = runCatching {
        if (!file.exists() || file.length() !in 1..131072L) return null
        val root = JSONObject(file.readText())
        val identity = ScreenCache.identity(links, profile) ?: return null
        if (root.get("version") != 1 || root.get("identity") != identity) return null
        root.getJSONObject("presentation").toString().takeIf { it.toByteArray().size <= 65536 }
    }.getOrNull()
    @Synchronized fun save(text: String, links: List<String>, profile: String, generation: Long) {
        if (generation <= this.generation || text.toByteArray().size > 65536) return
        val identity = ScreenCache.identity(links, profile) ?: return
        val data = runCatching {
            val blob = JSONObject(text)
            if (blob.get("version") != 1) return
            JSONObject().put("version", 1).put("identity", identity).put("presentation", blob).toString()
        }.getOrNull()?.takeIf { it.toByteArray().size <= 131072 } ?: return
        val tmp = File(file.path + ".tmp")
        runCatching { tmp.writeText(data); check(tmp.renameTo(file)); this.generation = generation }
            .onFailure { tmp.delete() }
    }
    @Synchronized fun clear(through: Long) {
        generation = maxOf(generation, through)
        file.delete()
    }
}
