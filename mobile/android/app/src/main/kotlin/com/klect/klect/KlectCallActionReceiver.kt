package com.klect.klect

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.content.ContextCompat

/** Receives CallStyle actions even when the Flutter process is not warm. */
class KlectCallActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val callId = intent.getStringExtra(KlectCallService.EXTRA_CALL_ID) ?: return
        val serviceIntent = Intent(context, KlectCallService::class.java)
            .setAction(intent.action)
            .putExtras(intent)
            .putExtra(KlectCallService.EXTRA_CALL_ID, callId)
        ContextCompat.startForegroundService(context, serviceIntent)
    }
}
