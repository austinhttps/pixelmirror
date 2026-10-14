package com.google.pixelmirror.companion.service

import android.app.Notification
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.graphics.drawable.Icon
import android.os.Build
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Base64
import android.util.Log
import com.google.pixelmirror.companion.model.NotificationEnqueueData
import com.google.pixelmirror.companion.network.ConnectionStatus
import com.google.pixelmirror.companion.network.SocketEventBus
import com.google.pixelmirror.companion.util.NotificationReplyHelper
import java.io.ByteArrayOutputStream

/**
 * Section 3.1: Interactive NotificationListenerService.
 * Intercepts incoming system alerts, serializes their arrays into NOTIFICATION_ENQUEUE
 * payloads conforming to API_CONTRACT.md, and stores action handlers for remote replies.
 */
class MirrorNotificationListenerService : NotificationListenerService() {

    private val tag = "MirrorNotificationSvc"

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        super.onNotificationPosted(sbn)
        if (sbn == null) return

        val pkgName = sbn.packageName ?: return
        // Ignore self notifications
        if (pkgName == packageName) return

        val status = SocketEventBus.connectionStatus.value
        if (status != ConnectionStatus.AUTHORIZED && status != ConnectionStatus.CONNECTED) {
            return
        }

        try {
            val notification = sbn.notification ?: return
            val extras = notification.extras ?: return

            // Extract Notification Title & Body
            val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()
                ?: extras.getCharSequence(Notification.EXTRA_CONVERSATION_TITLE)?.toString()
                ?: ""
            val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()
                ?: extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()
                ?: ""

            if (title.isBlank() && text.isBlank()) return

            // Resolve App Label
            val pm = packageManager
            val appLabel = try {
                val appInfo = pm.getApplicationInfo(pkgName, 0)
                pm.getApplicationLabel(appInfo).toString()
            } catch (_: PackageManager.NameNotFoundException) {
                pkgName
            }

            // Extract & Convert Icon to Base64 PNG
            val iconBase64 = extractIconBase64(notification, pkgName)

            // Cache for NOTIFICATION_REPLY quick-reply routing
            NotificationReplyHelper.registerNotification(sbn)

            val enqueueData = NotificationEnqueueData(
                notificationId = sbn.id,
                packageName = pkgName,
                appLabel = appLabel,
                title = title,
                body = text,
                iconBase64 = iconBase64
            )

            Log.i(tag, "Dispatching NOTIFICATION_ENQUEUE: [${sbn.id}] $appLabel: $title")
            SocketEventBus.postOutbound(enqueueData.toEventPacket())

        } catch (e: Exception) {
            Log.e(tag, "Error processing incoming notification: ${e.message}", e)
        }
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        super.onNotificationRemoved(sbn)
        if (sbn != null) {
            NotificationReplyHelper.unregisterNotification(sbn.id, sbn.packageName)
        }
    }

    /**
     * Extracts large icon or small app icon and encodes it to a compact Base64 PNG string.
     */
    private fun extractIconBase64(notification: Notification, packageName: String): String {
        return try {
            val bitmap: Bitmap? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                notification.getLargeIcon()?.loadDrawable(this)?.let { drawableToBitmap(it) }
                    ?: notification.smallIcon?.loadDrawable(this)?.let { drawableToBitmap(it) }
            } else {
                @Suppress("DEPRECATION")
                notification.largeIcon ?: drawableToBitmap(packageManager.getApplicationIcon(packageName))
            }

            val finalBitmap = bitmap ?: drawableToBitmap(packageManager.getApplicationIcon(packageName))
            val stream = ByteArrayOutputStream()
            // Scale icon to max 64x64 for efficient network transmission
            val scaled = Bitmap.createScaledBitmap(finalBitmap, 64, 64, true)
            scaled.compress(Bitmap.CompressFormat.PNG, 90, stream)
            Base64.encodeToString(stream.toByteArray(), Base64.NO_WRAP)
        } catch (e: Exception) {
            Log.w(tag, "Failed to encode notification icon: ${e.message}")
            ""
        }
    }

    private fun drawableToBitmap(drawable: Drawable): Bitmap {
        if (drawable is BitmapDrawable && drawable.bitmap != null) {
            return drawable.bitmap
        }
        val width = if (drawable.intrinsicWidth > 0) drawable.intrinsicWidth else 64
        val height = if (drawable.intrinsicHeight > 0) drawable.intrinsicHeight else 64
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        drawable.setBounds(0, 0, canvas.width, canvas.height)
        drawable.draw(canvas)
        return bitmap
    }
}
