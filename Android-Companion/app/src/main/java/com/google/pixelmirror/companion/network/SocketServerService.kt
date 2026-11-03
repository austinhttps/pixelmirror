package com.google.pixelmirror.companion.network

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.lifecycle.LifecycleService
import androidx.lifecycle.lifecycleScope
import com.google.pixelmirror.companion.PixelMirrorApplication
import com.google.pixelmirror.companion.R
import com.google.pixelmirror.companion.model.ClipboardSyncData
import com.google.pixelmirror.companion.model.NotificationReplyData
import com.google.pixelmirror.companion.ui.MainActivity
import com.google.pixelmirror.companion.util.ClipboardSyncHelper
import com.google.pixelmirror.companion.util.NotificationReplyHelper
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.net.ServerSocket
import java.net.Socket

/**
 * High-performance background Foreground Service hosting the local TCP socket server
 * on port 8080 for notifications and clipboard synchronization.
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
        // Immediate Foreground Service promotion within onStartCommand
        ensureNotificationChannel()
        val notification = buildNotification(getString(R.string.notification_listening, DEFAULT_PORT))

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                PixelMirrorApplication.SERVICE_NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE
            )
        } else {
            startForeground(
                PixelMirrorApplication.SERVICE_NOTIFICATION_ID,
                notification
            )
        }

        super.onStartCommand(intent, flags, startId)

        val action = intent?.action
        if (action == ACTION_STOP_SERVER) {
            stopServer()
            stopSelf()
            return START_NOT_STICKY
        }

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

                    try {
                        // Single-session tracking: Close previous session if any
                        activeSession?.close()

                        val session = ClientSession(
                            context = applicationContext,
                            socket = clientSocket,
                            scope = lifecycleScope,
                            onDisconnected = {
                                activeSession = null
                                SocketEventBus.updateStatus(ConnectionStatus.LISTENING)
                            }
                        )
                        activeSession = session
                        session.start()
                    } catch (e: Exception) {
                        Log.e(tag, "Client session handling error: ${e.message}", e)
                    }
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
                    }
                    ConnectionStatus.AUTHORIZED -> {
                        val ip = SocketEventBus.connectedClientIp.value ?: "Desktop"
                        updateNotification(getString(R.string.notification_connected, ip))
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
                }
            }
        }
    }

    private fun ensureNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            if (manager != null && manager.getNotificationChannel(CHANNEL_STREAM_ID) == null) {
                val channel = NotificationChannel(
                    CHANNEL_STREAM_ID,
                    getString(R.string.notification_channel_name),
                    NotificationManager.IMPORTANCE_LOW
                ).apply {
                    description = getString(R.string.notification_channel_desc)
                    setShowBadge(false)
                }
                manager.createNotificationChannel(channel)
            }
        }
    }

    private fun buildNotification(contentText: String): Notification {
        ensureNotificationChannel()

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

        return NotificationCompat.Builder(this, CHANNEL_STREAM_ID)
            .setContentTitle(getString(R.string.notification_title))
            .setContentText(contentText)
            .setSmallIcon(R.drawable.ic_mirror_tile)
            .setContentIntent(pendingIntent)
            .addAction(R.drawable.ic_cell_tower, "Stop", stopPendingIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()
    }

    private fun updateNotification(contentText: String) {
        val notification = buildNotification(contentText)
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
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
        const val CHANNEL_STREAM_ID = "pixel_mirror_stream"
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
