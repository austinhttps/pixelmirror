package com.google.pixelmirror.companion.util

import android.app.NotificationManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.os.Build
import android.provider.Settings
import android.util.Log
import com.google.pixelmirror.companion.model.HotspotRequestData
import com.google.pixelmirror.companion.model.SystemModeSyncData

/**
 * Section 3.5: Mode Sync & System Settings Routing.
 * Handles incoming hotspot requests routing straight to com.android.settings.TetherSettings
 * and sets phone mode states (DND / Ringer).
 */
object SystemActionHelper {

    private const val tag = "SystemActionHelper"

    /**
     * Section 3.5: Launches explicit intent routing straight to com.android.settings.TetherSettings.
     */
    fun handleHotspotRequest(context: Context, request: HotspotRequestData) {
        Log.i(tag, "Received HOTSPOT_REQUEST: ${request.action}")

        try {
            // Explicit intent straight to com.android.settings.TetherSettings
            val explicitIntent = Intent().apply {
                component = ComponentName("com.android.settings", "com.android.settings.TetherSettings")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(explicitIntent)
            Log.i(tag, "Dispatched explicit intent to com.android.settings.TetherSettings")
        } catch (e: Exception) {
            Log.w(tag, "Explicit TetherSettings component failed (${e.message}), attempting action fallback...")
            try {
                // Secondary fallback to ACTION_WIRELESS_SETTINGS / TETHER_SETTINGS
                val fallbackIntent = Intent("android.settings.TETHER_SETTINGS").apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                context.startActivity(fallbackIntent)
            } catch (fallbackError: Exception) {
                val generalIntent = Intent(Settings.ACTION_WIRELESS_SETTINGS).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                context.startActivity(generalIntent)
            }
        }
    }

    /**
     * Symmetrically updates phone mode (Do Not Disturb / Silent / Normal).
     */
    fun handleModeSync(context: Context, mode: SystemModeSyncData) {
        Log.i(tag, "Received SYSTEM_MODE_SYNC: ${mode.modeType} enabled=${mode.isEnabled}")

        when (mode.modeType) {
            "DO_NOT_DISTURB" -> {
                val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && notificationManager.isNotificationPolicyAccessGranted) {
                    val filter = if (mode.isEnabled) {
                        NotificationManager.INTERRUPTION_FILTER_PRIORITY
                    } else {
                        NotificationManager.INTERRUPTION_FILTER_ALL
                    }
                    notificationManager.setInterruptionFilter(filter)
                    Log.d(tag, "Applied DND filter: $filter")
                } else {
                    Log.w(tag, "Notification policy access not granted. Cannot modify DND filter.")
                }
            }
            "RINGER_MODE" -> {
                val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
                val targetMode = if (mode.isEnabled) AudioManager.RINGER_MODE_SILENT else AudioManager.RINGER_MODE_NORMAL
                try {
                    audioManager.ringerMode = targetMode
                    Log.d(tag, "Applied ringer mode: $targetMode")
                } catch (e: Exception) {
                    Log.w(tag, "Failed to apply ringer mode: ${e.message}")
                }
            }
        }
    }
}
