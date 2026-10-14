package com.google.pixelmirror.companion.network

import com.google.pixelmirror.companion.model.EventPacket
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow

enum class ConnectionStatus {
    STOPPED,
    LISTENING,
    CONNECTED,
    AUTHORIZED,
    ERROR
}

/**
 * Reactive bus coordinating communication between background services,
 * system receivers, and the active TCP socket session.
 */
object SocketEventBus {

    // Status state
    private val _connectionStatus = MutableStateFlow(ConnectionStatus.STOPPED)
    val connectionStatus: StateFlow<ConnectionStatus> = _connectionStatus.asStateFlow()

    private val _connectedClientIp = MutableStateFlow<String?>(null)
    val connectedClientIp: StateFlow<String?> = _connectedClientIp.asStateFlow()

    private val _isScreenPrivacyEnabled = MutableStateFlow(true)
    val isScreenPrivacyEnabled: StateFlow<Boolean> = _isScreenPrivacyEnabled.asStateFlow()

    // Outbound packets from Android services to Windows Client
    private val _outboundPackets = MutableSharedFlow<EventPacket>(extraBufferCapacity = 64)
    val outboundPackets: SharedFlow<EventPacket> = _outboundPackets.asSharedFlow()

    // Inbound packets from Windows Client to Android services
    private val _inboundPackets = MutableSharedFlow<EventPacket>(extraBufferCapacity = 64)
    val inboundPackets: SharedFlow<EventPacket> = _inboundPackets.asSharedFlow()

    fun updateStatus(status: ConnectionStatus, clientIp: String? = null) {
        _connectionStatus.value = status
        _connectedClientIp.value = clientIp
    }

    fun setScreenPrivacyEnabled(enabled: Boolean) {
        _isScreenPrivacyEnabled.value = enabled
    }

    /**
     * Broadcast an event packet from any Android service to the connected Windows client.
     */
    fun postOutbound(packet: EventPacket) {
        _outboundPackets.tryEmit(packet)
    }

    /**
     * Deliver an event packet parsed from the TCP stream to listening Android components.
     */
    fun postInbound(packet: EventPacket) {
        _inboundPackets.tryEmit(packet)
    }
}
