package com.google.pixelmirror.companion.util

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.util.Base64
import android.util.Log
import androidx.core.content.FileProvider
import java.io.File
import java.io.FileOutputStream

/**
 * Section 3.4: Quick Share Bridge.
 * Accepts files routed from Windows and launches the native system share sheet
 * (Intent.ACTION_SEND with FileProvider URI) so Quick Share / Nearby Share
 * opens directly inside the mirrored screen.
 */
object QuickShareHelper {

    private const val tag = "QuickShareHelper"
    private const val FILE_PROVIDER_AUTHORITY = "com.google.pixelmirror.companion.fileprovider"
    private val mainHandler = Handler(Looper.getMainLooper())

    fun shareFile(
        context: Context,
        filename: String,
        mimeType: String,
        fileBase64: String
    ) {
        try {
            val fileBytes = Base64.decode(fileBase64, Base64.DEFAULT)
            val downloadDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
            if (!downloadDir.exists()) {
                downloadDir.mkdirs()
            }

            val targetFile = File(downloadDir, filename)
            FileOutputStream(targetFile).use { fos ->
                fos.write(fileBytes)
                fos.flush()
            }

            val fileUri: Uri = FileProvider.getUriForFile(
                context,
                FILE_PROVIDER_AUTHORITY,
                targetFile
            )

            mainHandler.post {
                val shareIntent = Intent(Intent.ACTION_SEND).apply {
                    type = mimeType.ifBlank { "*/*" }
                    putExtra(Intent.EXTRA_STREAM, fileUri)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }

                val chooser = Intent.createChooser(shareIntent, "Share with Quick Share").apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }

                context.startActivity(chooser)
                Log.i(tag, "Launched native Quick Share sheet for: $filename")
            }

        } catch (e: Exception) {
            Log.e(tag, "Failed to launch Quick Share chooser: ${e.message}", e)
        }
    }
}
