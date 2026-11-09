package com.example.secondsight

import android.accessibilityservice.AccessibilityServiceInfo
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.provider.Settings
import android.view.accessibility.AccessibilityManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** Read-only detection. Enabling TalkBack remains the user's choice in Settings. */
class AccessibilityBridge(private val activity: Activity, messenger: BinaryMessenger) {
    private val manager = activity.getSystemService(Context.ACCESSIBILITY_SERVICE) as AccessibilityManager
    private val channel = MethodChannel(messenger, "secondsight/accessibility")
    private val touchListener = AccessibilityManager.TouchExplorationStateChangeListener { publish() }
    private val stateListener = AccessibilityManager.AccessibilityStateChangeListener { publish() }

    init {
        manager.addTouchExplorationStateChangeListener(touchListener)
        manager.addAccessibilityStateChangeListener(stateListener)
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getState" -> result.success(snapshot())
                "openSettings" -> {
                    try {
                        activity.startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                        result.success(true)
                    } catch (_: Exception) {
                        result.error("accessibility_settings", "Không mở được cài đặt trợ năng.", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun snapshot(): Map<String, Boolean> {
        val talkBack = manager.getEnabledAccessibilityServiceList(AccessibilityServiceInfo.FEEDBACK_SPOKEN)
            .any { info ->
                val service = info.resolveInfo.serviceInfo
                service.packageName == "com.google.android.marvin.talkback" ||
                    service.packageName == "com.samsung.android.accessibility.talkback"
            }
        return mapOf(
            "talkBackEnabled" to talkBack,
            // Also covers screen readers from other vendors; don't talk over them.
            "touchExplorationEnabled" to manager.isTouchExplorationEnabled
        )
    }

    fun publish() {
        activity.runOnUiThread { channel.invokeMethod("stateChanged", snapshot()) }
    }

    fun dispose() {
        manager.removeTouchExplorationStateChangeListener(touchListener)
        manager.removeAccessibilityStateChangeListener(stateListener)
        channel.setMethodCallHandler(null)
    }
}
