package com.google.pixelmirror.companion.network

import android.content.Context
import android.util.Log
import com.google.pixelmirror.companion.crypto.CryptoManager
import com.google.pixelmirror.companion.model.EventPacket
import com.google.pixelmirror.companion.model.HandshakeInit
import com.google.pixelmirror.companion.model.HandshakeResponse
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import org.json.JSONObject
import java.io.BufferedReader
import java.io.BufferedWriter
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.net.Socket
import java.nio.charset.StandardCharsets

/**
 * Manages an individual client TCP connection lifecycle, cryptographic handshake,
 * framing, and bidirectional packet transmission according to API_CONTRACT.md.
 */
class ClientSession(
    private val context: Context,
    private val socket: Socket,
    private val scope: CoroutineScope,
    private val onDisconnected: () -> Unit
) {

    private val tag = "ClientSession"
    private var writeJob: Job? = null
    private var reader: BufferedReader? = null
    private var writer: BufferedWriter? = null

    val clientIp: String = socket.inetAddress?.hostAddress ?: "Unknown"

    fun start() {
        scope.launch(Dispatchers.IO) {
            try {
                reader = BufferedReader(InputStreamReader(socket.getInputStream(), StandardCharsets.UTF_8))
                writer = BufferedWriter(OutputStreamWriter(socket.getOutputStream(), StandardCharsets.UTF_8))

                Log.i(tag, "Client connected from $clientIp. Awaiting cryptographic handshake...")
                SocketEventBus.updateStatus(ConnectionStatus.CONNECTED, clientIp)

                // 1. Perform Cryptographic Handshake (Section 1 of API_CONTRACT.md)
                val isHandshakeOk = performHandshake()
                if (!isHandshakeOk) {
                    Log.w(tag, "Handshake validation challenge failed. Dropping connection immediately.")
                    close()
                    return@launch
                }

                SocketEventBus.updateStatus(ConnectionStatus.AUTHORIZED, clientIp)
                Log.i(tag, "Handshake successful. Established 256-bit AES-GCM session with $clientIp.")

                // 2. Launch outbound streaming loop
                startOutboundLoop()

                // 3. Inbound reading loop
                readInboundLoop()

            } catch (e: Exception) {
                Log.e(tag, "Socket connection error with $clientIp: ${e.message}")
            } finally {
                close()
            }
        }
    }

    /**
     * Executes initial handshake verification:
     * Expects HANDSHAKE_INIT, parses 256-bit secret key, registers it, and responds with AUTHORIZED.
     */
    private fun performHandshake(): Boolean {
        return try {
            val rawMessage = readNextJsonChunk() ?: return false
            Log.d(tag, "Handshake raw payload received: $rawMessage")

            val json = JSONObject(rawMessage)
            val type = json.optString("type")

            if (type != "HANDSHAKE_INIT") {
                Log.e(tag, "Unexpected handshake type: $type")
                return false
            }

            val handshakeInit = HandshakeInit.fromJson(json)
            val keyRegistered = CryptoManager.registerSessionKey(context, handshakeInit.secretKeyB64)

            if (!keyRegistered) {
                // Send unauthorized and drop
                val failResponse = HandshakeResponse(status = "UNAUTHORIZED")
                sendRaw(failResponse.toJson().toString())
                return false
            }

            // Send successful authorization response
            val successResponse = HandshakeResponse(
                status = "AUTHORIZED",
                deviceName = "Google Pixel 10"
            )
            sendRaw(successResponse.toJson().toString())
            true
        } catch (e: Exception) {
            Log.e(tag, "Exception during handshake execution: ${e.message}", e)
            false
        }
    }

    /**
     * Collects outbound packets from SocketEventBus and flushes them across the socket.
     */
    private fun startOutboundLoop() {
        writeJob = scope.launch(Dispatchers.IO) {
            SocketEventBus.outboundPackets.collect { packet ->
                if (!socket.isConnected || socket.isClosed) return@collect

                try {
                    val rawJson = packet.toJson().toString()
                    sendRaw(rawJson)
                    Log.d(tag, "Sent outbound event: ${packet.eventType}")
                } catch (e: Exception) {
                    Log.e(tag, "Failed to send outbound packet: ${e.message}")
                }
            }
        }
    }

    /**
     * Continuously reads inbound event payloads from Windows desktop client.
     */
    private fun readInboundLoop() {
        while (scope.isActive && !socket.isClosed) {
            val chunk = readNextJsonChunk() ?: break
            try {
                // Parse either plaintext or decrypt payload
                val packetJson = if (chunk.startsWith("{") && chunk.contains("\"event_type\"")) {
                    JSONObject(chunk)
                } else {
                    // Decrypt encrypted payload if applicable
                    val decryptedString = CryptoManager.decryptPayload(chunk)
                    JSONObject(decryptedString)
                }

                val packet = EventPacket.fromJson(packetJson)
                Log.d(tag, "Received inbound event: ${packet.eventType}")
                SocketEventBus.postInbound(packet)

            } catch (e: Exception) {
                Log.w(tag, "Failed to parse inbound message: ${e.message} (Payload: $chunk)")
            }
        }
    }

    /**
     * Sends a raw string chunk across the TCP socket.
     */
    private synchronized fun sendRaw(message: String) {
        val out = writer ?: return
        out.write(message)
        out.newLine() // Delimit chunks cleanly
        out.flush()
    }

    /**
     * Reads a complete JSON object from the stream, handling buffer chunks or line breaks.
     */
    private fun readNextJsonChunk(): String? {
        val inStream = reader ?: return null
        val buffer = CharArray(4096)
        val sb = StringBuilder()
        var braceDepth = 0
        var inString = false
        var isEscaped = false
        var objectStarted = false

        while (true) {
            val charsRead = inStream.read(buffer)
            if (charsRead == -1) {
                if (sb.isNotEmpty()) return sb.toString().trim()
                return null
            }

            for (i in 0 until charsRead) {
                val c = buffer[i]
                sb.append(c)

                if (c == '"' && !isEscaped) {
                    inString = !inString
                } else if (c == '\\' && inString) {
                    isEscaped = !isEscaped
                    continue
                } else if (!inString) {
                    if (c == '{') {
                        braceDepth++
                        objectStarted = true
                    } else if (c == '}') {
                        braceDepth--
                        if (objectStarted && braceDepth == 0) {
                            return sb.toString().trim()
                        }
                    }
                }
                isEscaped = false
            }
        }
    }

    fun close() {
        writeJob?.cancel()
        try {
            reader?.close()
        } catch (_: Exception) {}
        try {
            writer?.close()
        } catch (_: Exception) {}
        try {
            socket.close()
        } catch (_: Exception) {}

        CryptoManager.resetAuthorization()
        onDisconnected()
    }
}
