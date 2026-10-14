package com.google.pixelmirror.companion.util

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.net.Uri
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.util.Base64
import android.util.Log
import androidx.core.content.FileProvider
import com.google.pixelmirror.companion.model.FileDropData
import com.google.pixelmirror.companion.service.MirrorAccessibilityService
import java.io.File
import java.io.FileOutputStream

/**
 * Section 3.3: Smart File Drops (Canvas Pasting).
 * Handles incoming file byte data, writes directly to /sdcard/Download/,
 * registers as a FileProvider URI, copies to the system clipboard, and
 * commands MirrorAccessibilityService to tap target coordinates and trigger PASTE.
 */
object FileDropHelper {

    private const val tag = "FileDropHelper"
    private const val FILE_PROVIDER_AUTHORITY = "com.google.pixelmirror.companion.fileprovider"
    private val mainHandler = Handler(Looper.getMainLooper())

    fun handleIncomingFile(context: Context, fileDrop: FileDropData) {
        try {
            val fileBytes = Base64.decode(fileDrop.fileBase64, Base64.DEFAULT)
            val downloadDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
            if (!downloadDir.exists()) {
                downloadDir.mkdirs()
            }

            val targetFile = File(downloadDir, fileDrop.filename)
            FileOutputStream(targetFile).use { fos ->
                fos.write(fileBytes)
                fos.flush()
            }
            Log.i(tag, "Saved dropped file to: ${targetFile.absolutePath} (${fileBytes.size} bytes)")

            // Generate secure FileProvider URI
            val fileUri: Uri = FileProvider.getUriForFile(
                context,
                FILE_PROVIDER_AUTHORITY,
                targetFile
            )

            // Copy FileProvider URI to system clipboard
            mainHandler.post {
                val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                val clipData = ClipData.newUri(context.contentResolver, fileDrop.filename, fileUri)
                clipboard.setPrimaryClip(clipData)
                Log.d(tag, "Registered FileProvider URI on clipboard: $fileUri")

                // Execute coordinate macro if target coordinates are specified
                if (fileDrop.isCanvasPaste && fileDrop.targetX >= 0 && fileDrop.targetY >= 0) {
                    val a11y = MirrorAccessibilityService.instance
                    if (a11y != null) {
                        Log.i(tag, "Invoking A11y macro: tap at (${fileDrop.targetX}, ${fileDrop.targetY}) and PASTE")
                        a11y.performFocusAndPaste(fileDrop.targetX.toFloat(), fileDrop.targetY.toFloat())
                    } else {
                        Log.w(tag, "AccessibilityService not enabled. Cannot execute tap-and-paste macro.")
                    }
                }
            }

        } catch (e: Exception) {
            Log.e(tag, "Failed to handle incoming file drop: ${e.message}", e)
        }
    }
}
