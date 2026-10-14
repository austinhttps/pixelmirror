package com.google.pixelmirror.companion.model

import org.json.JSONArray
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

// 3.1 Plaintext Accessibility UI Tree Payload (FLAG_SECURE DRM Workaround)
data class NodeBounds(
    val top: Int,
    val left: Int,
    val bottom: Int,
    val right: Int
) {
    fun toJson(): JSONObject {
        return JSONObject().apply {
            put("top", top)
            put("left", left)
            put("bottom", bottom)
            put("right", right)
        }
    }
}

data class AccessibilityNodeMap(
    val nodeId: String,
    val className: String,
    val text: String,
    val isClickable: Boolean,
    val bounds: NodeBounds
) {
    fun toJson(): JSONObject {
        return JSONObject().apply {
            put("node_id", nodeId)
            put("class_name", className)
            put("text", text)
            put("is_clickable", isClickable)
            put("bounds", bounds.toJson())
        }
    }
}

data class SecureWindowMapData(
    val packageName: String,
    val nodes: List<AccessibilityNodeMap>
) {
    fun toEventPacket(): EventPacket {
        val array = JSONArray()
        nodes.forEach { array.put(it.toJson()) }

        val data = JSONObject().apply {
            put("package_name", packageName)
            put("nodes", array)
        }
        return EventPacket("SECURE_WINDOW_MAP", System.currentTimeMillis() / 1000, data)
    }
}

// 3.2 Dynamic Action / Touch Mapping Payload
data class RemoteInputActionData(
    val actionType: String, // "CLICK_COORDINATE", "GLOBAL_BACK", "GLOBAL_HOME", etc.
    val targetX: Int,
    val targetY: Int
) {
    companion object {
        fun fromJson(data: JSONObject): RemoteInputActionData {
            return RemoteInputActionData(
                actionType = data.optString("action_type", "CLICK_COORDINATE"),
                targetX = data.optInt("target_x", 0),
                targetY = data.optInt("target_y", 0)
            )
        }
    }
}

// 4.1 Phone Mode Toggle Payload
data class SystemModeSyncData(
    val modeType: String, // "DO_NOT_DISTURB", "RINGER_MODE"
    val isEnabled: Boolean
) {
    fun toEventPacket(): EventPacket {
        val data = JSONObject().apply {
            put("mode_type", modeType)
            put("is_enabled", isEnabled)
        }
        return EventPacket("SYSTEM_MODE_SYNC", System.currentTimeMillis() / 1000, data)
    }

    companion object {
        fun fromJson(data: JSONObject): SystemModeSyncData {
            return SystemModeSyncData(
                modeType = data.optString("mode_type", "DO_NOT_DISTURB"),
                isEnabled = data.optBoolean("is_enabled", false)
            )
        }
    }
}

// 4.2 Hotspot Trigger Request
data class HotspotRequestData(
    val action: String // "LAUNCH_TETHER_SETTINGS"
) {
    companion object {
        fun fromJson(data: JSONObject): HotspotRequestData {
            return HotspotRequestData(
                action = data.optString("action", "LAUNCH_TETHER_SETTINGS")
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

// Smart File Drop & Quick Share Payload
data class FileDropData(
    val filename: String,
    val mimeType: String,
    val fileBase64: String,
    val targetX: Int,
    val targetY: Int,
    val isCanvasPaste: Boolean
) {
    companion object {
        fun fromJson(data: JSONObject): FileDropData {
            return FileDropData(
                filename = data.optString("filename", "drop_${System.currentTimeMillis()}"),
                mimeType = data.optString("mime_type", "application/octet-stream"),
                fileBase64 = data.getString("file_base64"),
                targetX = data.optInt("target_x", -1),
                targetY = data.optInt("target_y", -1),
                isCanvasPaste = data.optBoolean("is_canvas_paste", true)
            )
        }
    }
}
