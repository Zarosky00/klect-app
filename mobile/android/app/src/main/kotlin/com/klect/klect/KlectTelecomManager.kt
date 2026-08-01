package com.klect.klect

import android.content.Context
import android.net.Uri
import android.telecom.DisconnectCause
import androidx.core.telecom.CallAttributesCompat
import androidx.core.telecom.CallControlScope
import androidx.core.telecom.CallsManager
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.launch

/** One Core-Telecom session. Supabase remains authoritative for media state. */
class KlectTelecomManager(private val context: Context) {
    private sealed interface Command {
        data object Answer : Command
        data object Active : Command
        data class Disconnect(val cause: Int) : Command
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val callsManager = CallsManager(context)
    private val commands = Channel<Command>(Channel.UNLIMITED)
    @Volatile private var currentCallId: String? = null

    init {
        callsManager.registerAppWithTelecom(
            CallsManager.CAPABILITY_BASELINE or
                CallsManager.CAPABILITY_SUPPORTS_VIDEO_CALLING,
        )
    }

    fun register(
        callId: String,
        callerName: String,
        incoming: Boolean,
        video: Boolean,
    ): Boolean {
        if (currentCallId == callId) return true
        if (currentCallId != null) {
            KlectCallActionStore.enqueue(context, "busy", callId)
            return false
        }
        currentCallId = callId
        val attributes = CallAttributesCompat(
            displayName = callerName,
            address = Uri.parse("klect://call/$callId"),
            direction = if (incoming) {
                CallAttributesCompat.DIRECTION_INCOMING
            } else {
                CallAttributesCompat.DIRECTION_OUTGOING
            },
            callType = if (video) {
                CallAttributesCompat.CALL_TYPE_VIDEO_CALL
            } else {
                CallAttributesCompat.CALL_TYPE_AUDIO_CALL
            },
            callCapabilities = 0,
        )
        scope.launch {
            try {
                callsManager.addCall(
                    attributes,
                    onAnswer = {
                        KlectCallActionStore.enqueue(context, "answer", callId)
                    },
                    onDisconnect = {
                        KlectCallActionStore.enqueue(context, "hangup", callId)
                    },
                    onSetActive = { Unit },
                    onSetInactive = { Unit },
                ) {
                    processCommands(this, callId, video)
                }
            } finally {
                currentCallId = null
            }
        }
        return true
    }

    private fun CoroutineScope.processCommands(
        control: CallControlScope,
        callId: String,
        video: Boolean,
    ) {
        launch {
            for (command in commands) {
                if (currentCallId != callId) continue
                when (command) {
                    Command.Answer -> control.answer(
                        if (video) CallAttributesCompat.CALL_TYPE_VIDEO_CALL
                        else CallAttributesCompat.CALL_TYPE_AUDIO_CALL,
                    )
                    Command.Active -> control.setActive()
                    is Command.Disconnect -> control.disconnect(
                        DisconnectCause(command.cause),
                    )
                }
            }
        }
    }

    fun answer() {
        commands.trySend(Command.Answer)
    }

    fun setActive() {
        commands.trySend(Command.Active)
    }

    fun disconnect(rejected: Boolean) {
        commands.trySend(
            Command.Disconnect(
                if (rejected) DisconnectCause.REJECTED else DisconnectCause.LOCAL,
            ),
        )
    }

}
