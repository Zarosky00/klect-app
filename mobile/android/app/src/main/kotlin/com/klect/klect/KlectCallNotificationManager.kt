package com.klect.klect

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.net.Uri
import androidx.core.app.NotificationCompat
import androidx.core.app.Person

/** Native Android CallStyle surfaces for ringing and ongoing calls. */
class KlectCallNotificationManager(private val context: Context) {
    companion object {
        const val NOTIFICATION_ID = 1700
        const val INCOMING_CHANNEL = "klect_calls_incoming_v1"
        const val ONGOING_CHANNEL = "klect_calls_ongoing_v1"
    }

    private val manager = context.getSystemService(NotificationManager::class.java)

    init {
        createChannels()
    }

    fun incoming(callId: String, callerName: String, video: Boolean): Notification {
        val person = Person.Builder()
            .setName(callerName)
            .setUri("klect://call/$callId")
            .setImportant(true)
            .build()
        return base(INCOMING_CHANNEL, callId, callerName, video)
            .setFullScreenIntent(contentIntent(callId), true)
            .setOngoing(true)
            .setTimeoutAfter(45_000)
            .setStyle(
                NotificationCompat.CallStyle.forIncomingCall(
                    person,
                    actionIntent(KlectCallService.ACTION_DECLINE, callId, callerName, video),
                    actionIntent(KlectCallService.ACTION_ANSWER, callId, callerName, video),
                ),
            )
            .addPerson(person)
            .build()
    }

    fun ongoing(callId: String, callerName: String, video: Boolean): Notification {
        val person = Person.Builder()
            .setName(callerName)
            .setUri("klect://call/$callId")
            .setImportant(true)
            .build()
        return base(ONGOING_CHANNEL, callId, callerName, video)
            .setOngoing(true)
            .setStyle(
                NotificationCompat.CallStyle.forOngoingCall(
                    person,
                    actionIntent(KlectCallService.ACTION_HANGUP, callId, callerName, video),
                ),
            )
            .addPerson(person)
            .build()
    }

    fun cancel() = manager.cancel(NOTIFICATION_ID)

    private fun base(
        channel: String,
        callId: String,
        callerName: String,
        video: Boolean,
    ) = NotificationCompat.Builder(context, channel)
        .setSmallIcon(R.drawable.ic_launcher_monochrome)
        .setContentTitle(callerName)
        .setContentText(if (video) "KLECT video call" else "KLECT audio call")
        .setContentIntent(contentIntent(callId))
        .setCategory(NotificationCompat.CATEGORY_CALL)
        .setPriority(NotificationCompat.PRIORITY_MAX)
        .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
        .setOnlyAlertOnce(false)

    private fun contentIntent(callId: String): PendingIntent {
        val intent = Intent(
            Intent.ACTION_VIEW,
            Uri.parse("klect://call/$callId"),
            context,
            MainActivity::class.java,
        ).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        return PendingIntent.getActivity(
            context,
            callId.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun actionIntent(
        action: String,
        callId: String,
        callerName: String,
        video: Boolean,
    ): PendingIntent {
        val intent = Intent(context, KlectCallActionReceiver::class.java)
            .setAction(action)
            .putExtra(KlectCallService.EXTRA_CALL_ID, callId)
            .putExtra(KlectCallService.EXTRA_CALLER_NAME, callerName)
            .putExtra(KlectCallService.EXTRA_KIND, if (video) "video" else "audio")
        return PendingIntent.getBroadcast(
            context,
            31 * callId.hashCode() + action.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun createChannels() {
        val ringtone = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
        val audio = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        manager.createNotificationChannel(
            NotificationChannel(
                INCOMING_CHANNEL,
                "Incoming calls",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "Incoming KLECT calls"
                enableVibration(true)
                setSound(ringtone, audio)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            },
        )
        manager.createNotificationChannel(
            NotificationChannel(
                ONGOING_CHANNEL,
                "Ongoing calls",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Calls currently using microphone or camera"
                setSound(null, null)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            },
        )
    }
}
