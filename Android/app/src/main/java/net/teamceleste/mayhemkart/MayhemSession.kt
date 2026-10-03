package net.teamceleste.mayhemkart

import java.io.DataInputStream
import java.io.DataOutputStream
import java.net.InetSocketAddress
import java.net.Socket
import java.util.concurrent.Executors

class MayhemSession {
    private val executor = Executors.newSingleThreadExecutor()
    private var socket: Socket? = null
    private var initiatedConnection = false
    private var receivedHello = false
    private var connected = false

    var onConnected: (() -> Unit)? = null
    var onDisconnected: ((Exception?) -> Unit)? = null
    var onRejected: ((String) -> Unit)? = null
    var onPeerRequest: ((String, (Boolean) -> Unit) -> Unit)? = null

    fun connect(host: String, port: Int) {
        disconnect()
        initiatedConnection = true
        executor.execute {
            try {
                val next = Socket()
                next.connect(InetSocketAddress(host, port), 3000)
                runHandshake(next)
            } catch (error: Exception) {
                onDisconnected?.invoke(error)
            }
        }
    }

    fun accept(accepted: Socket) {
        disconnect()
        initiatedConnection = false
        executor.execute { runHandshake(accepted) }
    }

    private fun runHandshake(next: Socket) {
        try {
            socket = next
            next.tcpNoDelay = true
            val output = DataOutputStream(next.getOutputStream())
            val input = DataInputStream(next.getInputStream())

            val name = android.os.Build.MODEL
                .replace("\t", " ")
                .replace("\n", " ")
                .replace("\r", " ")

            MayhemProtocol.write(
                output,
                MayhemPacket.Hello(
                    MayhemProtocol.PROTOCOL_VERSION,
                    MayhemProtocol.ENGINE_VERSION,
                    name
                )
            )

            while (socket != null) {
                when (val packet = MayhemProtocol.read(input)) {
                    is MayhemPacket.Hello -> {
                        if (packet.version != MayhemProtocol.PROTOCOL_VERSION ||
                            packet.engine != MayhemProtocol.ENGINE_VERSION ||
                            receivedHello
                        ) {
                            reject("Incompatible Mayhem Kart version.")
                            return
                        }
                        receivedHello = true
                        if (initiatedConnection) continue

                        onPeerRequest?.invoke(packet.deviceName) { allowed ->
                            if (allowed) {
                                runCatching {
                                    MayhemProtocol.write(output, MayhemPacket.Accept)
                                    markConnected()
                                }.onFailure { onDisconnected?.invoke(it as? Exception) }
                            } else {
                                runCatching {
                                    MayhemProtocol.write(
                                        output,
                                        MayhemPacket.Reject("The host declined the connection.")
                                    )
                                }
                                disconnect()
                            }
                        }
                        return
                    }

                    MayhemPacket.Accept -> {
                        if (initiatedConnection) markConnected()
                        return
                    }

                    is MayhemPacket.Reject -> {
                        onRejected?.invoke(packet.reason)
                        disconnect()
                        return
                    }
                }
            }
        } catch (error: Exception) {
            if (socket != null) onDisconnected?.invoke(error)
        }
    }

    private fun markConnected() {
        if (connected) return
        connected = true
        onConnected?.invoke()
    }

    private fun reject(reason: String) {
        onRejected?.invoke(reason)
        disconnect()
    }

    fun disconnect() {
        runCatching { socket?.close() }
        socket = null
        receivedHello = false
        connected = false
    }
}
