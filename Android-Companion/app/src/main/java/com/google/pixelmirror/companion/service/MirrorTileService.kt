package com.google.pixelmirror.companion.service

import android.graphics.drawable.Icon
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import android.util.Log
import com.google.pixelmirror.companion.R
import com.google.pixelmirror.companion.network.ConnectionStatus
import com.google.pixelmirror.companion.network.SocketEventBus
import com.google.pixelmirror.companion.network.SocketServerService
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

/**
 * Section 1.3: Quick Settings TileService labeled "Pixel Mirror".
 * Provides a pull-down quick setting toggle to programmatically initialize
 * or completely terminate the background socket server to preserve battery life.
 */
class MirrorTileService : TileService() {

    private val tag = "MirrorTileService"
    private var stateObserverJob: Job? = null
    private val scope = CoroutineScope(Dispatchers.Main)

    override fun onStartListening() {
        super.onStartListening()
        Log.d(tag, "Tile started listening.")
        observeServerState()
    }

    override fun onStopListening() {
        super.onStopListening()
        stateObserverJob?.cancel()
        stateObserverJob = null
    }

    private fun observeServerState() {
        stateObserverJob?.cancel()
        stateObserverJob = scope.launch {
            SocketEventBus.connectionStatus.collect { status ->
                updateTileState(status)
            }
        }
    }

    override fun onClick() {
        super.onClick()
        val currentStatus = SocketEventBus.connectionStatus.value
        Log.i(tag, "Tile clicked. Current status: $currentStatus")

        if (currentStatus == ConnectionStatus.STOPPED || currentStatus == ConnectionStatus.ERROR) {
            // Start the background TCP socket server
            SocketServerService.start(applicationContext)
        } else {
            // Terminate background TCP server to preserve battery life
            SocketServerService.stop(applicationContext)
        }
    }

    private fun updateTileState(status: ConnectionStatus) {
        val tile = qsTile ?: return

        when (status) {
            ConnectionStatus.AUTHORIZED -> {
                tile.state = Tile.STATE_ACTIVE
                tile.label = getString(R.string.tile_name)
                tile.icon = Icon.createWithResource(this, R.drawable.ic_mirror_tile)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    val client = SocketEventBus.connectedClientIp.value ?: "Connected"
                    tile.subtitle = client
                }
            }
            ConnectionStatus.LISTENING, ConnectionStatus.CONNECTED -> {
                tile.state = Tile.STATE_ACTIVE
                tile.label = getString(R.string.tile_name)
                tile.icon = Icon.createWithResource(this, R.drawable.ic_mirror_tile)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    tile.subtitle = getString(R.string.tile_active_subtitle)
                }
            }
            ConnectionStatus.STOPPED, ConnectionStatus.ERROR -> {
                tile.state = Tile.STATE_INACTIVE
                tile.label = getString(R.string.tile_name)
                tile.icon = Icon.createWithResource(this, R.drawable.ic_mirror_tile)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    tile.subtitle = getString(R.string.tile_inactive_subtitle)
                }
            }
        }
        tile.updateTile()
    }
}
