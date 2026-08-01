package com.klect.klect

import android.content.Intent
import androidx.core.content.ContextCompat
import com.google.firebase.messaging.RemoteMessage
import io.flutter.plugins.firebase.messaging.FlutterFirebaseMessagingService

/** Consumes versioned high-priority, data-only call pushes natively. */
class KlectFirebaseMessagingService : FlutterFirebaseMessagingService() {
    override fun onMessageReceived(message: RemoteMessage) {
        super.onMessageReceived(message)
        val payload = KlectCallPushPayload.parse(message.data) ?: return

        val intent = Intent(this, KlectCallService::class.java)
            .setAction(KlectCallService.ACTION_PRESENT_INCOMING)
            .putExtra(KlectCallService.EXTRA_CALL_ID, payload.callId)
            .putExtra(KlectCallService.EXTRA_CONVERSATION_ID, payload.conversationId)
            .putExtra(KlectCallService.EXTRA_CALLER_ID, payload.callerId)
            .putExtra(KlectCallService.EXTRA_CALLER_NAME, payload.callerName)
            .putExtra(KlectCallService.EXTRA_KIND, payload.kind)
            .putExtra(KlectCallService.EXTRA_EXPIRES_AT, payload.expiresAt.toString())
        ContextCompat.startForegroundService(this, intent)
    }
}
