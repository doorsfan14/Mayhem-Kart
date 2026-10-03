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

    fun connect(host: String, port: Int) {
        disconnect()

        executor.execute {
            try {
                val socket = Socket()
                socket.connect(InetSocketAddress(host, port), 3000)
                this.socket = socket

                val writer = OutputStreamWriter(socket.getOutputStream(), Charsets.UTF_8)
                val reader = BufferedReader(InputStreamReader(socket.getInputStream(), Charsets.UTF_8))

                writer.write("MAYHEM\tHELLO\t$PROTOCOL_VERSION\t$ENGINE_VERSION\n")
                writer.flush()

                val response = reader.readLine()
                    ?: throw IllegalStateException("Peer closed the connection during handshake.")

                val parts = response.split("\t")
                if (parts.size != 4 || parts[0] != "MAYHEM" || parts[1] != "HELLO") {
                    onRejected?.invoke("Invalid Mayhem Kart handshake.")
                    disconnect()
                    return@execute
                }

                val protocolVersion = parts[2].toIntOrNull()
                if (protocolVersion != PROTOCOL_VERSION) {
                    onRejected?.invoke("Incompatible protocol version.")
                    disconnect()
                    return@execute
                }

                onConnected?.invoke()
            } catch (error: Exception) {
                onDisconnected?.invoke(error)
            }
        }
    }

    fun disconnect() {
        runCatching { socket?.close() }
        socket = null
    }
}
