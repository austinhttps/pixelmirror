package com.google.pixelmirror.companion.ui

import android.accessibilityservice.AccessibilityServiceInfo
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import android.view.accessibility.AccessibilityManager
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
import com.google.pixelmirror.companion.service.MirrorAccessibilityService
import com.google.pixelmirror.companion.service.MirrorNotificationListenerService
import com.google.pixelmirror.companion.util.ClipboardSyncHelper
import kotlinx.coroutines.launch

/**
 * Section 5: Material Design 3 UI Aesthetics Dashboard.
 * Inherits the active system wallpaper palette of the Pixel 10 via DynamicColors,
 * featuring 24dp rounded cards and native Material motion switches.
 */
class MainActivity : AppCompatActivity() {

    private lateinit var binding: ActivityMainBinding

    override fun onCreate(savedInstanceState: Bundle?) {
        // Section 5: DynamicColors integration
        DynamicColors.applyToActivityIfAvailable(this)

        super.onCreate(savedInstanceState)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)

        // Initialize cryptography and clipboard sync listeners
        CryptoManager.init(applicationContext)
        ClipboardSyncHelper.init(applicationContext)

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

        // Screen Privacy Guard Switch
        binding.switchPrivacyGuard.setOnCheckedChangeListener { _, isChecked ->
            SocketEventBus.setScreenPrivacyEnabled(isChecked)
        }

        // Accessibility Service Button
        binding.btnGrantAccessibility.setOnClickListener {
            val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
            startActivity(intent)
        }

        // Notification Listener Button
        binding.btnGrantNotifications.setOnClickListener {
            val intent = Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
            startActivity(intent)
        }

        // Screen Privacy Overlay Button
        binding.btnGrantOverlay.setOnClickListener {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val intent = Intent(
                    Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                    Uri.parse("package:$packageName")
                )
                startActivity(intent)
            }
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
        // 1. Accessibility Service check
        val isA11yGranted = isAccessibilityServiceEnabled(MirrorAccessibilityService::class.java)
        binding.btnGrantAccessibility.text = if (isA11yGranted) getString(R.string.btn_granted) else getString(R.string.btn_grant)
        binding.btnGrantAccessibility.isEnabled = !isA11yGranted

        // 2. Notification Listener check
        val isNotifGranted = isNotificationServiceEnabled(MirrorNotificationListenerService::class.java)
        binding.btnGrantNotifications.text = if (isNotifGranted) getString(R.string.btn_granted) else getString(R.string.btn_grant)
        binding.btnGrantNotifications.isEnabled = !isNotifGranted

        // 3. Overlay check
        val isOverlayGranted = Settings.canDrawOverlays(this)
        binding.btnGrantOverlay.text = if (isOverlayGranted) getString(R.string.btn_granted) else getString(R.string.btn_grant)
        binding.btnGrantOverlay.isEnabled = !isOverlayGranted

        // 4. Battery Optimization check
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        val isBatteryIgnored = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            powerManager.isIgnoringBatteryOptimizations(packageName)
        } else true
        binding.btnGrantBattery.text = if (isBatteryIgnored) getString(R.string.btn_granted) else getString(R.string.btn_grant)
        binding.btnGrantBattery.isEnabled = !isBatteryIgnored
    }

    private fun isAccessibilityServiceEnabled(serviceClass: Class<*>): Boolean {
        val am = getSystemService(Context.ACCESSIBILITY_SERVICE) as AccessibilityManager
        val enabledServices = am.getEnabledAccessibilityServiceList(AccessibilityServiceInfo.FEEDBACK_ALL_MASK)
        for (service in enabledServices) {
            if (service.resolveInfo.serviceInfo.name == serviceClass.name) {
                return true
            }
        }
        return false
    }

    private fun isNotificationServiceEnabled(serviceClass: Class<*>): Boolean {
        val packageNames = NotificationManagerCompat.getEnabledListenerPackages(this)
        return packageNames.contains(packageName)
    }
}
