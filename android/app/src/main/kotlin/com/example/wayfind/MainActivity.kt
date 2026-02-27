package com.example.wayfind

import android.app.Activity
import android.content.Intent
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Bundle
import android.speech.RecognizerIntent
import androidx.core.content.getSystemService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*
import java.io.File
import java.util.Locale

/**
 * WayFind — Navigation MainActivity
 *
 * MethodChannel: "com.example.wayfind/nav"
 *
 * Flutter → Kotlin calls:
 *   startCompass                    — begin streaming compass headings every ~3 seconds
 *   stopCompass                     — stop compass stream
 *   saveMap(String jsonData)        — persist the floor map to internal storage
 *   loadMap()                       — return persisted floor map JSON string
 *   startSpeechInput(String prompt) — open Android native speech dialog
 *
 * Kotlin → Flutter callbacks:
 *   onCompassUpdate(Double)  — compass heading in degrees (0–360, 0 = north)
 *   onSpeechResult(String)   — recognised speech text (empty string if cancelled)
 */
class MainActivity : FlutterActivity(), SensorEventListener {

    companion object {
        private const val CHANNEL             = "com.example.wayfind/nav"
        private const val MAP_FILE            = "wayfind_map.json"
        private const val COMPASS_INTERVAL_MS = 3000L
        private const val SPEECH_REQUEST_CODE = 100
    }

    private var methodChannel: MethodChannel? = null

    // ── Sensors ───────────────────────────────────────────────────────────────
    private lateinit var sensorManager: SensorManager
    private var accelerometerSensor: Sensor? = null
    private var magnetometerSensor: Sensor?  = null

    private val gravity     = FloatArray(3)
    private val geomagnetic = FloatArray(3)
    private var hasGravity  = false
    private var hasGeomag   = false

    private var compassRunning    = false
    private var lastCompassSendMs = 0L

    // ── Coroutine scope ───────────────────────────────────────────────────────
    private val mainScope = CoroutineScope(Dispatchers.Main + SupervisorJob())

    // ═════════════════════════════════════════════════════════════════════════
    // Flutter engine setup
    // ═════════════════════════════════════════════════════════════════════════

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        sensorManager       = getSystemService()!!
        accelerometerSensor = sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
        magnetometerSensor  = sensorManager.getDefaultSensor(Sensor.TYPE_MAGNETIC_FIELD)

        methodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        )

        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {

                "startCompass" -> {
                    startCompass()
                    result.success(true)
                }

                "stopCompass" -> {
                    stopCompass()
                    result.success(true)
                }

                "saveMap" -> {
                    val json = call.arguments as? String ?: ""
                    saveMapToFile(json)
                    result.success(true)
                }

                "loadMap" -> {
                    result.success(loadMapFromFile())
                }

                // ── Native Android Speech Recognition ─────────────────────
                "startSpeechInput" -> {
                    val prompt = call.arguments as? String ?: "Speak now"
                    val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                        putExtra(
                            RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                            RecognizerIntent.LANGUAGE_MODEL_FREE_FORM
                        )
                        putExtra(RecognizerIntent.EXTRA_LANGUAGE, Locale.getDefault())
                        putExtra(RecognizerIntent.EXTRA_PROMPT, prompt)
                        putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 3)
                    }
                    try {
                        startActivityForResult(intent, SPEECH_REQUEST_CODE)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error(
                            "SPEECH_UNAVAILABLE",
                            "Google Speech not available: ${e.message}",
                            null
                        )
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    // ═════════════════════════════════════════════════════════════════════════
    // Speech result — called when Google speech dialog closes
    // ═════════════════════════════════════════════════════════════════════════

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)

        if (requestCode != SPEECH_REQUEST_CODE) return

        val spokenText = if (resultCode == Activity.RESULT_OK) {
            data
                ?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)
                ?.firstOrNull()
                ?: ""
        } else {
            // User pressed back or speech failed — send empty string
            ""
        }

        mainScope.launch {
            methodChannel?.invokeMethod("onSpeechResult", spokenText)
        }
    }

    // ═════════════════════════════════════════════════════════════════════════
    // Compass (Accelerometer + Magnetometer → Rotation Matrix → Azimuth)
    // ═════════════════════════════════════════════════════════════════════════

    private fun startCompass() {
        if (compassRunning) return
        compassRunning = true
        accelerometerSensor?.let {
            sensorManager.registerListener(this, it, SensorManager.SENSOR_DELAY_UI)
        }
        magnetometerSensor?.let {
            sensorManager.registerListener(this, it, SensorManager.SENSOR_DELAY_UI)
        }
    }

    private fun stopCompass() {
        if (!compassRunning) return
        compassRunning = false
        sensorManager.unregisterListener(this)
    }

    override fun onSensorChanged(event: SensorEvent) {
        when (event.sensor.type) {
            Sensor.TYPE_ACCELEROMETER ->
                System.arraycopy(event.values, 0, gravity, 0, 3).also { hasGravity = true }
            Sensor.TYPE_MAGNETIC_FIELD ->
                System.arraycopy(event.values, 0, geomagnetic, 0, 3).also { hasGeomag = true }
        }

        if (!hasGravity || !hasGeomag) return

        val now = System.currentTimeMillis()
        if (now - lastCompassSendMs < COMPASS_INTERVAL_MS) return
        lastCompassSendMs = now

        val rotationMatrix    = FloatArray(9)
        val inclinationMatrix = FloatArray(9)
        val success = SensorManager.getRotationMatrix(
            rotationMatrix, inclinationMatrix, gravity, geomagnetic
        )
        if (!success) return

        val orientation = FloatArray(3)
        SensorManager.getOrientation(rotationMatrix, orientation)

        val azimuthDeg = Math.toDegrees(orientation[0].toDouble())
        val heading    = (azimuthDeg + 360) % 360

        mainScope.launch {
            methodChannel?.invokeMethod("onCompassUpdate", heading)
        }
    }

    override fun onAccuracyChanged(sensor: Sensor, accuracy: Int) {
        // No action needed
    }

    // ═════════════════════════════════════════════════════════════════════════
    // Persistent map storage  (internal files dir — no permissions needed)
    // ═════════════════════════════════════════════════════════════════════════

    private fun mapFile(): File = File(filesDir, MAP_FILE)

    private fun saveMapToFile(json: String) {
        try {
            mapFile().writeText(json, Charsets.UTF_8)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun loadMapFromFile(): String {
        return try {
            val f = mapFile()
            if (f.exists()) f.readText(Charsets.UTF_8) else ""
        } catch (e: Exception) {
            ""
        }
    }

    // ═════════════════════════════════════════════════════════════════════════
    // Lifecycle
    // ═════════════════════════════════════════════════════════════════════════

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
    }

    override fun onResume() {
        super.onResume()
        if (compassRunning) startCompass()
    }

    override fun onPause() {
        super.onPause()
        sensorManager.unregisterListener(this)
    }

    override fun onDestroy() {
        super.onDestroy()
        stopCompass()
        mainScope.cancel()
    }
}