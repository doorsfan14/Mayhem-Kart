package net.teamceleste.mayhemkart

import android.app.Activity
import android.graphics.Color
import android.graphics.Typeface
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.widget.LinearLayout
import android.widget.TextView

class MainActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(56, 32, 56, 24)
            setBackgroundColor(Color.rgb(12, 12, 12))
        }

        val title = TextView(this).apply {
            text = "MAYHEM KART"
            textSize = 38f
            setTextColor(Color.WHITE)
            setTypeface(Typeface.DEFAULT, Typeface.BOLD)
            letterSpacing = 0.08f
        }
        root.addView(title, LinearLayout.LayoutParams(320, LinearLayout.LayoutParams.WRAP_CONTENT))

        listOf("Play", "Online Play", "Settings").forEach { label ->
            val button = TextView(this).apply {
                text = label
                textSize = 20f
                setTextColor(Color.WHITE)
                gravity = Gravity.CENTER_VERTICAL
                setPadding(18, 0, 18, 0)
                setBackgroundColor(Color.rgb(30, 30, 30))
                isClickable = true
                isFocusable = true
            }
            val lp = LinearLayout.LayoutParams(320, 64)
            lp.topMargin = 12
            root.addView(button, lp)
        }

        val footer = TextView(this).apply {
            text = "Version 26.0 Developer Build\nUnauthorized distribution or disclosure is prohibited.\n© 2026 Team Celeste™. All rights reserved."
            textSize = 11f
            setTextColor(Color.rgb(150, 150, 150))
            gravity = Gravity.END
        }
        root.addView(footer, LinearLayout.LayoutParams(-1, 70).apply {
            gravity = Gravity.BOTTOM
            topMargin = 12
        })

        setContentView(root)
    }
}
