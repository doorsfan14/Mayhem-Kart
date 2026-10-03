package net.teamceleste.mayhemkart

import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.net.InetSocketAddress
import java.net.Socket
import java.util.concurrent.Executors

class MayhemSession {
    companion object {
        const val PROTOCOL_VERSION = 1
        const val ENGINE_VERSION = "26.0"
    }
    private val executor = Executors.newSingleThreadExecutor()
    private var socket: Socket? = null
    var onConnected: (() -> Unit)? = null
    var onDisconnected: ((Exception?) -> Unit)? = null
    var onRejected: ((String) -> Unit)? = null
    var onPeerRequest: ((String, (Boolean) -> Unit) -> Unit)? = null

    fun connect(host: String, port: Int) {
        disconnect()
        executor.execute {
            try {
                val socket = Socket()
                socket.connect(InetSocketAddress(host, port), 3000)
                runHandshake(socket)
            } catch (error: Exception) {
                onDisconnected?.invoke(error)
            }
        }
    }

    fun accept(accepted: Socket) {
        disconnect()
        executor.execute { runHandshake(accepted) }
    }

    private fun runHandshake(socket: Socket) {
        try {
            this.socket = socket
            val writer = OutputStreamWriter(socket.getOutputStream(), Charsets.UTF_8)
            val reader = BufferedReader(InputStreamReader(socket.getInputStream(), Charsets.UTF_8))
            val name = android.os.Build.MODEL.replace("\t", " ").replace("\n", " ")
            writer.write("MAYHEM\tHELLO\t$PROTOCOL_VERSION\t$ENGINE_VERSION\t$name\n")
            writer.flush()

            val response = reader.readLine() ?: throw IllegalStateException("Peer closed the connection during handshake.")
            val parts = response.split("\t")
            if (parts.size < 2 || parts[0] != "MAYHEM") {
                onRejected?.invoke("Invalid Mayhem Kart message.")
                disconnect()
                return
            }
            when (parts[1]) {
                "HELLO" -> {
                    if (parts.size != 5 || parts[2].toIntOrNull() != PROTOCOL_VERSION) {
                        onRejected?.invoke("Incompatible protocol version.")
                        disconnect()
                        return
                    }
                    val deviceName = parts[4].ifEmpty { "Unknown Device" }
                    onPeerRequest?.invoke(deviceName) { allowed ->
                        val command = if (allowed) "ACCEPT" else "REJECT"
                        writer.write("MAYHEM\t" + command + "\n")
                        writer.flush()
                        if (allowed) onConnected?.invoke() else disconnect()
                    }
                }
                "ACCEPT" -> onConnected?.invoke()
                "REJECT" -> {
                    onRejected?.invoke("The host declined the connection.")
                    disconnect()
                }
                else -> {
                    onRejected?.invoke("Invalid Mayhem Kart message.")
                    disconnect()
                }
            }
        } catch (error: Exception) {
            onDisconnected?.invoke(error)
        }
    }

    fun disconnect() {
        runCatching { socket?.close() }
        socket = null
    }
}