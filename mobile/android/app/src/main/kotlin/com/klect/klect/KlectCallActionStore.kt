package com.klect.klect

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

/** Durable native-to-Flutter call actions, safe across process recreation. */
object KlectCallActionStore {
    private const val PREFS = "klect_call_bridge"
    private const val ACTIONS = "queued_actions_v1"
    private val lock = Any()

    @Volatile
    var listener: ((Map<String, Any?>) -> Unit)? = null

    fun enqueue(context: Context, action: String, callId: String) {
        val item = mapOf<String, Any?>(
            "version" to 1,
            "eventId" to UUID.randomUUID().toString(),
            "action" to action,
            "callId" to callId,
            "createdAt" to System.currentTimeMillis(),
        )
        synchronized(lock) {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val queue = runCatching { JSONArray(prefs.getString(ACTIONS, "[]")) }
                .getOrDefault(JSONArray())
            val last = queue.optJSONObject(queue.length() - 1)
            if (last?.optString("action") != action || last.optString("callId") != callId) {
                queue.put(JSONObject(item))
            }
            while (queue.length() > 16) queue.remove(0)
            prefs.edit().putString(ACTIONS, queue.toString()).apply()
        }
        listener?.invoke(item)
    }

    fun drain(context: Context): List<Map<String, Any?>> = synchronized(lock) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val queue = runCatching { JSONArray(prefs.getString(ACTIONS, "[]")) }
            .getOrDefault(JSONArray())
        buildList {
            for (index in 0 until queue.length()) {
                val item = queue.optJSONObject(index) ?: continue
                add(
                    mapOf(
                        "version" to item.optInt("version", 1),
                        "eventId" to item.optString("eventId"),
                        "action" to item.optString("action"),
                        "callId" to item.optString("callId"),
                        "createdAt" to item.optLong("createdAt"),
                    ),
                )
            }
        }
    }

    fun ack(context: Context, eventId: String) = synchronized(lock) {
        if (eventId.isBlank()) return@synchronized
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val queue = runCatching { JSONArray(prefs.getString(ACTIONS, "[]")) }
            .getOrDefault(JSONArray())
        val remaining = JSONArray()
        for (index in 0 until queue.length()) {
            val item = queue.optJSONObject(index) ?: continue
            if (item.optString("eventId") != eventId) remaining.put(item)
        }
        prefs.edit().putString(ACTIONS, remaining.toString()).apply()
    }
}
