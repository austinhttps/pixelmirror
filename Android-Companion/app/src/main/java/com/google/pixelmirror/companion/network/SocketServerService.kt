package com.google.pixelmirror.companion.network

import android.app.Notification
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.lifecycle.LifecycleService
import androidx.lifecycle.lifecycleScope
import com.google.pixelmirror.companion.PixelMirrorApplication
import com.google.pixelmirror.companion.R
import com.google.pixelmirror.companion.model.ClipboardSyncData
import com.google.pixelmirror.companion.model.FileDropData
import com.google.pixelmirror.companion.model.HotspotRequestData
import com.google.pixelmirror.companion.model.NotificationReplyData
import com.google.pixelmirror.companion.model.SystemModeSyncData
import com.google.pixelmirror.companion.service.ScreenPrivacyOverlayService
import com.google.pixelmirror.companion.ui.MainActivity
import com.google.pixelmirror.companion.util.ClipboardSyncHelper
import com.google.pixelmirror.companion.util.FileDropHelper
import com.google.pixelmirror.companion.util.NotificationReplyHelper
import com.google.pixelmirror.companion.util.SystemActionHelper
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.net.ServerSocket
import java.net.Socket

/**
 * High-performance background Foreground Service hosting the local TCP socket server
 * on port 8080 for desktop mirroring and inter-system synchronization.
 */
class SocketServerService : LifecycleService() {

    private val tag = "SocketServerService"
    private var serverSocket: ServerSocket? = null
    private var serverJob: Job? = null
    private var activeSession: ClientSession? = null

    override fun onCreate() {
        super.onCreate()
        Log.i(tag, "SocketServerService created.")
        observeInboundEvents()
        observeConnectionStatus()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        super.onStartCommand(intent, flags, startId)

        val action = intent?.action
        if (action == ACTION_STOP_SERVER) {
            stopServer()
            stopSelf()
            return START_NOT_STICKY
        }

        startForeground(
            PixelMirrorApplication.SERVICE_NOTIFICATION_ID,
            buildNotification(getString(R.string.notification_listening, DEFAULT_PORT))
        )

        startServer()
        return START_STICKY
    }

    private fun startServer() {
        if (serverJob != null && serverJob?.isActive == true) return

        serverJob = lifecycleScope.launch(Dispatchers.IO) {
            try {
                serverSocket = ServerSocket(DEFAULT_PORT).apply {
                    reuseAddress = true
                }
                Log.i(tag, "Local TCP server listening on port $DEFAULT_PORT")
                SocketEventBus.updateStatus(ConnectionStatus.LISTENING)

                while (isActive && serverSocket?.isClosed == false) {
                    val clientSocket: Socket = try {
                        serverSocket?.accept() ?: break
                    } catch (e: Exception) {
                        if (!isActive) break
                        Log.w(tag, "Accept interrupted: ${e.message}")
                        continue
                    }

                    // Only allow one active desktop mirror session at a time for maximum bandwidth/security
                    activeSession?.close()

                    val session = ClientSession(
                        context = applicationContext,
                        socket = clientSocket,
                        scope = lifecycleScope,
                        onDisconnected = {
                            activeSession = null
                            SocketEventBus.updateStatus(ConnectionStatus.LISTENING)
                            // Remove screen privacy overlay when client disconnects
                            ScreenPrivacyOverlayService.stopOverlay(applicationContext)
                        }
                    )
                    activeSession = session
                    session.start()
                }

            } catch (e: Exception) {
                Log.e(tag, "Server socket runtime error: ${e.message}", e)
                SocketEventBus.updateStatus(ConnectionStatus.ERROR)
            }
        }
    }

    private fun observeConnectionStatus() {
        lifecycleScope.launch {
            SocketEventBus.connectionStatus.collect { status ->
                when (status) {
                    ConnectionStatus.LISTENING -> {
                        updateNotification(getString(R.string.notification_listening, DEFAULT_PORT))
                        ScreenPrivacyOverlayService.stopOverlay(applicationContext)
                    }
                    ConnectionStatus.AUTHORIZED -> {
                        val ip = SocketEventBus.connectedClientIp.value ?: "Desktop"
                        updateNotification(getString(R.string.notification_connected, ip))

                        // Section 1.4: Screen Privacy Handler (Dim/blur phone canvas when mirrored)
                        if (SocketEventBus.isScreenPrivacyEnabled.value) {
                            ScreenPrivacyOverlayService.startOverlay(applicationContext)
                        }
                    }
                    ConnectionStatus.STOPPED -> {
                        ScreenPrivacyOverlayService.stopOverlay(applicationContext)
                    }
                    else -> Unit
                }
            }
        }
    }

    /**
     * Routes inbound contract commands from Windows to respective subsystem handlers.
     */
    private fun observeInboundEvents() {
        lifecycleScope.launch {
            SocketEventBus.inboundPackets.collect { packet ->
                when (packet.eventType) {
                    "NOTIFICATION_REPLY" -> {
                        val reply = NotificationReplyData.fromJson(packet.data)
                        NotificationReplyHelper.executeQuickReply(applicationContext, reply)
                    }
                    "CLIPBOARD_SYNC" -> {
                        val clip = ClipboardSyncData.fromJson(packet.data)
                        ClipboardSyncHelper.updateSystemClipboard(applicationContext, clip.text)
                    }
                    "FILE_DROP" -> {
                        val fileDrop = FileDropData.fromJson(packet.data)
                        FileDropHelper.handleIncomingFile(applicationContext, fileDrop)
                    }
                    "HOTSPOT_REQUEST" -> {
                        val hotspot = HotspotRequestData.fromJson(packet.data)
                        SystemActionHelper.handleHotspotRequest(applicationContext, hotspot)
                    }
                    "SYSTEM_MODE_SYNC" -> {
                        val mode = SystemModeSyncData.fromJson(packet.data)
                        SystemActionHelper.handleModeSync(applicationContext, mode)
                    }
                }
            }
        }
    }

    private fun buildNotification(contentText: String): Notification {
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val stopIntent = Intent(this, SocketServerService::class.java).apply {
            action = ACTION_STOP_SERVER
        }
        val stopPendingIntent = PendingIntent.getService(
            this,
            1,
            stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, PixelMirrorApplication.CHANNEL_SERVICE_ID)
            .setContentTitle(getString(R.string.notification_title))
            .setContentText(contentText)
            .setSmallIcon(R.drawable.ic_mirror_tile)
            .setContentIntent(pendingIntent)
            .addAction(R.drawable.ic_visibility_off, "Stop", stopPendingIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()
    }

    private fun updateNotification(contentText: String) {
        val notification = buildNotification(contentText)
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
        manager.notify(PixelMirrorApplication.SERVICE_NOTIFICATION_ID, notification)
    }

    private fun stopServer() {
        try {
            activeSession?.close()
            activeSession = null
            serverSocket?.close()
            serverSocket = null
        } catch (_: Exception) {}
        serverJob?.cancel()
        serverJob = null
        SocketEventBus.updateStatus(ConnectionStatus.STOPPED)
        ScreenPrivacyOverlayService.stopOverlay(applicationContext)
    }

    override fun onDestroy() {
        stopServer()
        super.onDestroy()
        Log.i(tag, "SocketServerService destroyed.")
    }

    override fun onBind(intent: Intent): IBinder? {
        super.onBind(intent)
        return null
    }

    companion object {
        const val DEFAULT_PORT = 8080
        const val ACTION_START_SERVER = "com.google.pixelmirror.action.START_SERVER"
        const val ACTION_STOP_SERVER = "com.google.pixelmirror.action.STOP_SERVER"

        fun start(context: Context) {
            val intent = Intent(context, SocketServerService::class.java).apply {
                action = ACTION_START_SERVER
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            val intent = Intent(context, SocketServerService::class.java).apply {
                action = ACTION_STOP_SERVER
            }
            context.startService(intent)
        }
    }
}
