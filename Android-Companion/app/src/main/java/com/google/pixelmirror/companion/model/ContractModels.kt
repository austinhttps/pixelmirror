package com.google.pixelmirror.companion.model

import org.json.JSONObject

/**
 * Data models and serialization utilities conforming directly to API_CONTRACT.md.
 */

// 1. Handshake Models
data class HandshakeInit(
    val type: String = "HANDSHAKE_INIT",
    val version: String = "1.0.0",
    val timestamp: Long = System.currentTimeMillis() / 1000,
    val secretKeyB64: String
) {
    companion object {
        fun fromJson(json: JSONObject): HandshakeInit {
            val payload = json.getJSONObject("payload")
            return HandshakeInit(
                type = json.optString("type", "HANDSHAKE_INIT"),
                version = json.optString("version", "1.0.0"),
                timestamp = json.optLong("timestamp", System.currentTimeMillis() / 1000),
                secretKeyB64 = payload.getString("secret_key_b64")
            )
        }
    }
}

data class HandshakeResponse(
    val type: String = "HANDSHAKE_RESPONSE",
    val status: String, // "AUTHORIZED" or "UNAUTHORIZED"
    val deviceName: String = "Google Pixel 10"
) {
    fun toJson(): JSONObject {
        return JSONObject().apply {
            put("type", type)
            put("status", status)
            put("device_name", deviceName)
        }
    }
}

// 2. Core Event Data Framing Packet
data class EventPacket(
    val eventType: String,
    val timestamp: Long = System.currentTimeMillis() / 1000,
    val data: JSONObject
) {
    fun toJson(): JSONObject {
        return JSONObject().apply {
            put("event_type", eventType)
            put("timestamp", timestamp)
            put("data", data)
        }
    }

    companion object {
        fun fromJson(json: JSONObject): EventPacket {
            return EventPacket(
                eventType = json.getString("event_type"),
                timestamp = json.optLong("timestamp", System.currentTimeMillis() / 1000),
                data = json.optJSONObject("data") ?: JSONObject()
            )
        }
    }
}

// 2.1 Interactive Notification Enqueue Payload
data class NotificationEnqueueData(
    val notificationId: Int,
    val packageName: String,
    val appLabel: String,
    val title: String,
    val body: String,
    val iconBase64: String
) {
    fun toEventPacket(): EventPacket {
        val json = JSONObject().apply {
            put("notification_id", notificationId)
            put("package_name", packageName)
            put("app_label", appLabel)
            put("title", title)
            put("body", body)
            put("icon_base64", iconBase64)
        }
        return EventPacket("NOTIFICATION_ENQUEUE", System.currentTimeMillis() / 1000, json)
    }
}

// 2.2 Interactive Quick-Reply Payload
data class NotificationReplyData(
    val notificationId: Int,
    val packageName: String,
    val replyText: String
) {
    companion object {
        fun fromJson(data: JSONObject): NotificationReplyData {
            return NotificationReplyData(
                notificationId = data.getInt("notification_id"),
                packageName = data.getString("package_name"),
                replyText = data.getString("reply_text")
            )
        }
    }
}

// Clipboard Sync Payload
data class ClipboardSyncData(
    val text: String
) {
    fun toEventPacket(): EventPacket {
        val data = JSONObject().apply {
            put("text", text)
        }
        return EventPacket("CLIPBOARD_SYNC", System.currentTimeMillis() / 1000, data)
    }

    companion object {
        fun fromJson(data: JSONObject): ClipboardSyncData {
            return ClipboardSyncData(
                text = data.optString("text", "")
            )
        }
    }
}

