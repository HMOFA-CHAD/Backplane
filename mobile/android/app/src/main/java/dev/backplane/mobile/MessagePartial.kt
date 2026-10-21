package dev.backplane.mobile

import org.json.JSONObject

data class MessagePartial(val version: String, val cursor: String, val hasMore: Boolean, val complete: Boolean, val id: String = "") {
    val incomplete get() = !complete || hasMore
    val canRequest get() = !complete && hasMore && version.isNotEmpty() && cursor.isNotEmpty() && cursor.toByteArray().size <= 1024
}

fun messagePartial(o: JSONObject): MessagePartial {
    // Malformed metadata stays visibly incomplete and cannot issue a request.
    if (o.opt("version") !is String || o.opt("cursor") !is String || o.opt("hasMore") !is Boolean || o.opt("complete") !is Boolean)
        return MessagePartial("", "", false, false)
    return MessagePartial(o.getString("version"), o.getString("cursor"), o.getBoolean("hasMore"), o.getBoolean("complete"), o.opt("id") as? String ?: "")
}
