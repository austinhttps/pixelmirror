package com.google.pixelmirror.companion.util

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.google.pixelmirror.companion.model.ClipboardSyncData
import com.google.pixelmirror.companion.network.ConnectionStatus
import com.google.pixelmirror.companion.network.SocketEventBus

/**
 * Section 3.2: Clipboard Syncing Utility.
 * Symmetrically syncs the copy-paste stack between Android and Windows
 * using ClipboardManager.setPrimaryClip() and primary clip changed listeners.
 */
object ClipboardSyncHelper {

    private const val tag = "ClipboardSyncHelper"
    private var lastSyncedText: String? = null
    private var clipboardManager: ClipboardManager? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    fun init(context: Context) {
        clipboardManager = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        clipboardManager?.addPrimaryClipChangedListener {
            val status = SocketEventBus.connectionStatus.value
            if (status != ConnectionStatus.AUTHORIZED && status != ConnectionStatus.CONNECTED) {
                return@addPrimaryClipChangedListener
            }

            val clip = clipboardManager?.primaryClip ?: return@addPrimaryClipChangedListener
            if (clip.itemCount > 0) {
                val text = clip.getItemAt(0).text?.toString() ?: return@addPrimaryClipChangedListener
                if (text != lastSyncedText && text.isNotBlank()) {
                    lastSyncedText = text
                    Log.d(tag, "Local clipboard changed. Dispatching to Windows: '$text'")
                    SocketEventBus.postOutbound(ClipboardSyncData(text).toEventPacket())
                }
            }
        }
    }

    /**
     * Updates Android system clipboard with text received from Windows desktop.
     */
    fun updateSystemClipboard(context: Context, text: String) {
        if (text.isBlank() || text == lastSyncedText) return

        mainHandler.post {
            try {
                val manager = clipboardManager
                    ?: (context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager)
                lastSyncedText = text
                val clip = ClipData.newPlainText("Pixel Mirror Sync", text)
                manager.setPrimaryClip(clip)
                Log.i(tag, "Phone clipboard updated from Windows: '$text'")
            } catch (e: Exception) {
                Log.e(tag, "Failed to set phone clipboard: ${e.message}")
            }
        }
    }
}
