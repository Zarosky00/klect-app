package com.klect.klect

import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class KlectCallPushPayloadTest {
    private val now = Instant.parse("2026-08-01T12:00:00Z")
    private val valid = mapOf(
        "type" to "call",
        "payload_version" to "1",
        "call_id" to "call-1",
        "conversation_id" to "conversation-1",
        "caller_id" to "caller-1",
        "caller_name" to "Akash",
        "kind" to "video",
        "expires_at" to "2026-08-01T12:00:45Z",
    )

    @Test
    fun `parses a current versioned call envelope`() {
        val payload = KlectCallPushPayload.parse(valid, now)
        assertEquals("call-1", payload?.callId)
        assertEquals("conversation-1", payload?.conversationId)
        assertEquals("Akash", payload?.callerName)
        assertEquals("video", payload?.kind)
    }

    @Test
    fun `rejects unsupported, incomplete and stale envelopes`() {
        assertNull(KlectCallPushPayload.parse(valid + ("payload_version" to "2"), now))
        assertNull(KlectCallPushPayload.parse(valid - "caller_id", now))
        assertNull(KlectCallPushPayload.parse(valid + ("kind" to "screen"), now))
        assertNull(
            KlectCallPushPayload.parse(
                valid + ("expires_at" to "2026-08-01T12:00:00Z"),
                now,
            ),
        )
    }

    @Test
    fun `falls back to a safe caller label`() {
        val payload = KlectCallPushPayload.parse(valid + ("caller_name" to ""), now)
        assertTrue(payload != null)
        assertEquals("Incoming call", payload?.callerName)
    }
}
