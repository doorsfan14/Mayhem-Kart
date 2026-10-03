package net.teamceleste.mayhemkart

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import java.net.ServerSocket
import java.util.concurrent.atomic.AtomicBoolean

class MayhemDiscovery(context: Context) {
    companion object {
        const val SERVICE_TYPE = "_mayhemkart._tcp"
        const val SERVICE_NAME_PREFIX = "Mayhem Kart"
    }

    private val nsd = context.applicationContext.getSystemService(Context.NSD_SERVICE) as NsdManager
    private var registration: NsdManager.RegistrationListener? = null
    private var discovery: NsdManager.DiscoveryListener? = null
    private var serverSocket: ServerSocket? = null
    private var session: MayhemSession? = null
    private val running = AtomicBoolean(false)

    var onPeerFound: ((NsdServiceInfo) -> Unit)? = null
    var onPeerLost: ((String) -> Unit)? = null
    var onPeerConnected: (() -> Unit)? = null
    var onPeerRejected: ((String) -> Unit)? = null

    fun start() {
        if (!running.compareAndSet(false, true)) return

        serverSocket = ServerSocket(0)

        Thread {
            while (running.get()) {
                try {
                    val accepted = serverSocket?.accept() ?: break
                    beginSession(accepted)
                } catch (_: Exception) {
                    if (running.get()) continue
                    break
                }
            }
        }.start()

        val serviceInfo = NsdServiceInfo().apply {
            serviceName = "$SERVICE_NAME_PREFIX Android"
            serviceType = SERVICE_TYPE
            port = serverSocket!!.localPort
        }

        registration = object : NsdManager.RegistrationListener {
            override fun onServiceRegistered(info: NsdServiceInfo) = Unit
            override fun onRegistrationFailed(info: NsdServiceInfo, errorCode: Int) = stop()
            override fun onServiceUnregistered(info: NsdServiceInfo) = Unit
            override fun onUnregistrationFailed(info: NsdServiceInfo, errorCode: Int) = Unit
        }

        discovery = object : NsdManager.DiscoveryListener {
            override fun onDiscoveryStarted(serviceType: String) = Unit
            override fun onDiscoveryStopped(serviceType: String) = Unit

            override fun onServiceFound(info: NsdServiceInfo) {
                if (info.serviceName == serviceInfo.serviceName) return

                nsd.resolveService(info, object : NsdManager.ResolveListener {
                    override fun onServiceResolved(resolved: NsdServiceInfo) {
                        onPeerFound?.invoke(resolved)
                        if (session == null) {
                            beginSession(resolved.host.hostAddress, resolved.port)
                        }
                    }

                    override fun onResolveFailed(info: NsdServiceInfo, errorCode: Int) = Unit
                })
            }

            override fun onServiceLost(info: NsdServiceInfo) {
                onPeerLost?.invoke(info.serviceName)
            }

            override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) {
                stop()
            }

            override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) = Unit
        }

        nsd.registerService(serviceInfo, NsdManager.PROTOCOL_DNS_SD, registration)
        nsd.discoverServices(SERVICE_TYPE, NsdManager.PROTOCOL_DNS_SD, discovery)
    }

    private fun beginSession(host: String, port: Int) {
        if (session != null) return

        val next = MayhemSession()
        next.onConnected = { onPeerConnected?.invoke() }
        next.onRejected = {
            onPeerRejected?.invoke(it)
            next.disconnect()
            session = null
        }
        next.onDisconnected = {
            session = null
        }

        session = next
        next.connect(host, port)
    }

    private fun beginSession(socket: java.net.Socket) {
        if (session != null) {
            runCatching { socket.close() }
            return
        }

        val next = MayhemSession()
        next.onConnected = { onPeerConnected?.invoke() }
        next.onRejected = {
            onPeerRejected?.invoke(it)
            next.disconnect()
            session = null
        }
        next.onDisconnected = {
            session = null
        }

        session = next
        next.accept(socket)
    }

    fun stop() {
        if (!running.compareAndSet(true, false)) return

        session?.disconnect()
        session = null

        registration?.let { runCatching { nsd.unregisterService(it) } }
        discovery?.let { runCatching { nsd.stopServiceDiscovery(it) } }

        registration = null
        discovery = null

        runCatching { serverSocket?.close() }
        serverSocket = null
    }
}
