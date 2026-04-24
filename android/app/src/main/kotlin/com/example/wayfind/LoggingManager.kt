package com.example.wayfind

import android.content.Context
import android.util.Log
import java.io.File
import java.io.FileOutputStream
import java.text.SimpleDateFormat
import java.util.*

/**
 * Logging Manager — Fingerprinting edition.
 *
 * Logs each prediction cycle: the raw RSSI vector, matched zone, and timing.
 */
class LoggingManager(private val context: Context) {

    companion object {
        private const val TAG = "LoggingManager"
        private const val LOG_FILE_NAME = "finger_fingerprint_log.txt"
    }

    private val dateFormat = SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS", Locale.US)

    // ── Public API ────────────────────────────────────────────────────────────

    /**
     * Log one prediction cycle.
     *
     * @param scanVector       beaconId -> median RSSI fed to KNN
     * @param predictedZone    Zone name returned by matcher
     * @param processingTimeMs Elapsed time for the cycle
     * @param status           "success" or "error"
     */
    fun logPrediction(
        scanVector: Map<String, Int>,
        predictedZone: String,
        processingTimeMs: Double,
        status: String = "success"
    ) {
        try {
            val timestamp = dateFormat.format(Date())
            val sb = StringBuilder()

            sb.append("=".repeat(70)).append("\n")
            sb.append("[$timestamp] PREDICTION\n")
            sb.append("=".repeat(70)).append("\n")

            sb.append("Scan Vector (${scanVector.size} beacons):\n")
            for ((beaconId, rssi) in scanVector.entries.sortedBy { it.key }) {
                sb.append("  $beaconId → $rssi dBm\n")
            }

            sb.append("\nPredicted Zone : $predictedZone\n")
            sb.append("Processing Time: ${String.format("%.2f", processingTimeMs)} ms\n")
            sb.append("Status         : ${status.uppercase()}\n")
            sb.append("=".repeat(70)).append("\n\n")

            appendToFile(sb.toString())
        } catch (e: Exception) {
            Log.e(TAG, "Error writing prediction log: ${e.message}", e)
        }
    }

    /**
     * Log an error event.
     */
    /**
     * Log a completed survey fingerprint.
     *
     * Called by MainActivity after [SurveyManager.stopSurvey] returns a
     * non-null [Fingerprint].  Records the zone name, number of beacons, and
     * the full per-beacon median RSSI map that was persisted to disk.
     *
     * @param fingerprint  The fingerprint that was just saved
     * @param sampleCount  Total raw RSSI samples collected during the survey
     */
    fun logSurveyFingerprint(
        fingerprint: Fingerprint,
        sampleCount: Int,
        rawSamples:  Map<String, List<Int>> = emptyMap()
    ) {
        try {
            val timestamp = dateFormat.format(Date())
            val sb = StringBuilder()

            sb.append("=".repeat(70)).append("\n")
            sb.append("[$timestamp] SURVEY FINGERPRINT SAVED\n")
            sb.append("=".repeat(70)).append("\n")
            sb.append("Zone Name     : ${fingerprint.zoneName}\n")
            sb.append("Beacons seen  : ${fingerprint.rssiMap.size}\n")
            sb.append("Total samples : $sampleCount\n")

            sb.append("\nMedian RSSI per beacon:\n")
            for ((beaconId, rssi) in fingerprint.rssiMap.entries.sortedBy { it.key }) {
                sb.append("  $beaconId → $rssi dBm\n")
            }

            if (rawSamples.isNotEmpty()) {
                sb.append("\nRaw sample buffer:\n")
                for ((beaconId, samples) in rawSamples.entries.sortedBy { it.key }) {
                    sb.append("  $beaconId (${samples.size}): [${samples.joinToString(", ")}]\n")
                }
            }

            sb.append("=".repeat(70)).append("\n\n")

            appendToFile(sb.toString())
        } catch (e: Exception) {
            Log.e(TAG, "Error writing survey fingerprint log: ${e.message}", e)
        }
    }

    /**
     * Log an error event.
     */
    fun logError(errorMessage: String, processingTimeMs: Double) {
        try {
            val timestamp = dateFormat.format(Date())
            val sb = StringBuilder()

            sb.append("=".repeat(70)).append("\n")
            sb.append("[$timestamp] ERROR\n")
            sb.append("=".repeat(70)).append("\n")
            sb.append("Error          : $errorMessage\n")
            sb.append("Processing Time: ${String.format("%.2f", processingTimeMs)} ms\n")
            sb.append("Status         : ERROR\n")
            sb.append("=".repeat(70)).append("\n\n")

            appendToFile(sb.toString())
        } catch (e: Exception) {
            Log.e(TAG, "Error writing error log: ${e.message}", e)
        }
    }

    fun getLogFilePath(): String = getLogFile().absolutePath

    fun clearLogs(): Boolean = try {
        val f = getLogFile()
        if (f.exists()) f.delete() else true
    } catch (e: Exception) {
        Log.e(TAG, "Error clearing logs: ${e.message}", e)
        false
    }

    fun getLogInfo(): Pair<Boolean, Long> {
        val f = getLogFile()
        return Pair(f.exists(), if (f.exists()) f.length() else 0L)
    }

    // ── Private helpers ───────────────────────────────────────────────────────

    private fun getLogFile(): File = File(context.getExternalFilesDir(null), LOG_FILE_NAME)

    private fun appendToFile(text: String) {
        FileOutputStream(getLogFile(), true).use { it.write(text.toByteArray()) }
        Log.d(TAG, "Log written to: ${getLogFile().absolutePath}")
    }
}
