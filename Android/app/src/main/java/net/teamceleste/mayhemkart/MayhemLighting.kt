package net.teamceleste.mayhemkart

import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt

data class MayhemTimeOfDay(var hour: Float = 12f) {
    init {
        hour = ((hour % 24f) + 24f) % 24f
    }

    val normalized: Float
        get() = hour / 24f

    val daylight: Float
        get() {
            val sun = sin(((hour - 6f) / 24f) * 2f * PI).toFloat()
            return min(1f, max(0f, sun * 0.5f + 0.5f))
        }

    val skyBrightness: Float
        get() = 0.08f + daylight * 0.92f

    val cloudShadowStrength: Float
        get() = 0.18f + daylight * 0.30f

    fun sunDirection(): FloatArray {
        val angle = ((hour - 6f) / 24f) * 2f * PI
        val x = cos(angle).toFloat() * 0.65f
        val y = max(sin(angle).toFloat(), -0.15f)
        val z = 0.45f
        val length = sqrt(x * x + y * y + z * z)
        return floatArrayOf(x / length, y / length, z / length)
    }
}

/**
 * Renderer-facing lighting state.
 *
 * Vulkan shaders can consume these values directly as uniforms/push constants.
 * A track only needs to set lighting.timeOfDay.hour; the renderer derives
 * sun direction, daylight and cloud-shadow strength from it.
 */
class MayhemLighting {
    var timeOfDay = MayhemTimeOfDay()

    val sunDirection: FloatArray
        get() = timeOfDay.sunDirection()

    val daylight: Float
        get() = timeOfDay.daylight

    val skyBrightness: Float
        get() = timeOfDay.skyBrightness

    val cloudShadowStrength: Float
        get() = timeOfDay.cloudShadowStrength
}
