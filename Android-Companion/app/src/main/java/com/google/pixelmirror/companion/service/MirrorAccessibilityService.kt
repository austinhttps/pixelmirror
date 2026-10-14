package com.google.pixelmirror.companion.service

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.graphics.Path
import android.graphics.Rect
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import com.google.pixelmirror.companion.model.AccessibilityNodeMap
import com.google.pixelmirror.companion.model.NodeBounds
import com.google.pixelmirror.companion.model.RemoteInputActionData
import com.google.pixelmirror.companion.model.SecureWindowMapData
import com.google.pixelmirror.companion.network.ConnectionStatus
import com.google.pixelmirror.companion.network.SocketEventBus
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * Section 4 & Section 3.3: Native AccessibilityService.
 * 1. Bypasses FLAG_SECURE video recording blackouts in banking apps by scraping
 *    the AccessibilityNodeInfo view hierarchy into structured SECURE_WINDOW_MAP payloads.
 * 2. Injects remote touch gestures (CLICK_COORDINATE) for desktop mouse interactions.
 * 3. Executes macro tap & PASTE actions for Smart File Drops.
 */
class MirrorAccessibilityService : AccessibilityService() {

    private val tag = "MirrorA11yService"
    private val scope = CoroutineScope(Dispatchers.Main)
    private var inboundJob: Job? = null

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        Log.i(tag, "Pixel Mirror Accessibility Service connected.")
        observeInboundGestures()
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return

        val status = SocketEventBus.connectionStatus.value
        if (status != ConnectionStatus.AUTHORIZED && status != ConnectionStatus.CONNECTED) {
            return
        }

        // Section 4: Monitor for TYPE_WINDOW_STATE_CHANGED
        if (event.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) {
            val pkg = event.packageName?.toString() ?: return
            handleWindowStateChanged(pkg)
        }
    }

    /**
     * Recursively scrapes the live AccessibilityNodeInfo view hierarchy tree
     * and broadcasts a SECURE_WINDOW_MAP packet down the socket.
     */
    private fun handleWindowStateChanged(packageName: String) {
        val rootNode = rootInActiveWindow ?: return

        try {
            val nodeList = mutableListOf<AccessibilityNodeMap>()
            extractNodesRecursively(rootNode, nodeList)

            if (nodeList.isNotEmpty()) {
                val mapData = SecureWindowMapData(
                    packageName = packageName,
                    nodes = nodeList
                )
                Log.d(tag, "Scraped ${nodeList.size} secure nodes from $packageName")
                SocketEventBus.postOutbound(mapData.toEventPacket())
            }
        } catch (e: Exception) {
            Log.e(tag, "Error scraping node tree: ${e.message}", e)
        } finally {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                // Node recycling handled automatically on modern Android
            } else {
                @Suppress("DEPRECATION")
                rootNode.recycle()
            }
        }
    }

    private fun extractNodesRecursively(
        node: AccessibilityNodeInfo,
        outList: MutableList<AccessibilityNodeMap>
    ) {
        if (!node.isVisibleToUser) return

        val text = node.text?.toString() ?: node.contentDescription?.toString() ?: ""
        val className = node.className?.toString() ?: ""
        val resId = node.viewIdResourceName ?: "node_${outList.size}"
        val isClickable = node.isClickable

        val rect = Rect()
        node.getBoundsInScreen(rect)

        // Only include nodes with valid screen footprint and text or interactive capabilities
        if (!rect.isEmpty && (text.isNotBlank() || isClickable)) {
            val bounds = NodeBounds(
                top = rect.top,
                left = rect.left,
                bottom = rect.bottom,
                right = rect.right
            )
            outList.add(
                AccessibilityNodeMap(
                    nodeId = resId,
                    className = className,
                    text = text,
                    isClickable = isClickable,
                    bounds = bounds
                )
            )
        }

        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            extractNodesRecursively(child, outList)
        }
    }

    /**
     * Listens for remote input and file drop macro requests from the TCP stream.
     */
    private fun observeInboundGestures() {
        inboundJob?.cancel()
        inboundJob = scope.launch {
            SocketEventBus.inboundPackets.collect { packet ->
                if (packet.eventType == "REMOTE_INPUT_ACTION") {
                    val action = RemoteInputActionData.fromJson(packet.data)
                    handleRemoteInput(action)
                }
            }
        }
    }

    /**
     * Dispatches a tap gesture at target (X, Y) layout coordinates.
     */
    fun performClick(x: Float, y: Float, onComplete: (() -> Unit)? = null) {
        val path = Path().apply {
            moveTo(x, y)
        }
        val stroke = GestureDescription.StrokeDescription(path, 0, 50)
        val gesture = GestureDescription.Builder().addStroke(stroke).build()

        dispatchGesture(gesture, object : GestureResultCallback() {
            override fun onCompleted(gestureDescription: GestureDescription?) {
                super.onCompleted(gestureDescription)
                Log.d(tag, "Dispatched tap at ($x, $y)")
                onComplete?.invoke()
            }

            override fun onCancelled(gestureDescription: GestureDescription?) {
                super.onCancelled(gestureDescription)
                Log.w(tag, "Tap gesture cancelled at ($x, $y)")
            }
        }, null)
    }

    /**
     * Section 3.3: Executes target coordinate macro:
     * Taps at incoming (target_x, target_y) to focus the destination app,
     * then injects a programmatic PASTE action command.
     */
    fun performFocusAndPaste(x: Float, y: Float) {
        performClick(x, y) {
            scope.launch {
                // Short delay to allow destination window/field focus
                delay(150)
                injectPasteAction()
            }
        }
    }

    private fun injectPasteAction() {
        val rootNode = rootInActiveWindow ?: return
        val focusedNode = rootNode.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
            ?: rootNode.findFocus(AccessibilityNodeInfo.FOCUS_ACCESSIBILITY)

        if (focusedNode != null) {
            val arguments = Bundle().apply {
                putInt(AccessibilityNodeInfo.ACTION_ARGUMENT_EXTEND_SELECTION_BOOLEAN, 0)
            }
            val success = focusedNode.performAction(AccessibilityNodeInfo.ACTION_PASTE, arguments)
            Log.d(tag, "Programmatic ACTION_PASTE execution result: $success")
        } else {
            // Fallback: search for editable fields
            searchAndPaste(rootNode)
        }
    }

    private fun searchAndPaste(node: AccessibilityNodeInfo): Boolean {
        if (node.isEditable) {
            return node.performAction(AccessibilityNodeInfo.ACTION_PASTE)
        }
        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            if (searchAndPaste(child)) return true
        }
        return false
    }

    private fun handleRemoteInput(action: RemoteInputActionData) {
        when (action.actionType) {
            "CLICK_COORDINATE" -> {
                performClick(action.targetX.toFloat(), action.targetY.toFloat())
            }
            "GLOBAL_BACK" -> performGlobalAction(GLOBAL_ACTION_BACK)
            "GLOBAL_HOME" -> performGlobalAction(GLOBAL_ACTION_HOME)
            "GLOBAL_RECENTS" -> performGlobalAction(GLOBAL_ACTION_RECENTS)
        }
    }

    override fun onInterrupt() {
        Log.w(tag, "MirrorAccessibilityService interrupted.")
    }

    override fun onDestroy() {
        instance = null
        inboundJob?.cancel()
        super.onDestroy()
    }

    companion object {
        @Volatile
        var instance: MirrorAccessibilityService? = null
            private set
    }
}
