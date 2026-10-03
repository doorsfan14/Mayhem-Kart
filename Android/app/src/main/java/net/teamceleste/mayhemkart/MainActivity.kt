package net.teamceleste.mayhemkart

import android.app.Activity
import android.app.AlertDialog
import android.graphics.Color
import android.graphics.Typeface
import android.os.Bundle
import android.widget.LinearLayout
import android.widget.TextView

class MainActivity : Activity() {
    private lateinit var discovery: MayhemDiscovery

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        discovery = MayhemDiscovery(this).apply {
            onPeerFound = { peer -> println("Mayhem Kart peer found: " + peer.serviceName) }
            onPeerLost = { name -> println("Mayhem Kart peer lost: " + name) }
            onPeerRequest = { deviceName, reply ->
                runOnUiThread {
                    AlertDialog.Builder(this@MainActivity)
                        .setTitle("Allow Device to Join Your Game")
                        .setMessage("Device Name: " + deviceName)
                        .setPositiveButton("Yes") { _, _ -> reply(true) }
                        .setNegativeButton("No") { _, _ -> reply(false) }
                        .show()
                }
            }
        }
        discovery.start()

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
        val footer = TextView(this).apply {
            text = "Version 26.0 Developer Build\nUnauthorized distribution or disclosure is prohibited.\n© 2026 Team Celeste™. All rights reserved."
            textSize = 11f
            setTextColor(Color.rgb(150, 150, 150))
        }
        root.addView(footer)
        setContentView(root)
    }

    override fun onDestroy() {
        discovery.stop()
        super.onDestroy()
    }
}