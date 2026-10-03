package net.teamceleste.mayhemkart

import java.io.DataInputStream
import java.io.DataOutputStream

sealed class MayhemPacket {
    data class Hello(val version: Int, val engine: String, val deviceName: String) : MayhemPacket()
    data object Accept : MayhemPacket()
    data class Reject(val reason: String) : MayhemPacket()
}

object MayhemProtocol {
    const val PROTOCOL_VERSION = 2
    const val ENGINE_VERSION = "26.0"
    private const val MAX_PACKET_SIZE = 1024 * 1024

    fun write(output: DataOutputStream, packet: MayhemPacket) {
        val payload = when (packet) {
            is MayhemPacket.Hello -> "MAYHEM\tHELLO\t${packet.version}\t${sanitize(packet.engine)}\t${sanitize(packet.deviceName)}\n"
            MayhemPacket.Accept -> "MAYHEM\tACCEPT\n"
            is MayhemPacket.Reject -> "MAYHEM\tREJECT\t${sanitize(packet.reason)}\n"
        }.toByteArray(Charsets.UTF_8)
        require(payload.size <= MAX_PACKET_SIZE)
        output.writeInt(payload.size)
        output.write(payload)
        output.flush()
    }

    fun read(input: DataInputStream): MayhemPacket {
        val size = input.readInt()
        require(size in 1..MAX_PACKET_SIZE)
        val payload = ByteArray(size)
        input.readFully(payload)
        val parts = String(payload, Charsets.UTF_8).trimEnd('\n', '\r').split("\t")
        require(parts.size >= 2 && parts[0] == "MAYHEM")
        return when (parts[1]) {
            "HELLO" -> {
                require(parts.size == 5)
                val version = parts[2].toIntOrNull() ?: error("Invalid protocol version")
                require(version == PROTOCOL_VERSION)
                MayhemPacket.Hello(version, parts[3], parts[4].ifEmpty { "Unknown Device" })
            }
            "ACCEPT" -> MayhemPacket.Accept
            "REJECT" -> MayhemPacket.Reject(parts.getOrNull(2) ?: "Connection rejected.")
            else -> error("Unknown Mayhem Kart packet")
        }
    }

    private fun sanitize(value: String): String =
        value.replace("\t", " ").replace("\n", " ").replace("\r", " ")
}
