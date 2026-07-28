package com.klect.klect

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private companion object {
        const val UPDATE_CHANNEL = "com.klect.klect/updater"
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
    }
}
