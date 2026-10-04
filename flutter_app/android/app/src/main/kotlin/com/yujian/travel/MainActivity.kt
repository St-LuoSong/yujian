package com.yujian.travel

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import java.security.MessageDigest

class MainActivity : FlutterActivity() {
    private val channelName = "com.yujian.travel/app_release"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "installedInfo" -> result.success(installedInfo())
                    "openDownload" -> {
                        val url = call.argument<String>("url")
                        result.success(url != null && openDownload(url))
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun installedInfo(): Map<String, Any> {
        val info = packageManager.getPackageInfo(packageName, PackageManager.GET_SIGNING_CERTIFICATES)
        val code = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.longVersionCode
        } else {
            @Suppress("DEPRECATION") info.versionCode.toLong()
        }
        return mapOf(
            "packageName" to packageName,
            "versionName" to (info.versionName ?: ""),
            "versionCode" to code,
            "certificateSha256" to signingCertificate(info.signingInfo?.apkContentsSigners?.firstOrNull()?.toByteArray()),
            "debuggable" to ((applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0),
        )
    }

    private fun signingCertificate(bytes: ByteArray?): String {
        if (bytes == null) return ""
        return MessageDigest.getInstance("SHA-256")
            .digest(bytes)
            .joinToString("") { "%02x".format(it.toInt() and 0xff) }
    }

    private fun openDownload(url: String): Boolean {
        val uri = runCatching { Uri.parse(url) }.getOrNull() ?: return false
        val debuggable = (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
        if (uri.scheme != "https" && !(debuggable && uri.scheme == "http")) return false
        return try {
            startActivity(Intent(Intent.ACTION_VIEW, uri).apply {
                addCategory(Intent.CATEGORY_BROWSABLE)
            })
            true
        } catch (_: ActivityNotFoundException) {
            false
        }
    }
}
