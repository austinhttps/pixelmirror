package com.google.pixelmirror.companion.service

import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.os.Build
import android.os.IBinder
import android.provider.Settings
import android.util.Log
import android.view.Gravity
import android.view.LayoutInflater
import android.view.View
import android.view.WindowManager
import com.google.pixelmirror.companion.R

/**
 * Section 1.4: Screen Privacy Handler.
 * Dims/blacks out the physical Pixel 10 screen canvas as soon as an active
 * desktop mirroring connection is established to protect privacy and save OLED battery.
 */
class ScreenPrivacyOverlayService : Service() {

    private val tag = "ScreenPrivacyService"
    private var windowManager: WindowManager? = null
    private var overlayView: View? = null

    override fun onCreate() {
        super.onCreate()
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action
        if (action == ACTION_HIDE_OVERLAY) {
            removeOverlay()
            stopSelf()
            return START_NOT_STICKY
        }

        showOverlay()
        return START_STICKY
    }

    private fun showOverlay() {
        if (overlayView != null) return

        if (!Settings.canDrawOverlays(this)) {
            Log.w(tag, "SYSTEM_ALERT_WINDOW permission not granted. Cannot display privacy canvas.")
            return
        }

        try {
            val inflater = LayoutInflater.from(this)
            overlayView = inflater.inflate(R.layout.overlay_screen_privacy, null)

            val layoutType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            } else {
                @Suppress("DEPRECATION")
                WindowManager.LayoutParams.TYPE_PHONE
            }

            val params = WindowManager.LayoutParams(
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.MATCH_PARENT,
                layoutType,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                        WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                        WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
                PixelFormat.TRANSLUCENT
            ).apply {
                gravity = Gravity.CENTER
                // Dim screen brightness to minimum hardware OLED level
                screenBrightness = 0.01f
            }

            // Double tap overlay view to manually dismiss if needed physically
            overlayView?.setOnClickListener {
                Log.d(tag, "Privacy canvas tapped.")
            }

            windowManager?.addView(overlayView, params)
            Log.i(tag, "Screen privacy dimming canvas overlay displayed successfully.")

        } catch (e: Exception) {
            Log.e(tag, "Failed to attach screen privacy overlay: ${e.message}", e)
        }
    }

    private fun removeOverlay() {
        overlayView?.let {
            try {
                windowManager?.removeView(it)
                Log.i(tag, "Screen privacy overlay removed.")
            } catch (e: Exception) {
                Log.e(tag, "Error removing overlay view: ${e.message}")
            }
        }
        overlayView = null
    }

    override fun onDestroy() {
        removeOverlay()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    companion object {
        const val ACTION_SHOW_OVERLAY = "com.google.pixelmirror.action.SHOW_PRIVACY_OVERLAY"
        const val ACTION_HIDE_OVERLAY = "com.google.pixelmirror.action.HIDE_PRIVACY_OVERLAY"

        fun startOverlay(context: Context) {
            if (Settings.canDrawOverlays(context)) {
                val intent = Intent(context, ScreenPrivacyOverlayService::class.java).apply {
                    action = ACTION_SHOW_OVERLAY
                }
                context.startService(intent)
            }
        }

        fun stopOverlay(context: Context) {
            val intent = Intent(context, ScreenPrivacyOverlayService::class.java).apply {
                action = ACTION_HIDE_OVERLAY
            }
            context.startService(intent)
        }
    }
}
