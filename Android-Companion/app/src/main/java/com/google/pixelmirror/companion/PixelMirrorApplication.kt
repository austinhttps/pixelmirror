package com.google.pixelmirror.companion

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import com.google.android.material.color.DynamicColors

/**
 * Pixel Mirror Companion Application entrypoint.
 * Applies Material Design 3 Dynamic Colors from the Pixel 10 active wallpaper palette
 * and initializes high-priority notification channels for foreground services.
 */
class PixelMirrorApplication : Application() {

    override fun onCreate() {
        super.onCreate()

        // Section 5: Integrate DynamicColors so app inherits Pixel 10 wallpaper palette
        DynamicColors.applyToActivitiesIfAvailable(this)

        createNotificationChannels()
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val serviceChannel = NotificationChannel(
                CHANNEL_SERVICE_ID,
                getString(R.string.notification_channel_name),
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = getString(R.string.notification_channel_desc)
                setShowBadge(false)
            }

            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(serviceChannel)
        }
    }

    companion object {
        const val CHANNEL_SERVICE_ID = "pixel_mirror_stream"
        const val SERVICE_NOTIFICATION_ID = 1001
    }
}
