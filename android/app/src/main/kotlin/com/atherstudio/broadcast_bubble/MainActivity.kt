package com.atherstudio.broadcast_bubble

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.atherstudio.broadcast_bubble/native"
    private val preferences by lazy { getSharedPreferences(BubbleOverlayService.PREFERENCES_NAME, MODE_PRIVATE) }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "loadState" -> result.success(
                    mapOf(
                        "ideasJson" to preferences.getString(BubbleOverlayService.KEY_IDEAS, "[]"),
                        "selectedId" to preferences.getString(BubbleOverlayService.KEY_SELECTED_ID, null),
                        "fontSize" to preferences.getInt(BubbleOverlayService.KEY_FONT_SIZE, 30),
                        "bubbleActive" to BubbleOverlayService.isRunning,
                    ),
                )

                "saveState" -> {
                    val state = call.arguments as? Map<*, *>
                    if (state == null) {
                        result.error("invalid_state", "تعذّر حفظ الأفكار.", null)
                    } else {
                        preferences.edit()
                            .putString(BubbleOverlayService.KEY_IDEAS, state["ideasJson"] as? String ?: "[]")
                            .putString(BubbleOverlayService.KEY_SELECTED_ID, state["selectedId"] as? String)
                            .putInt(BubbleOverlayService.KEY_FONT_SIZE, (state["fontSize"] as? Number)?.toInt() ?: 30)
                            .apply()
                        if (BubbleOverlayService.isRunning) {
                            startBubbleService(BubbleOverlayService.ACTION_REFRESH)
                        }
                        result.success(null)
                    }
                }

                "canDrawOverlays" -> result.success(
                    Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.canDrawOverlays(this),
                )

                "requestOverlayPermission" -> {
                    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.canDrawOverlays(this)) {
                        result.success(null)
                    } else {
                        val intent = Intent(
                            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                            Uri.parse("package:$packageName"),
                        )
                        startActivity(intent)
                        result.success(null)
                    }
                }

                "startBubble" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {
                        result.error("overlay_permission", "يجب السماح بالظهور فوق التطبيقات أولًا.", null)
                    } else {
                        preferences.edit().putBoolean(BubbleOverlayService.KEY_BUBBLE_ACTIVE, true).apply()
                        startBubbleService(BubbleOverlayService.ACTION_START)
                        result.success(null)
                    }
                }

                "stopBubble" -> {
                    stopService(Intent(this, BubbleOverlayService::class.java))
                    preferences.edit().putBoolean(BubbleOverlayService.KEY_BUBBLE_ACTIVE, false).apply()
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun startBubbleService(action: String) {
        val intent = Intent(this, BubbleOverlayService::class.java).setAction(action)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }
}
