package com.example.ymtimetable

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

object WebsiteUpdater {
    fun register(activity: FlutterActivity, engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, "para/website_update")
            .setMethodCallHandler { call, result ->
                try {
                    val directory = File(activity.cacheDir, "app_updates")
                    val apk = File(directory, "update.apk")
                    when (call.method) {
                        "prepare" -> {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                                !activity.packageManager.canRequestPackageInstalls()) {
                                activity.startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                    Uri.parse("package:" + activity.packageName)))
                                result.error("permission_not_granted", "Allow installs and retry", null)
                            } else {
                                directory.mkdirs()
                                result.success(apk.absolutePath)
                            }
                        }
                        "install" -> {
                            check(apk.isFile) { "APK not found" }
                            val uri = FileProvider.getUriForFile(activity,
                                activity.packageName + ".update_provider", apk)
                            activity.startActivity(Intent(Intent.ACTION_VIEW).apply {
                                setDataAndType(uri, "application/vnd.android.package-archive")
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            })
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (error: Exception) {
                    result.error("install_failed", error.message, null)
                }
            }
    }
}
