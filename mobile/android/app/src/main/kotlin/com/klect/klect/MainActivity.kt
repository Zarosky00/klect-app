package com.klect.klect

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private companion object {
        const val UPDATE_CHANNEL = "com.klect.klect/updater"
        const val CALL_CHANNEL = "com.klect.klect/calls"
        const val APK_MIME_TYPE = "application/vnd.android.package-archive"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            UPDATE_CHANNEL,
        ).setMethodCallHandler { call, result ->
            if (call.method != "installApk") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            val path = call.argument<String>("path")
            if (path.isNullOrBlank()) {
                result.error("INVALID_PATH", "The APK path is missing.", null)
                return@setMethodCallHandler
            }

            val apk = File(path)
            val updateDirectory = File(cacheDir, "updates")
            val isInsideUpdateDirectory =
                runCatching {
                    apk.canonicalFile.parentFile == updateDirectory.canonicalFile
                }.getOrDefault(false)
            if (!apk.isFile || !isInsideUpdateDirectory || apk.extension != "apk") {
                result.error("INVALID_APK", "The verified APK is unavailable.", null)
                return@setMethodCallHandler
            }

            try {
                if (
                    Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                    !packageManager.canRequestPackageInstalls()
                ) {
                    startActivity(
                        Intent(
                            Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                            Uri.parse("package:$packageName"),
                        ),
                    )
                    result.success("permissionRequired")
                    return@setMethodCallHandler
                }

                val apkUri = FileProvider.getUriForFile(
                    this,
                    "$packageName.update_file_provider",
                    apk,
                )
                val installIntent =
                    Intent(Intent.ACTION_VIEW)
                        .setDataAndType(apkUri, APK_MIME_TYPE)
                        .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                startActivity(installIntent)
                result.success("installerOpened")
            } catch (error: ActivityNotFoundException) {
                result.error(
                    "INSTALLER_UNAVAILABLE",
                    "No Android package installer is available.",
                    null,
                )
            } catch (error: Exception) {
                result.error("INSTALL_FAILED", error.message, null)
            }
        }

        val callChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CALL_CHANNEL,
        )
        KlectCallActionStore.listener = { action ->
            runOnUiThread { callChannel.invokeMethod("callAction", action) }
        }
        callChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "drainActions" -> result.success(KlectCallActionStore.drain(this))
                "ackAction" -> {
                    KlectCallActionStore.ack(
                        this,
                        call.argument<String>("eventId") ?: "",
                    )
                    result.success(null)
                }
                "presentCall" -> {
                    val callId = call.argument<String>("callId")
                    if (callId.isNullOrBlank()) {
                        result.error("INVALID_CALL", "The call id is missing.", null)
                        return@setMethodCallHandler
                    }
                    val incoming = call.argument<Boolean>("incoming") ?: false
                    val intent = Intent(this, KlectCallService::class.java)
                        .setAction(
                            if (incoming) KlectCallService.ACTION_PRESENT_INCOMING
                            else KlectCallService.ACTION_PRESENT_OUTGOING,
                        )
                        .putExtra(KlectCallService.EXTRA_CALL_ID, callId)
                        .putExtra(
                            KlectCallService.EXTRA_CONVERSATION_ID,
                            call.argument<String>("conversationId"),
                        )
                        .putExtra(
                            KlectCallService.EXTRA_CALLER_NAME,
                            call.argument<String>("peerName") ?: "KLECT call",
                        )
                        .putExtra(
                            KlectCallService.EXTRA_KIND,
                            call.argument<String>("kind") ?: "audio",
                        )
                        .putExtra(
                            KlectCallService.EXTRA_EXPIRES_AT,
                            call.argument<String>("expiresAt"),
                        )
                    ContextCompat.startForegroundService(this, intent)
                    result.success(null)
                }
                "setCallState" -> {
                    val callId = call.argument<String>("callId")
                    val state = call.argument<String>("state")
                    if (callId.isNullOrBlank() || state.isNullOrBlank()) {
                        result.error("INVALID_STATE", "Call state is incomplete.", null)
                        return@setMethodCallHandler
                    }
                    val action = if (state == "active" || state == "connecting") {
                        KlectCallService.ACTION_ACTIVE
                    } else {
                        KlectCallService.ACTION_END
                    }
                    startService(
                        Intent(this, KlectCallService::class.java)
                            .setAction(action)
                            .putExtra(KlectCallService.EXTRA_CALL_ID, callId),
                    )
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        KlectCallActionStore.listener = null
        super.onDestroy()
    }
}
