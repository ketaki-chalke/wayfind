package com.example.wayfind

import android.annotation.SuppressLint
import android.app.*
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.bluetooth.le.*
import android.content.Context
import android.content.Intent
import android.os.Binder
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import kotlinx.coroutines.*
import java.util.concurrent.ConcurrentHashMap

/**
 * Foreground Service for BLE iBeacon scanning — Fingerprinting edition.
 *
 * Key changes vs. distance-based version:
 *  • RSSI values are kept in a SLIDING WINDOW (not cleared every batch).
 *  • Every SCAN_INTERVAL_MS the median-per-beacon map is fed into KNN matcher.
 *  • Emits a zone name string instead of distances / coordinates.
 */
class BleBeaconService : Service() {

    companion object {
        private const val TAG = "BleBeaconService"
        private const val NOTIFICATION_ID = 1
        private const val CHANNEL_ID = "ble_beacon_channel"

        /** Target iBeacon UUID (without hyphens, lower-case) */
        const val TARGET_UUID = "e2c56db5dffb48d2b060d0f5a71096e0"

        /** How often to run the KNN prediction (ms) */
        private const val SCAN_INTERVAL_MS = 1000L

        /** Sliding window depth per beacon */
        private const val WINDOW_SIZE = 10
    }

    // ── Service plumbing ──────────────────────────────────────────────────────

    private val binder = LocalBinder()
    private var bluetoothAdapter: BluetoothAdapter? = null
    private var bluetoothLeScanner: BluetoothLeScanner? = null
    private val serviceScope = CoroutineScope(Dispatchers.Default + SupervisorJob())

    /** beaconId ("major-minor") → sliding RSSI window */
    private val rssiWindows = ConcurrentHashMap<String, ArrayDeque<Int>>()

    /** KNN matcher — replaced wholesale when new fingerprints are loaded */
    private var matcher = BleFingerprintMatcher(
        fingerprints = FingerprintDatabase.fingerprints,
        k = 3,
        historySize = 5
    )

    /** Replace the matcher with a freshly merged fingerprint list. */
    fun reloadMatcher(fingerprints: List<Fingerprint>) {
        matcher = BleFingerprintMatcher(fingerprints, k = 3, historySize = 5)
        Log.d(TAG, "Matcher reloaded with ${fingerprints.size} fingerprints")
    }

    // ── Callbacks for MainActivity ────────────────────────────────────────────

    /** Invoked on every successful zone prediction (positioning mode) */
    var onZoneDetected: ((ZoneResult) -> Unit)? = null

    /** Invoked on every batch tick during survey mode — passes live sample count */
    var onSurveyTick: ((Int) -> Unit)? = null

    /** When true the service feeds RSSI into SurveyManager instead of KNN */
    var surveyMode: Boolean = false

    /** Injected by MainActivity after service binds */
    var surveyManager: SurveyManager? = null

    /**
     * Navigation constraint — when non-null, KNN is limited to these two zones.
     * First = current zone the user should be at, second = next zone on the path.
     */
    private var navConstraint: Pair<String, String>? = null

    /**
     * Activate constrained matching for a navigation step.
     * Only [currentZone] and [nextZone] fingerprints will be compared.
     */
    fun setNavigationConstraint(currentZone: String, nextZone: String) {
        navConstraint = Pair(currentZone, nextZone)
        Log.d(TAG, "Nav constraint set: $currentZone → $nextZone")
    }

    /** Remove the constraint — used when navigation ends or is cancelled. */
    fun clearNavigationConstraint() {
        navConstraint = null
        Log.d(TAG, "Nav constraint cleared")
    }

    // ── Binder ────────────────────────────────────────────────────────────────

    inner class LocalBinder : Binder() {
        fun getService(): BleBeaconService = this@BleBeaconService
    }

    override fun onBind(intent: Intent?): IBinder = binder

    // ── Lifecycle ─────────────────────────────────────────────────────────────

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "Service created")

        val btManager = getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
        bluetoothAdapter   = btManager.adapter
        bluetoothLeScanner = bluetoothAdapter?.bluetoothLeScanner

        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForeground(NOTIFICATION_ID, createNotification())
        Log.d(TAG, "Service started")
        startScanning()
        return START_STICKY
    }

    override fun onDestroy() {
        super.onDestroy()
        stopScanning()
        serviceScope.cancel()
        Log.d(TAG, "Service destroyed")
    }

    // ── BLE scanning ──────────────────────────────────────────────────────────

    @SuppressLint("MissingPermission")
    private fun startScanning() {
        if (bluetoothLeScanner == null) {
            Log.e(TAG, "BLE Scanner not available")
            return
        }

        val settings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .setReportDelay(0)
            .build()

        try {
            bluetoothLeScanner?.startScan(null, settings, scanCallback)
            Log.d(TAG, "BLE scanning started")
            startBatchProcessor()
        } catch (e: Exception) {
            Log.e(TAG, "Error starting scan: ${e.message}", e)
        }
    }

    @SuppressLint("MissingPermission")
    private fun stopScanning() {
        try {
            bluetoothLeScanner?.stopScan(scanCallback)
            Log.d(TAG, "BLE scanning stopped")
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping scan: ${e.message}", e)
        }
    }

    private val scanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult?) {
            result?.let { processScanResult(it) }
        }
        override fun onBatchScanResults(results: MutableList<ScanResult>?) {
            results?.forEach { processScanResult(it) }
        }
        override fun onScanFailed(errorCode: Int) {
            Log.e(TAG, "Scan failed: $errorCode")
        }
    }

    // ── RSSI window management ────────────────────────────────────────────────

    private fun processScanResult(result: ScanResult) {
        serviceScope.launch {
            try {
                val ibeacon = extractIBeaconData(result) ?: return@launch
                if (ibeacon.uuid != TARGET_UUID) return@launch

                val beaconId = "${ibeacon.major}-${ibeacon.minor}"

                // Thread-safe sliding window update
                rssiWindows.compute(beaconId) { _, window ->
                    val w = window ?: ArrayDeque(WINDOW_SIZE)
                    w.addLast(result.rssi)
                    if (w.size > WINDOW_SIZE) w.removeFirst()
                    w
                }

                Log.d(TAG, "RSSI update: $beaconId = ${result.rssi}")
            } catch (e: Exception) {
                Log.e(TAG, "Error processing scan result: ${e.message}", e)
            }
        }
    }

    // ── Periodic KNN prediction ───────────────────────────────────────────────

    private fun startBatchProcessor() {
        serviceScope.launch {
            while (isActive) {
                delay(SCAN_INTERVAL_MS)
                runPrediction()
            }
        }
    }

    private fun runPrediction() {
        if (rssiWindows.isEmpty()) return

        // Build current fingerprint vector: beaconId -> median RSSI
        val currentScan: Map<String, Int> = rssiWindows.mapValues { (_, window) ->
            medianOf(window.toList())
        }

        Log.d(TAG, "Current scan vector: $currentScan")

        if (surveyMode) {
            // ── Survey mode: feed samples into SurveyManager ──────────────────
            surveyManager?.addSamples(currentScan)
            val count = surveyManager?.sampleCount() ?: 0
            onSurveyTick?.invoke(count)
            Log.d(TAG, "Survey tick: $count total samples")
        } else {
            // ── Positioning mode: run KNN ─────────────────────────────────────
            val constraint = navConstraint
            val zoneName = if (constraint != null) {
                matcher.predictConstrained(
                    currentScan,
                    setOf(constraint.first, constraint.second)
                )
            } else {
                matcher.predict(currentScan)
            }

            val result = ZoneResult(
                zoneName    = zoneName ?: "Unknown",
                beaconCount = currentScan.size,
                scanVector  = currentScan,
                timestamp   = System.currentTimeMillis() / 1000
            )

            onZoneDetected?.invoke(result)
            Log.d(TAG, "Predicted zone: ${result.zoneName}")
        }
    }

    // ── iBeacon parsing ───────────────────────────────────────────────────────

    private fun extractIBeaconData(result: ScanResult): IBeaconData? {
        return try {
            val scanRecord = result.scanRecord ?: return null
            val mfgData = scanRecord.manufacturerSpecificData ?: return null

            for (i in 0 until mfgData.size()) {
                val data = mfgData.valueAt(i)
                // iBeacon identifier: 0x02 0x15, minimum 23 bytes
                if (data.size >= 23 && data[0].toInt() == 0x02 && data[1].toInt() == 0x15) {
                    val uuid  = data.sliceArray(2..17).joinToString("") { "%02x".format(it) }
                    val major = ((data[18].toInt() and 0xFF) shl 8) or (data[19].toInt() and 0xFF)
                    val minor = ((data[20].toInt() and 0xFF) shl 8) or (data[21].toInt() and 0xFF)
                    val txPow = data[22].toInt()
                    return IBeaconData(uuid, major, minor, txPow)
                }
            }
            null
        } catch (e: Exception) {
            Log.e(TAG, "Error extracting iBeacon: ${e.message}", e)
            null
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private fun medianOf(values: List<Int>): Int {
        if (values.isEmpty()) return 0
        val sorted = values.sorted()
        val n = sorted.size
        return if (n % 2 == 0) ((sorted[n / 2 - 1] + sorted[n / 2]) / 2.0).toInt()
        else sorted[n / 2]
    }

    // ── Notification ──────────────────────────────────────────────────────────

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "BLE Beacon Scanning",
                NotificationManager.IMPORTANCE_LOW
            ).apply { description = "Fingerprint-based zone detection" }
            getSystemService(NotificationManager::class.java)
                .createNotificationChannel(channel)
        }
    }

    private fun createNotification(): Notification {
        val pendingIntent = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("FINGER")
            .setContentText("Fingerprint zone detection active…")
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .build()
    }

    // ── Data classes ──────────────────────────────────────────────────────────

    /** Result emitted to MainActivity after each KNN prediction cycle */
    data class ZoneResult(
        val zoneName: String,
        val beaconCount: Int,
        val scanVector: Map<String, Int>,   // beaconId -> median RSSI (for logging)
        val timestamp: Long
    )

    private data class IBeaconData(
        val uuid: String,
        val major: Int,
        val minor: Int,
        val txPower: Int
    )
}
