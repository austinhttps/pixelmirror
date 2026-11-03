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
 * Bidirectional Clipboard Synchronization Utility.
 * Symmetrically syncs the copy-paste stack between Android and Windows
 * using ClipboardManager.setPrimaryClip() and primary clip changed listeners,
 * preventing echo feedback loops.
 */
object ClipboardSyncHelper {

    private const val tag = "ClipboardSyncHelper"
    private var lastSyncedText: String? = null
    private var lastReceivedFromPcText: String? = null
    private var lastReceivedFromPcTimestamp: Long = 0L
    private var clipboardManager: ClipboardManager? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    @Synchronized
    fun init(context: Context) {
        if (clipboardManager != null) return
        clipboardManager = context.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager
        clipboardManager?.addPrimaryClipChangedListener {
            val status = SocketEventBus.connectionStatus.value
            if (status != ConnectionStatus.AUTHORIZED && status != ConnectionStatus.CONNECTED) {
                return@addPrimaryClipChangedListener
            }

            val clip = clipboardManager?.primaryClip ?: return@addPrimaryClipChangedListener
            if (clip.itemCount > 0) {
                val item = clip.getItemAt(0)
                val text = item.coerceToText(context)?.toString() ?: return@addPrimaryClipChangedListener
                if (text.isBlank()) return@addPrimaryClipChangedListener

                synchronized(this) {
                    val isRecentPcClip = text == lastReceivedFromPcText &&
                            (System.currentTimeMillis() - lastReceivedFromPcTimestamp) < 3000L

                    if (text != lastSyncedText && !isRecentPcClip) {
                        lastSyncedText = text
                        Log.d(tag, "Local Android clipboard changed. Dispatching CLIPBOARD_SYNC: '$text'")
                        SocketEventBus.postOutbound(ClipboardSyncData(text).toEventPacket())
                    }
                }
            }
        }
    }

    /**
     * Updates Android system clipboard with text received from Windows desktop.
     */
    fun updateSystemClipboard(context: Context, text: String) {
        if (text.isBlank()) return

        synchronized(this) {
            if (text == lastSyncedText) return
            lastSyncedText = text
            lastReceivedFromPcText = text
            lastReceivedFromPcTimestamp = System.currentTimeMillis()
        }

        mainHandler.post {
            try {
                val manager = clipboardManager
                    ?: (context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager)
                val clip = ClipData.newPlainText("Pixel Mirror Sync", text)
                manager.setPrimaryClip(clip)
                Log.i(tag, "Phone clipboard updated from Windows: '$text'")
            } catch (e: Exception) {
                Log.e(tag, "Failed to set phone clipboard: ${e.message}")
            }
        }
    }
}
