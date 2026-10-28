package com.voice.amharic.amharic_assistant

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.graphics.Path
import android.graphics.Rect
import android.os.Build
import android.os.Bundle
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo

class RasAccessibilityService : AccessibilityService() {

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {}

    override fun onInterrupt() {}

    override fun onDestroy() {
        instance = null
        super.onDestroy()
    }

    companion object {
        var instance: RasAccessibilityService? = null

        fun isConnected(): Boolean = instance != null

        fun tap(x: Float, y: Float, callback: ((Boolean) -> Unit)? = null): Boolean {
            val s = instance ?: return false
            val path = Path().apply {
                moveTo(x, y)
            }
            val stroke = GestureDescription.StrokeDescription(path, 0, 50)
            val gesture = GestureDescription.Builder().addStroke(stroke).build()
            return s.dispatchGesture(gesture, object : GestureResultCallback() {
                override fun onCompleted(gestureDescription: GestureDescription?) {
                    callback?.invoke(true)
                }
                override fun onCancelled(gestureDescription: GestureDescription?) {
                    callback?.invoke(false)
                }
            }, null)
        }

        fun doubleTap(x: Float, y: Float, callback: ((Boolean) -> Unit)? = null): Boolean {
            return tap(x, y) { success ->
                if (success) {
                    android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                        tap(x, y, callback)
                    }, 120)
                } else {
                    callback?.invoke(false)
                }
            }
        }

        fun longPress(x: Float, y: Float, durationMs: Long = 800, callback: ((Boolean) -> Unit)? = null): Boolean {
            val s = instance ?: return false
            val path = Path().apply {
                moveTo(x, y)
            }
            val stroke = GestureDescription.StrokeDescription(path, 0, durationMs)
            val gesture = GestureDescription.Builder().addStroke(stroke).build()
            return s.dispatchGesture(gesture, object : GestureResultCallback() {
                override fun onCompleted(gestureDescription: GestureDescription?) {
                    callback?.invoke(true)
                }
                override fun onCancelled(gestureDescription: GestureDescription?) {
                    callback?.invoke(false)
                }
            }, null)
        }

        fun swipe(x1: Float, y1: Float, x2: Float, y2: Float, durationMs: Long = 300, callback: ((Boolean) -> Unit)? = null): Boolean {
            val s = instance ?: return false
            val path = Path().apply {
                moveTo(x1, y1)
                lineTo(x2, y2)
            }
            val stroke = GestureDescription.StrokeDescription(path, 0, durationMs)
            val gesture = GestureDescription.Builder().addStroke(stroke).build()
            return s.dispatchGesture(gesture, object : GestureResultCallback() {
                override fun onCompleted(gestureDescription: GestureDescription?) {
                    callback?.invoke(true)
                }
                override fun onCancelled(gestureDescription: GestureDescription?) {
                    callback?.invoke(false)
                }
            }, null)
        }

        fun scroll(direction: String, callback: ((Boolean) -> Unit)? = null): Boolean {
            val displayMetrics = android.content.res.Resources.getSystem().displayMetrics
            val cx = displayMetrics.widthPixels / 2f
            val h = displayMetrics.heightPixels.toFloat()
            return when (direction.lowercase()) {
                "up" -> swipe(cx, h * 0.7f, cx, h * 0.3f, 300, callback)
                "down" -> swipe(cx, h * 0.3f, cx, h * 0.7f, 300, callback)
                "left" -> swipe(cx * 1.5f, h * 0.5f, cx * 0.5f, h * 0.5f, 300, callback)
                "right" -> swipe(cx * 0.5f, h * 0.5f, cx * 1.5f, h * 0.5f, 300, callback)
                else -> swipe(cx, h * 0.7f, cx, h * 0.3f, 300, callback)
            }
        }

        fun typeText(text: String): Boolean {
            val s = instance ?: return false
            val root = s.rootInActiveWindow ?: return false
            val focused = root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT) ?: return false
            val arguments = Bundle().apply {
                putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, text)
            }
            return focused.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, arguments)
        }

        fun clearText(): Boolean {
            return typeText("")
        }

        fun getUiTree(): List<Map<String, Any>> {
            val s = instance ?: return emptyList()
            val root = s.rootInActiveWindow ?: return emptyList()
            val list = mutableListOf<Map<String, Any>>()
            traverseNode(root, list, 0)
            return list
        }

        private fun traverseNode(node: AccessibilityNodeInfo, list: MutableList<Map<String, Any>>, depth: Int) {
            val bounds = Rect()
            node.getBoundsInScreen(bounds)
            val text = node.text?.toString() ?: ""
            val desc = node.contentDescription?.toString() ?: ""
            val viewId = node.viewIdResourceName ?: ""
            val className = node.className?.toString() ?: ""

            if (text.isNotEmpty() || desc.isNotEmpty() || node.isClickable) {
                list.add(mapOf(
                    "depth" to depth,
                    "text" to text,
                    "description" to desc,
                    "id" to viewId,
                    "class" to className,
                    "clickable" to node.isClickable,
                    "bounds" to mapOf(
                        "left" to bounds.left,
                        "top" to bounds.top,
                        "right" to bounds.right,
                        "bottom" to bounds.bottom,
                        "centerX" to bounds.centerX(),
                        "centerY" to bounds.centerY()
                    )
                ))
            }

            for (i in 0 until node.childCount) {
                val child = node.getChild(i) ?: continue
                traverseNode(child, list, depth + 1)
            }
        }

        fun clickNodeContainingText(query: String): Boolean {
            val s = instance ?: return false
            val root = s.rootInActiveWindow ?: return false
            val list = mutableListOf<AccessibilityNodeInfo>()
            findNodesByTextRecursive(root, query.lowercase(), list)
            for (node in list) {
                var current: AccessibilityNodeInfo? = node
                while (current != null) {
                    if (current.isClickable) {
                        return current.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                    }
                    current = current.parent
                }
            }
            return false
        }

        private fun findNodesByTextRecursive(node: AccessibilityNodeInfo, query: String, result: MutableList<AccessibilityNodeInfo>) {
            val text = node.text?.toString()?.lowercase() ?: ""
            val desc = node.contentDescription?.toString()?.lowercase() ?: ""
            if (text.contains(query) || desc.contains(query)) {
                result.add(node)
            }
            for (i in 0 until node.childCount) {
                val child = node.getChild(i) ?: continue
                findNodesByTextRecursive(child, query, result)
            }
        }

        private fun collectAllNodes(node: AccessibilityNodeInfo, result: MutableList<AccessibilityNodeInfo>) {
            result.add(node)
            for (i in 0 until node.childCount) {
                val child = node.getChild(i) ?: continue
                collectAllNodes(child, result)
            }
        }

        private fun hasChildWithText(parent: AccessibilityNodeInfo, targetText: String): Boolean {
            for (i in 0 until parent.childCount) {
                val child = parent.getChild(i) ?: continue
                val text = child.text?.toString() ?: ""
                val desc = child.contentDescription?.toString() ?: ""
                if (text.equals(targetText, ignoreCase = true) || desc.equals(targetText, ignoreCase = true)) {
                    return true
                }
            }
            return false
        }

        private fun clickClickableParentOrCenter(node: AccessibilityNodeInfo, bounds: Rect): Boolean {
            var current: AccessibilityNodeInfo? = node
            while (current != null) {
                if (current.isClickable) {
                    return current.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                }
                current = current.parent
            }
            return tap(bounds.centerX().toFloat(), bounds.centerY().toFloat())
        }

        fun clickFirstSpotifyTrack(queryWords: List<String>): Boolean {
            val s = instance ?: run {
                android.util.Log.w("RasA11y", "clickFirstSpotifyTrack: instance is null")
                return false
            }
            val root = s.rootInActiveWindow ?: run {
                android.util.Log.w("RasA11y", "clickFirstSpotifyTrack: rootInActiveWindow is null")
                return false
            }

            val allNodes = mutableListOf<AccessibilityNodeInfo>()
            collectAllNodes(root, allNodes)

            // Priority 1: Direct song items with "Song •" or "Song" subtitle (below the filter chips)
            for (node in allNodes) {
                val text = node.text?.toString() ?: ""
                val desc = node.contentDescription?.toString() ?: ""
                val bounds = Rect()
                node.getBoundsInScreen(bounds)
                if (bounds.top in 360..1900 && !text.equals("Songs", ignoreCase = true)) {
                    if (text.startsWith("Song •", ignoreCase = true) || text.equals("Song", ignoreCase = true) ||
                        desc.startsWith("Song •", ignoreCase = true) || desc.equals("Song", ignoreCase = true)) {
                        android.util.Log.i("RasA11y", "Found direct Song item at $bounds. Clicking container...")
                        return clickClickableParentOrCenter(node, bounds)
                    }
                }
            }

            // Priority 2: If on search overview and "Songs" filter chip is UNCHECKED, click it to filter to pure songs
            for (node in allNodes) {
                val text = node.text?.toString() ?: ""
                val bounds = Rect()
                node.getBoundsInScreen(bounds)
                if (text.equals("Songs", ignoreCase = true) && bounds.top in 240..360) {
                    val parent = node.parent
                    val isChecked = node.isChecked || (parent != null && parent.isChecked)
                    if (!isChecked) {
                        android.util.Log.i("RasA11y", "Songs chip is UNCHECKED. Clicking 'Songs' filter chip at $bounds...")
                        clickClickableParentOrCenter(node, bounds)
                        // Return false so polling loop continues and clicks the first song on next tick!
                        return false
                    }
                }
            }

            // Priority 3: Filtered songs list (track items with :id/title in range 450..1900)
            for (node in allNodes) {
                val bounds = Rect()
                node.getBoundsInScreen(bounds)
                val viewId = node.viewIdResourceName ?: ""
                if (viewId.endsWith(":id/title") && bounds.top in 450..1900) {
                    val parent = node.parent
                    val isArtist = parent?.let { hasChildWithText(it, "Artist") } ?: false
                    val isPlaylist = parent?.let { hasChildWithText(it, "Playlist") } ?: false
                    if (!isArtist && !isPlaylist) {
                        android.util.Log.i("RasA11y", "Found track title '${node.text}' at $bounds. Clicking...")
                        return clickClickableParentOrCenter(node, bounds)
                    }
                }
            }

            // Priority 4: Keyword match excluding EditText, Artist, and Playlist cards
            for (word in queryWords) {
                if (word.length < 3) continue
                for (node in allNodes) {
                    val className = node.className?.toString() ?: ""
                    if (className.contains("EditText")) continue
                    val text = node.text?.toString() ?: ""
                    val desc = node.contentDescription?.toString() ?: ""
                    if (text.contains(word, ignoreCase = true) || desc.contains(word, ignoreCase = true)) {
                        val bounds = Rect()
                        node.getBoundsInScreen(bounds)
                        if (bounds.top in 360..1900) {
                            val parent = node.parent
                            val isArtist = parent?.let { hasChildWithText(it, "Artist") } ?: false
                            val isPlaylist = parent?.let { hasChildWithText(it, "Playlist") } ?: false
                            if (!isArtist && !isPlaylist) {
                                android.util.Log.i("RasA11y", "Clicking candidate node for '$word' at $bounds")
                                return clickClickableParentOrCenter(node, bounds)
                            }
                        }
                    }
                }
            }

            android.util.Log.w("RasA11y", "clickFirstSpotifyTrack: No matching playable song item found")
            return false
        }

        fun clickNodeByText(query: String): Boolean {
            return clickNodeContainingText(query)
        }

        fun clickNodeByDescription(query: String): Boolean {
            return clickNodeContainingText(query)
        }

        fun performGlobalAction(actionId: Int): Boolean {
            val s = instance ?: return false
            return s.performGlobalAction(actionId)
        }
    }
}
