package com.klect.klect

import java.time.Instant

/** Strict version-one call push envelope consumed before Flutter starts. */
data class KlectCallPushPayload(
    val callId: String,
    val conversationId: String,
    val callerId: String,
    val callerName: String,
    val kind: String,
    val expiresAt: Instant,
) {
    companion object {
        fun parse(
            data: Map<String, String>,
            now: Instant = Instant.now(),
        ): KlectCallPushPayload? {
            if (data["type"] != "call" || data["payload_version"] != "1") return null
            val callId = data["call_id"]?.takeIf(String::isNotBlank) ?: return null
            val conversationId = data["conversation_id"]?.takeIf(String::isNotBlank) ?: return null
            val callerId = data["caller_id"]?.takeIf(String::isNotBlank) ?: return null
            val kind = data["kind"]?.takeIf { it == "audio" || it == "video" } ?: return null
            val expiresAt = runCatching { Instant.parse(data["expires_at"]) }.getOrNull()
                ?: return null
            if (!expiresAt.isAfter(now)) return null
            return KlectCallPushPayload(
                callId = callId,
                conversationId = conversationId,
                callerId = callerId,
                callerName = data["caller_name"]?.takeIf(String::isNotBlank) ?: "Incoming call",
                kind = kind,
                expiresAt = expiresAt,
            )
        }
    }
}
