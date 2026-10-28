package com.voice.amharic.amharic_assistant

import android.app.Notification
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

class RasNotificationListenerService : NotificationListenerService() {

    override fun onListenerConnected() {
        super.onListenerConnected()
        instance = this
    }

    override fun onListenerDisconnected() {
        instance = null
        super.onListenerDisconnected()
    }

    override fun onDestroy() {
        instance = null
        super.onDestroy()
    }

    companion object {
        var instance: RasNotificationListenerService? = null

        fun isConnected(): Boolean = instance != null

        fun getActiveNotifications(): List<Map<String, Any>> {
            val s = instance ?: return emptyList()
            val list = mutableListOf<Map<String, Any>>()
            try {
                val active = s.activeNotifications ?: return emptyList()
                for (sbn in active) {
                    val extras = sbn.notification.extras
                    val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: ""
                    val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString() ?: ""
                    val subText = extras.getCharSequence(Notification.EXTRA_SUB_TEXT)?.toString() ?: ""
                    if (title.isNotEmpty() || text.isNotEmpty()) {
                        list.add(mapOf(
                            "id" to sbn.id,
                            "key" to sbn.key,
                            "package" to sbn.packageName,
                            "title" to title,
                            "text" to text,
                            "subText" to subText,
                            "isOngoing" to (sbn.isOngoing)
                        ))
                    }
                }
            } catch (_: Exception) {}
            return list
        }

        fun dismiss(key: String): Boolean {
            val s = instance ?: return false
            return try {
                s.cancelNotification(key)
                true
            } catch (_: Exception) {
                false
            }
        }
    }
}
