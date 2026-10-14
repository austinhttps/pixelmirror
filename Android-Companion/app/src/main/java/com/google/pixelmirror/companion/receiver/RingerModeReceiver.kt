package com.google.pixelmirror.companion.receiver

import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.os.Build
import android.util.Log
import com.google.pixelmirror.companion.model.SystemModeSyncData
import com.google.pixelmirror.companion.network.ConnectionStatus
import com.google.pixelmirror.companion.network.SocketEventBus

/**
 * Section 3.5: Mode Sync Receiver.
 * Tracks AudioManager.RINGER_MODE_CHANGED_ACTION and DND interruption filter changes,
 * broadcasting SYSTEM_MODE_SYNC payloads to Windows over the TCP socket.
 */
class RingerModeReceiver : BroadcastReceiver() {

    private val tag = "RingerModeReceiver"

    override fun onReceive(context: Context?, intent: Intent?) {
        if (context == null || intent == null) return

        val status = SocketEventBus.connectionStatus.value
        if (status != ConnectionStatus.AUTHORIZED && status != ConnectionStatus.CONNECTED) {
            return
        }

        when (intent.action) {
            AudioManager.RINGER_MODE_CHANGED_ACTION -> {
                val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
                val isSilentOrVibrate = audioManager.ringerMode != AudioManager.RINGER_MODE_NORMAL
                Log.d(tag, "Ringer mode changed. Silent/Vibrate=$isSilentOrVibrate")

                val syncPacket = SystemModeSyncData(
                    modeType = "RINGER_MODE",
                    isEnabled = isSilentOrVibrate
                ).toEventPacket()
                SocketEventBus.postOutbound(syncPacket)
            }
            NotificationManager.ACTION_INTERRUPTION_FILTER_CHANGED -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                    val isDndActive = nm.currentInterruptionFilter != NotificationManager.INTERRUPTION_FILTER_ALL
                    Log.d(tag, "DND filter changed. DndActive=$isDndActive")

                    val syncPacket = SystemModeSyncData(
                        modeType = "DO_NOT_DISTURB",
                        isEnabled = isDndActive
                    ).toEventPacket()
                    SocketEventBus.postOutbound(syncPacket)
                }
            }
        }
    }
}
