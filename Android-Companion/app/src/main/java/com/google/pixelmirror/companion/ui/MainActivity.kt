package com.google.pixelmirror.companion.ui

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import androidx.appcompat.app.AppCompatActivity
import androidx.core.app.NotificationManagerCompat
import androidx.lifecycle.lifecycleScope
import com.google.android.material.color.DynamicColors
import com.google.pixelmirror.companion.R
import com.google.pixelmirror.companion.crypto.CryptoManager
import com.google.pixelmirror.companion.databinding.ActivityMainBinding
import com.google.pixelmirror.companion.network.ConnectionStatus
import com.google.pixelmirror.companion.network.SocketEventBus
import com.google.pixelmirror.companion.network.SocketServerService
import com.google.pixelmirror.companion.service.MirrorNotificationListenerService
import com.google.pixelmirror.companion.util.ClipboardSyncHelper
import kotlinx.coroutines.launch

/**
 * Pixel Mirror V1 Dashboard.
 * Inherits active system wallpaper palette of the Pixel 10 via DynamicColors,
 * displaying socket status, 256-bit AES-GCM security, and permission clearance.
 */
class MainActivity : AppCompatActivity() {

    private lateinit var binding: ActivityMainBinding

    override fun onCreate(savedInstanceState: Bundle?) {
        DynamicColors.applyToActivityIfAvailable(this)

        super.onCreate(savedInstanceState)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)

        // Initialize cryptography and clipboard sync listeners
        CryptoManager.init(applicationContext)
        ClipboardSyncHelper.init(applicationContext)

        // Auto-start TCP Socket Server Service immediately on application launch
        SocketServerService.start(this)

        // Check if notification access clearance is granted; if not, prompt user
        val enabledListeners = Settings.Secure.getString(
            contentResolver,
            "enabled_notification_listeners"
        )
        if (enabledListeners == null || !enabledListeners.contains(packageName)) {
            val intent = Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
            startActivity(intent)
        }

        setupListeners()
        observeState()
    }

    override fun onResume() {
        super.onResume()
        updatePermissionStates()
        updateCryptoState()
    }

    private fun setupListeners() {
        // TCP Socket Server Master Switch
        binding.switchServerToggle.setOnCheckedChangeListener { _, isChecked ->
            val status = SocketEventBus.connectionStatus.value
            if (isChecked && (status == ConnectionStatus.STOPPED || status == ConnectionStatus.ERROR)) {
                SocketServerService.start(this)
            } else if (!isChecked && status != ConnectionStatus.STOPPED) {
                SocketServerService.stop(this)
            }
        }

        // Notification Listener Clearance Button
        binding.btnGrantNotifications.setOnClickListener {
            val intent = Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
            startActivity(intent)
        }

        // Battery Optimization Whitelist Button
        binding.btnGrantBattery.setOnClickListener {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                    data = Uri.parse("package:$packageName")
                }
                startActivity(intent)
            }
        }
    }

    private fun observeState() {
        lifecycleScope.launch {
            SocketEventBus.connectionStatus.collect { status ->
                when (status) {
                    ConnectionStatus.STOPPED, ConnectionStatus.ERROR -> {
                        binding.tvServerTitle.setText(R.string.status_server_stopped)
                        binding.tvServerSubtitle.setText(R.string.status_client_waiting)
                        if (binding.switchServerToggle.isChecked) {
                            binding.switchServerToggle.isChecked = false
                        }
                    }
                    ConnectionStatus.LISTENING -> {
                        binding.tvServerTitle.setText(R.string.status_server_running)
                        binding.tvServerSubtitle.setText(R.string.status_client_waiting)
                        if (!binding.switchServerToggle.isChecked) {
                            binding.switchServerToggle.isChecked = true
                        }
                    }
                    ConnectionStatus.CONNECTED -> {
                        binding.tvServerTitle.setText(R.string.status_server_running)
                        val ip = SocketEventBus.connectedClientIp.value ?: "Desktop"
                        binding.tvServerSubtitle.text = getString(R.string.status_client_connected, ip)
                        if (!binding.switchServerToggle.isChecked) {
                            binding.switchServerToggle.isChecked = true
                        }
                    }
                    ConnectionStatus.AUTHORIZED -> {
                        binding.tvServerTitle.setText(R.string.status_server_running)
                        val ip = SocketEventBus.connectedClientIp.value ?: "Desktop"
                        binding.tvServerSubtitle.text = getString(R.string.status_client_connected, "$ip (Authorized)")
                        if (!binding.switchServerToggle.isChecked) {
                            binding.switchServerToggle.isChecked = true
                        }
                    }
                }
                updateCryptoState()
            }
        }
    }

    private fun updateCryptoState() {
        if (CryptoManager.isAuthorized || CryptoManager.currentKey != null) {
            binding.tvCryptoTitle.setText(R.string.encryption_ready)
            binding.tvCryptoDesc.text = "Session active: AES-GCM 256-bit handshake validated."
        } else {
            binding.tvCryptoTitle.setText(R.string.encryption_pending)
            binding.tvCryptoDesc.text = "Connect via USB ADB to sync 256-bit AES-GCM session key"
        }
    }

    private fun updatePermissionStates() {
        // Notification Listener check
        val isNotifGranted = isNotificationServiceEnabled(MirrorNotificationListenerService::class.java)
        binding.btnGrantNotifications.text = if (isNotifGranted) getString(R.string.btn_granted) else getString(R.string.btn_grant)
        binding.btnGrantNotifications.isEnabled = !isNotifGranted

        // Battery Optimization check
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        val isBatteryIgnored = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            powerManager.isIgnoringBatteryOptimizations(packageName)
        } else true
        binding.btnGrantBattery.text = if (isBatteryIgnored) getString(R.string.btn_granted) else getString(R.string.btn_grant)
        binding.btnGrantBattery.isEnabled = !isBatteryIgnored
    }

    private fun isNotificationServiceEnabled(serviceClass: Class<*>): Boolean {
        val packageNames = NotificationManagerCompat.getEnabledListenerPackages(this)
        return packageNames.contains(packageName)
    }
}
