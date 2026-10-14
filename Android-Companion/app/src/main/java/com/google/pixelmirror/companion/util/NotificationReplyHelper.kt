package com.google.pixelmirror.companion.util

import android.app.Notification
import android.app.PendingIntent
import android.app.RemoteInput
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.service.notification.StatusBarNotification
import android.util.Log
import com.google.pixelmirror.companion.model.NotificationReplyData
import java.util.concurrent.ConcurrentHashMap

/**
 * Section 3.1: Interactive Notification Reply Helper.
 * Stores pending notification actions and executes native RemoteInput intents
 * for inline desktop quick replies.
 */
object NotificationReplyHelper {

    private const val tag = "NotificationReplyHelper"

    data class CachedAction(
        val pendingIntent: PendingIntent,
        val remoteInputs: Array<RemoteInput>
    )

    // Key: "packageName_notificationId"
    private val actionCache = ConcurrentHashMap<String, CachedAction>()

    fun registerNotification(sbn: StatusBarNotification) {
        val notification = sbn.notification ?: return
        val actions = notification.actions ?: return

        for (action in actions) {
            val remoteInputs = action.remoteInputs
            if (!remoteInputs.isNullOrEmpty() && action.actionIntent != null) {
                val key = buildKey(sbn.packageName, sbn.id)
                actionCache[key] = CachedAction(action.actionIntent, remoteInputs)
                Log.d(tag, "Cached quick-reply action for $key")
                break
            }
        }
    }

    fun unregisterNotification(id: Int, packageName: String) {
        actionCache.remove(buildKey(packageName, id))
    }

    /**
     * Executes the cached PendingIntent with the user's desktop reply string.
     */
    fun executeQuickReply(context: Context, reply: NotificationReplyData): Boolean {
        val key = buildKey(reply.packageName, reply.notificationId)
        val cached = actionCache[key]

        if (cached == null) {
            Log.w(tag, "No quick reply action found for key $key")
            return false
        }

        return try {
            val replyBundle = Bundle()
            for (input in cached.remoteInputs) {
                replyBundle.putCharSequence(input.resultKey, reply.replyText)
            }

            val replyIntent = Intent()
            RemoteInput.addResultsToIntent(cached.remoteInputs, replyIntent, replyBundle)

            cached.pendingIntent.send(context, 0, replyIntent)
            Log.i(tag, "Executed quick-reply to ${reply.packageName}: '${reply.replyText}'")
            true
        } catch (e: Exception) {
            Log.e(tag, "Failed to send quick reply: ${e.message}", e)
            false
        }
    }

    private fun buildKey(packageName: String, id: Int): String = "${packageName}_$id"
}
