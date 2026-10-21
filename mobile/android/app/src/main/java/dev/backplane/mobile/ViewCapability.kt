package dev.backplane.mobile

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import java.util.concurrent.TimeUnit

// HTTP adapter only; shared thin.js owns RPCs, epochs, cursors and actions.
object ViewCapability {
    private val client = OkHttpClient.Builder().followRedirects(false).followSslRedirects(false)
        .callTimeout(2, TimeUnit.SECONDS).build()
    fun accepts(bytes: ByteArray): Boolean = runCatching {
        if (bytes.size > 16384) return false
        val o = JSONObject(bytes.toString(Charsets.UTF_8))
        val v = o.getJSONObject("views")
        o.get("version") == 1 && v.get("version") == 1 && v.get("websocketQuery") == "view=1" &&
            v.get("compatibility") == "explicit-only" && v.getJSONArray("renderers").let { a ->
                (0 until a.length()).any { a.get(it) == "mobile" }
            }
    }.getOrDefault(false)
    suspend fun discover(link: String): Boolean = withContext(Dispatchers.IO) {
        runCatching {
            val url = Pairing.http(link, "/client/capabilities", token = false) ?: return@withContext false
            val request = Request.Builder().url(url).header("Cache-Control", "no-cache")
            val token = android.net.Uri.parse(Pairing.socket(link)).getQueryParameter("token")
            if (token != null) request.header("Authorization", "Bearer $token")
            client.newCall(request.build()).execute().use { response ->
                if (response.code != 200) return@use false
                val body = response.body ?: return@use false
                if (body.contentLength() > 16384) return@use false
                val source = body.source()
                // Request one extra byte to reject, before allocating a body.
                if (source.request(16385)) return@use false
                accepts(source.readByteArray())
            }
        }.getOrDefault(false)
    }
}
