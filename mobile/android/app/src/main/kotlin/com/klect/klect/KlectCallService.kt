package com.klect.klect

import android.app.Service
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import androidx.core.app.NotificationManagerCompat
import java.time.Instant

/** Owns Core-Telecom registration and the required foreground call surface. */
class KlectCallService : Service() {
    companion object {
        const val ACTION_PRESENT_INCOMING = "com.klect.klect.call.PRESENT_INCOMING"
        const val ACTION_PRESENT_OUTGOING = "com.klect.klect.call.PRESENT_OUTGOING"
        const val ACTION_ANSWER = "com.klect.klect.call.ANSWER"
        const val ACTION_DECLINE = "com.klect.klect.call.DECLINE"
        const val ACTION_HANGUP = "com.klect.klect.call.HANGUP"
        const val ACTION_ACTIVE = "com.klect.klect.call.ACTIVE"
        const val ACTION_END = "com.klect.klect.call.END"

        const val EXTRA_CALL_ID = "call_id"
        const val EXTRA_CONVERSATION_ID = "conversation_id"
        const val EXTRA_CALLER_ID = "caller_id"
        const val EXTRA_CALLER_NAME = "caller_name"
        const val EXTRA_KIND = "kind"
        const val EXTRA_EXPIRES_AT = "expires_at"
    }

    private lateinit var notifications: KlectCallNotificationManager
    private lateinit var telecom: KlectTelecomManager
    private var callId: String? = null
    private var callerName: String = "KLECT call"
    private var video = false
    private val expiryHandler = Handler(Looper.getMainLooper())
    private var expiryTask: Runnable? = null

    override fun onCreate() {
        super.onCreate()
        notifications = KlectCallNotificationManager(this)
        telecom = KlectTelecomManager(this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent == null) return START_NOT_STICKY
        val id = intent.getStringExtra(EXTRA_CALL_ID) ?: callId ?: return START_NOT_STICKY
        val isPresentation =
            intent.action == ACTION_PRESENT_INCOMING ||
                intent.action == ACTION_PRESENT_OUTGOING
        if (!isPresentation) {
            callerName = intent.getStringExtra(EXTRA_CALLER_NAME) ?: callerName
            video = intent.getStringExtra(EXTRA_KIND)?.let { it == "video" } ?: video
            startForeground(
                KlectCallNotificationManager.NOTIFICATION_ID,
                notifications.ongoing(id, callerName, video),
            )
        }
        when (intent.action) {
            ACTION_PRESENT_INCOMING,
            ACTION_PRESENT_OUTGOING ->
                present(intent, id, incoming = intent.action == ACTION_PRESENT_INCOMING)

            ACTION_ANSWER -> {
                KlectCallActionStore.enqueue(this, "answer", id)
                startForeground(
                    KlectCallNotificationManager.NOTIFICATION_ID,
                    notifications.ongoing(id, callerName, video),
                )
                telecom.answer()
                openCall(id)
            }

            ACTION_DECLINE -> {
                KlectCallActionStore.enqueue(this, "decline", id)
                telecom.disconnect(rejected = true)
                finishCall()
            }

            ACTION_HANGUP -> {
                KlectCallActionStore.enqueue(this, "hangup", id)
                telecom.disconnect(rejected = false)
                finishCall()
            }

            ACTION_ACTIVE -> {
                startForeground(
                    KlectCallNotificationManager.NOTIFICATION_ID,
                    notifications.ongoing(id, callerName, video),
                )
                telecom.setActive()
            }

            ACTION_END -> {
                telecom.disconnect(rejected = false)
                finishCall()
            }
        }
        return START_NOT_STICKY
    }

    private fun present(intent: Intent, id: String, incoming: Boolean) {
        val expiry = intent.getStringExtra(EXTRA_EXPIRES_AT)
        if (incoming && expiry != null) {
            val expiresAt = runCatching { Instant.parse(expiry) }.getOrNull()
            if (expiresAt == null || !expiresAt.isAfter(Instant.now())) {
                KlectCallActionStore.enqueue(this, "stale", id)
                stopSelf()
                return
            }
        }
        val presentedName = intent.getStringExtra(EXTRA_CALLER_NAME) ?: callerName
        val presentedVideo = intent.getStringExtra(EXTRA_KIND) == "video"
        if (!telecom.register(id, presentedName, incoming, presentedVideo)) return

        callId = id
        callerName = presentedName
        video = presentedVideo
        val notification = if (incoming) {
            notifications.incoming(id, callerName, video)
        } else {
            notifications.ongoing(id, callerName, video)
        }
        startForeground(KlectCallNotificationManager.NOTIFICATION_ID, notification)
        if (incoming && expiry != null) scheduleExpiry(id, Instant.parse(expiry))
    }

    private fun scheduleExpiry(id: String, expiresAt: Instant) {
        expiryTask?.let(expiryHandler::removeCallbacks)
        val task = Runnable {
            if (callId != id) return@Runnable
            KlectCallActionStore.enqueue(this, "stale", id)
            telecom.disconnect(rejected = false)
            finishCall()
        }
        expiryTask = task
        val remaining = (expiresAt.toEpochMilli() - System.currentTimeMillis()).coerceAtLeast(0)
        expiryHandler.postDelayed(task, remaining)
    }

    private fun openCall(id: String) {
        startActivity(
            Intent(
                Intent.ACTION_VIEW,
                Uri.parse("klect://call/$id"),
                this,
                MainActivity::class.java,
            ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
        )
    }

    private fun finishCall() {
        expiryTask?.let(expiryHandler::removeCallbacks)
        expiryTask = null
        stopForeground(STOP_FOREGROUND_REMOVE)
        NotificationManagerCompat.from(this)
            .cancel(KlectCallNotificationManager.NOTIFICATION_ID)
        callId = null
        stopSelf()
    }

    override fun onDestroy() {
        expiryTask?.let(expiryHandler::removeCallbacks)
        expiryTask = null
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
