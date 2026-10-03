package net.teamceleste.mayhemkart

import android.app.Activity
import android.app.AlertDialog
import android.graphics.Color
import android.graphics.Typeface
import android.net.nsd.NsdServiceInfo
import android.os.Bundle
import android.view.View
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView

class MainActivity : Activity() {
    private lateinit var discovery: MayhemDiscovery
    private lateinit var peersContainer: LinearLayout
    private lateinit var statusText: TextView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        discovery = MayhemDiscovery(this).apply {
            onPeerFound = { peer -> runOnUiThread { addPeer(peer) } }
            onPeerLost = { name -> runOnUiThread { removePeer(name) } }
            onPeerRequest = { deviceName, reply ->
                runOnUiThread {
                    AlertDialog.Builder(this@MainActivity)
                        .setTitle("Allow Device to Join Your Game?")
                        .setMessage("Device Name: " + deviceName)
                        .setPositiveButton("Yes") { _, _ -> reply(true) }
                        .setNegativeButton("No") { _, _ -> reply(false) }
                        .show()
                }
            }
            onPeerConnected = { runOnUiThread { statusText.text = "Connected." } }
            onPeerRejected = { reason -> runOnUiThread { statusText.text = reason } }
        }

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(56, 32, 56, 24)
            setBackgroundColor(Color.rgb(12, 12, 12))
        }

        val title = TextView(this).apply {
            text = "MAYHEM KART"
            textSize = 38f
            setTextColor(Color.WHITE)
            setTypeface(Typeface.DEFAULT, Typeface.BOLD)
        }
        root.addView(title)

        listOf("Play", "Online Play", "Settings").forEach { label ->
            val button = TextView(this).apply {
                text = label
                textSize = 20f
                setTextColor(Color.WHITE)
                isClickable = true
                isFocusable = true
            }
            root.addView(button, LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ))
        }

        val nearby = TextView(this).apply {
            text = "Nearby Players"
            textSize = 18f
            setTextColor(Color.WHITE)
            visibility = View.VISIBLE
        }
        root.addView(nearby)

        peersContainer = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
        }
        root.addView(peersContainer)

        statusText = TextView(this).apply {
            textSize = 12f
            setTextColor(Color.rgb(150, 150, 150))
        }
        root.addView(statusText)

        val footer = TextView(this).apply {
            text = "Version 26.0 Developer Build\nUnauthorized distribution or disclosure is prohibited.\n© 2026 Team Celeste™. All rights reserved."
            textSize = 11f
            setTextColor(Color.rgb(150, 150, 150))
        }
        root.addView(footer)

        setContentView(root)
        discovery.start()
    }

    private fun addPeer(peer: NsdServiceInfo) {
        if ((0 until peersContainer.childCount).any {
                peersContainer.getChildAt(it).tag == peer.serviceName
            }) return

        val button = Button(this).apply {
            text = peer.serviceName
            tag = peer.serviceName
            setOnClickListener {
                statusText.text = "Connecting to ${peer.serviceName}…"
                discovery.connectTo(peer)
            }
        }
        peersContainer.addView(button)
    }

    private fun removePeer(name: String) {
        for (index in peersContainer.childCount - 1 downTo 0) {
            if (peersContainer.getChildAt(index).tag == name) {
                peersContainer.removeViewAt(index)
            }
        }
    }

    override fun onDestroy() {
        discovery.stop()
        super.onDestroy()
    }
}
