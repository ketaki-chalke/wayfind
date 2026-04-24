package com.example.wayfind

import android.Manifest
import android.app.Activity
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.content.pm.PackageManager
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
import android.os.Bundle
import android.os.IBinder
import android.speech.RecognizerIntent
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.content.getSystemService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*
import org.json.JSONObject
import java.io.File
import java.util.Locale

/**
 * WayFind + FINGER — Merged MainActivity
 *
 * Nav channel  "com.example.wayfind/nav":
 *   Flutter→Kotlin : startCompass, stopCompass, saveMap(json), loadMap,
 *                    startSpeechInput(prompt)
 *   Kotlin→Flutter : onCompassUpdate(Double), onSpeechResult(String)
 *
 * BLE channel  "com.example.wayfind/ble":
 *   Flutter→Kotlin : startScanning, stopScanning, checkPermissions,
 *                    requestPermissions, getLogPath, clearLogs,
 *                    startSurvey(zoneName), stopSurvey, cancelSurvey,
 *                    getSurveyedZones, deleteZone(zoneName), clearSurveys,
 *                    setNavConstraint(currentZone, nextZone), clearNavConstraint
 *   Kotlin→Flutter : onZoneData(jsonString), onSurveyTick(Int),
 *                    onPermissionResult(Boolean)
 */
class MainActivity : FlutterActivity(), SensorEventListener {

    companion object {
        private const val TAG = "MainActivity"

        // ── MethodChannel names ──────────────────────────────────────────────
        private const val NAV_CHANNEL  = "com.example.wayfind/nav"
        private const val BLE_CHANNEL  = "com.example.wayfind/ble"

        // ── File keys ────────────────────────────────────────────────────────
        private const val MAP_FILE = "wayfind_map.json"

        // ── Constants ────────────────────────────────────────────────────────
        private const val COMPASS_INTERVAL_MS  = 3000L
        private const val SPEECH_REQUEST_CODE  = 100
        private const val PERMISSION_REQUEST_CODE = 1001
    }

    // ── MethodChannels ────────────────────────────────────────────────────────
    private var navChannel: MethodChannel? = null
    private var bleChannel: MethodChannel? = null

    // ── Compass sensors ───────────────────────────────────────────────────────
    private lateinit var sensorManager: SensorManager
    private var accelerometerSensor: Sensor? = null
    private var magnetometerSensor: Sensor?  = null
    private val gravity     = FloatArray(3)
    private val geomagnetic = FloatArray(3)
    private var hasGravity  = false
    private var hasGeomag   = false
    private var compassRunning    = false
    private var lastCompassSendMs = 0L

    // ── BLE service ───────────────────────────────────────────────────────────
    private var bleService: BleBeaconService? = null
    private var serviceBound = false
    private lateinit var loggingManager: LoggingManager
    private lateinit var surveyManager: SurveyManager

    // ── Coroutine scope ───────────────────────────────────────────────────────
    private val mainScope = CoroutineScope(Dispatchers.Main + SupervisorJob())
    // Add this line
    private var pendingNavConstraint: Pair<String, String>? = null
    // ═════════════════════════════════════════════════════════════════════════
    // BLE service connection
    // ═════════════════════════════════════════════════════════════════════════

    private val serviceConnection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, service: IBinder?) {
            val binder = service as BleBeaconService.LocalBinder
            bleService = binder.getService()
            serviceBound = true

            bleService?.surveyManager = surveyManager

            pendingNavConstraint?.let {
                bleService?.setNavigationConstraint(it.first, it.second)
                pendingNavConstraint = null
                Log.d(TAG, "Applied pending nav constraint: ${it.first} → ${it.second}")
            }
            reloadFingerprints()

            bleService?.onZoneDetected = { zoneResult ->
                handleZoneResult(zoneResult)
            }
            bleService?.onSurveyTick = { sampleCount ->
                mainScope.launch(Dispatchers.Main) {
                    bleChannel?.invokeMethod("onSurveyTick", sampleCount)
                }
            }
            Log.d(TAG, "BLE service connected")
        }

        override fun onServiceDisconnected(name: ComponentName?) {
            bleService = null
            serviceBound = false
            Log.d(TAG, "BLE service disconnected")
        }
    }

    // ═════════════════════════════════════════════════════════════════════════
    // Flutter engine setup — registers both MethodChannels
    // ═════════════════════════════════════════════════════════════════════════

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Sensors
        sensorManager       = getSystemService()!!
        accelerometerSensor = sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
        magnetometerSensor  = sensorManager.getDefaultSensor(Sensor.TYPE_MAGNETIC_FIELD)

        // Managers
        loggingManager = LoggingManager(this)
        surveyManager  = SurveyManager(this)

        // ── Nav channel ──────────────────────────────────────────────────────
        navChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NAV_CHANNEL)
        navChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "startCompass" -> { startCompass(); result.success(true) }
                "stopCompass"  -> { stopCompass();  result.success(true) }

                "saveMap" -> {
                    val json = call.arguments as? String ?: ""
                    saveMapToFile(json)
                    result.success(true)
                }
                "loadMap" -> result.success(loadMapFromFile())

                "startSpeechInput" -> {
                    val prompt = call.arguments as? String ?: "Speak now"
                    val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                        putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                            RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                        putExtra(RecognizerIntent.EXTRA_LANGUAGE, Locale.getDefault())
                        putExtra(RecognizerIntent.EXTRA_PROMPT, prompt)
                        putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 3)
                    }
                    try {
                        startActivityForResult(intent, SPEECH_REQUEST_CODE)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SPEECH_UNAVAILABLE",
                            "Google Speech not available: ${e.message}", null)
                    }
                }

                else -> result.notImplemented()
            }
        }

        // ── BLE channel ──────────────────────────────────────────────────────
        bleChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BLE_CHANNEL)
        bleChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "startScanning" -> {
                    if (checkPermissions()) {
                        startBleService()
                        result.success(true)
                    } else {
                        requestPermissions()
                        result.error("PERMISSION_DENIED",
                            "Bluetooth permissions not granted", null)
                    }
                }
                "stopScanning"       -> { stopBleService(); result.success(true) }
                "checkPermissions"   -> result.success(checkPermissions())
                "requestPermissions" -> { requestPermissions(); result.success(null) }
                "getLogPath"         -> result.success(loggingManager.getLogFilePath())
                "clearLogs"          -> result.success(loggingManager.clearLogs())

                "startSurvey" -> {
                    val zoneName = call.argument<String>("zoneName") ?: ""
                    if (zoneName.isBlank()) {
                        result.error("INVALID_NAME", "Zone name cannot be empty", null)
                    } else {
                        bleService?.surveyMode = true
                        surveyManager.startSurvey(zoneName)
                        result.success(true)
                    }
                }
                "stopSurvey" -> {
                    bleService?.surveyMode = false
                    val sampleCount = surveyManager.sampleCount()
                    val surveyResult = surveyManager.stopSurvey()
                    if (surveyResult != null) {
                        loggingManager.logSurveyFingerprint(
                            fingerprint = surveyResult.fingerprint,
                            sampleCount = sampleCount,
                            rawSamples  = surveyResult.rawSamples
                        )
                    }
                    reloadFingerprints()
                    result.success(surveyResult?.fingerprint?.zoneName)
                }
                "cancelSurvey" -> {
                    bleService?.surveyMode = false
                    surveyManager.cancelSurvey()
                    result.success(null)
                }
                "getSurveyedZones" -> {
                    val zones = surveyManager.loadPersistedFingerprints()
                        .map { it.zoneName }
                    result.success(zones)
                }
                "deleteZone" -> {
                    val zoneName = call.argument<String>("zoneName") ?: ""
                    result.success(surveyManager.deleteFingerprint(zoneName))
                }
                "clearSurveys" -> result.success(surveyManager.clearAllPersisted())

                "setNavConstraint" -> {
                    val currentZone = call.argument<String>("currentZone") ?: ""
                    val nextZone    = call.argument<String>("nextZone")    ?: ""
                    if (currentZone.isBlank() || nextZone.isBlank()) {
                        result.error("INVALID_ARGS", "currentZone and nextZone must not be empty", null)
                    } else {
                        if (bleService != null) {
                            bleService?.setNavigationConstraint(currentZone, nextZone)
                        } else {
                            // Service not bound yet — store it, will be applied in onServiceConnected
                            pendingNavConstraint = Pair(currentZone, nextZone)
                            Log.d(TAG, "Service not bound yet, queuing constraint: $currentZone → $nextZone")
                        }
                        result.success(true)
                    }
                }
                "clearNavConstraint" -> {
                    pendingNavConstraint = null
                    bleService?.clearNavigationConstraint()
                    result.success(true)
                }

                else -> result.notImplemented()
            }
        }
    }

    // ═════════════════════════════════════════════════════════════════════════
    // Speech result
    // ═════════════════════════════════════════════════════════════════════════

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != SPEECH_REQUEST_CODE) return

        val spokenText = if (resultCode == Activity.RESULT_OK) {
            data?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)
                ?.firstOrNull() ?: ""
        } else ""

        mainScope.launch {
            navChannel?.invokeMethod("onSpeechResult", spokenText)
        }
    }

    // ═════════════════════════════════════════════════════════════════════════
    // Compass
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
        if (!SensorManager.getRotationMatrix(rotationMatrix, inclinationMatrix,
                gravity, geomagnetic)) return

        val orientation = FloatArray(3)
        SensorManager.getOrientation(rotationMatrix, orientation)
        val heading = (Math.toDegrees(orientation[0].toDouble()) + 360) % 360

        mainScope.launch {
            navChannel?.invokeMethod("onCompassUpdate", heading)
        }
    }

    override fun onAccuracyChanged(sensor: Sensor, accuracy: Int) {}

    // ═════════════════════════════════════════════════════════════════════════
    // Map storage
    // ═════════════════════════════════════════════════════════════════════════

    private fun mapFile() = File(filesDir, MAP_FILE)

    private fun saveMapToFile(json: String) {
        try { mapFile().writeText(json, Charsets.UTF_8) } catch (e: Exception) { e.printStackTrace() }
    }

    private fun loadMapFromFile(): String {
        return try {
            val f = mapFile()
            if (f.exists()) f.readText(Charsets.UTF_8) else ""
        } catch (e: Exception) { "" }
    }

    // ═════════════════════════════════════════════════════════════════════════
    // BLE service management
    // ═════════════════════════════════════════════════════════════════════════

    private fun startBleService() {
        val intent = Intent(this, BleBeaconService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
        bindService(intent, serviceConnection, Context.BIND_AUTO_CREATE)
        Log.d(TAG, "BLE service started")
    }

    private fun stopBleService() {
        if (serviceBound) {
            unbindService(serviceConnection)
            serviceBound = false
        }
        stopService(Intent(this, BleBeaconService::class.java))
        Log.d(TAG, "BLE service stopped")
    }

    // ═════════════════════════════════════════════════════════════════════════
    // Zone result handling
    // ═════════════════════════════════════════════════════════════════════════

    private fun handleZoneResult(zoneResult: BleBeaconService.ZoneResult) {
        mainScope.launch(Dispatchers.Default) {
            val startTime = System.currentTimeMillis()
            try {
                loggingManager.logPrediction(
                    scanVector       = zoneResult.scanVector,
                    predictedZone    = zoneResult.zoneName,
                    processingTimeMs = (System.currentTimeMillis() - startTime).toDouble()
                )

                val json = JSONObject().apply {
                    put("zone",         zoneResult.zoneName)
                    put("beacon_count", zoneResult.beaconCount)
                    put("timestamp",    zoneResult.timestamp)
                    val vectorJson = JSONObject()
                    zoneResult.scanVector.forEach { (id, rssi) -> vectorJson.put(id, rssi) }
                    put("scan_vector", vectorJson)
                    val namesJson = JSONObject()
                    FingerprintDatabase.beaconNames.forEach { (id, name) -> namesJson.put(id, name) }
                    put("beacon_names", namesJson)
                }

                withContext(Dispatchers.Main) {
                    // Forward on BOTH channels so NavigationScreen can receive it
                    navChannel?.invokeMethod("onZoneData", json.toString())
                    bleChannel?.invokeMethod("onZoneData", json.toString())
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error handling zone result: ${e.message}", e)
                loggingManager.logError(
                    errorMessage     = e.message ?: "Unknown error",
                    processingTimeMs = (System.currentTimeMillis() - startTime).toDouble()
                )
            }
        }
    }

    private fun reloadFingerprints() {
        val merged = surveyManager.loadMergedFingerprints()
        bleService?.reloadMatcher(merged)
        Log.d(TAG, "Reloaded ${merged.size} fingerprints")
    }

    // ═════════════════════════════════════════════════════════════════════════
    // Permissions
    // ═════════════════════════════════════════════════════════════════════════

    private fun checkPermissions(): Boolean =
        requiredPermissions().all {
            ContextCompat.checkSelfPermission(this, it) == PackageManager.PERMISSION_GRANTED
        }

    private fun requestPermissions() {
        ActivityCompat.requestPermissions(
            this, requiredPermissions().toTypedArray(), PERMISSION_REQUEST_CODE
        )
    }

    private fun requiredPermissions(): List<String> =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            listOf(
                Manifest.permission.BLUETOOTH_SCAN,
                Manifest.permission.BLUETOOTH_CONNECT,
                Manifest.permission.ACCESS_FINE_LOCATION
            )
        } else {
            listOf(
                Manifest.permission.BLUETOOTH,
                Manifest.permission.BLUETOOTH_ADMIN,
                Manifest.permission.ACCESS_FINE_LOCATION
            )
        }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == PERMISSION_REQUEST_CODE) {
            val allGranted = grantResults.all { it == PackageManager.PERMISSION_GRANTED }
            bleChannel?.invokeMethod("onPermissionResult", allGranted)
        }
    }

    // ═════════════════════════════════════════════════════════════════════════
    // Lifecycle
    // ═════════════════════════════════════════════════════════════════════════

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (!checkPermissions()) requestPermissions()
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
        stopBleService()
        mainScope.cancel()
    }
}
