package com.example.wayfind

import android.content.Context
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.ConcurrentHashMap

/**
 * Survey Manager — collects live RSSI samples for a named zone,
 * computes per-beacon medians, and persists fingerprints to JSON.
 *
 * Persisted fingerprints are merged with [FingerprintDatabase.fingerprints]
 * at load time, so hardcoded entries are never lost.
 */
class SurveyManager(private val context: Context) {

    companion object {
        private const val TAG = "SurveyManager"
        private const val FILE_NAME = "finger_surveyed_fingerprints.json"
    }

    // ── Survey state ──────────────────────────────────────────────────────────

    /** True while a survey recording is in progress */
    var isSurveying = false
        private set

    /** Name of the zone currently being surveyed */
    var currentZoneName: String = ""
        private set

    /** beaconId -> all raw RSSI samples collected during this survey session */
    private val sampleBuffer = ConcurrentHashMap<String, MutableList<Int>>()

    // ── Survey control ────────────────────────────────────────────────────────

    /** Start collecting samples for [zoneName]. */
    fun startSurvey(zoneName: String) {
        currentZoneName = zoneName.trim()
        sampleBuffer.clear()
        isSurveying = true
        Log.d(TAG, "Survey started for zone: $currentZoneName")
    }

    /**
     * Feed the current sliding-window snapshot into the sample buffer.
     * Called by [BleBeaconService] on every batch tick while surveying.
     */
    fun addSamples(snapshot: Map<String, Int>) {
        if (!isSurveying) return
        for ((beaconId, rssi) in snapshot) {
            sampleBuffer.getOrPut(beaconId) { mutableListOf() }.add(rssi)
        }
        Log.d(TAG, "Samples added: ${snapshot.size} beacons, buffer=${sampleBuffer.map { "${it.key}:${it.value.size}" }}")
    }

    /**
     * Stop the survey, compute medians, persist the fingerprint, and return it.
     * Returns null if no samples were collected.
     */
    fun stopSurvey(): Fingerprint? {
        isSurveying = false

        if (sampleBuffer.isEmpty()) {
            Log.w(TAG, "Survey stopped but no samples collected")
            return null
        }

        // Compute median RSSI per beacon
        val rssiMap = sampleBuffer.mapValues { (_, samples) -> medianOf(samples) }

        val fingerprint = Fingerprint(
            zoneName = currentZoneName,
            rssiMap  = rssiMap
        )

        // Persist
        saveFingerprint(fingerprint)

        Log.d(TAG, "Survey complete: zone=$currentZoneName, beacons=${rssiMap.keys}")
        sampleBuffer.clear()
        return fingerprint
    }

    /** Discard current survey without saving. */
    fun cancelSurvey() {
        isSurveying = false
        sampleBuffer.clear()
        Log.d(TAG, "Survey cancelled")
    }

    /** Live sample count for the current survey (for UI feedback). */
    fun sampleCount(): Int = sampleBuffer.values.sumOf { it.size }

    // ── Persistence ───────────────────────────────────────────────────────────

    /**
     * Load all persisted fingerprints and merge with hardcoded database.
     * If both have an entry for the same zone name, the persisted one wins.
     */
    fun loadMergedFingerprints(): List<Fingerprint> {
        val persisted = loadPersistedFingerprints()
        val persistedZones = persisted.map { it.zoneName }.toSet()

        // Keep hardcoded entries whose zone is not overridden by a surveyed one
        val hardcoded = FingerprintDatabase.fingerprints.filter {
            it.zoneName !in persistedZones
        }

        val merged = hardcoded + persisted
        Log.d(TAG, "Merged fingerprints: ${merged.size} total (${hardcoded.size} hardcoded + ${persisted.size} surveyed)")
        return merged
    }

    /** All surveyed fingerprints from disk (does not include hardcoded). */
    fun loadPersistedFingerprints(): List<Fingerprint> {
        val file = getSurveyFile()
        if (!file.exists()) return emptyList()

        return try {
            val json = JSONArray(file.readText())
            (0 until json.length()).map { i ->
                val obj = json.getJSONObject(i)
                val rssiMap = mutableMapOf<String, Int>()
                val rssiObj = obj.getJSONObject("rssiMap")
                rssiObj.keys().forEach { key -> rssiMap[key] = rssiObj.getInt(key) }
                Fingerprint(zoneName = obj.getString("zoneName"), rssiMap = rssiMap)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error loading fingerprints: ${e.message}", e)
            emptyList()
        }
    }

    /** Delete a persisted fingerprint by zone name. Returns true if deleted. */
    fun deleteFingerprint(zoneName: String): Boolean {
        val existing = loadPersistedFingerprints().toMutableList()
        val before = existing.size
        existing.removeAll { it.zoneName == zoneName }
        if (existing.size == before) return false
        writeAll(existing)
        Log.d(TAG, "Deleted fingerprint: $zoneName")
        return true
    }

    /** Wipe all persisted fingerprints from disk. */
    fun clearAllPersisted(): Boolean = try {
        val f = getSurveyFile()
        if (f.exists()) f.delete() else true
    } catch (e: Exception) {
        Log.e(TAG, "Error clearing surveys: ${e.message}", e)
        false
    }

    fun getSurveyFilePath(): String = getSurveyFile().absolutePath

    // ── Private helpers ───────────────────────────────────────────────────────

    private fun saveFingerprint(fingerprint: Fingerprint) {
        val existing = loadPersistedFingerprints().toMutableList()
        // Replace if zone already exists, otherwise append
        val idx = existing.indexOfFirst { it.zoneName == fingerprint.zoneName }
        if (idx >= 0) existing[idx] = fingerprint else existing.add(fingerprint)
        writeAll(existing)
    }

    private fun writeAll(fingerprints: List<Fingerprint>) {
        val array = JSONArray()
        for (fp in fingerprints) {
            val rssiObj = JSONObject()
            fp.rssiMap.forEach { (k, v) -> rssiObj.put(k, v) }
            val obj = JSONObject().apply {
                put("zoneName", fp.zoneName)
                put("rssiMap", rssiObj)
            }
            array.put(obj)
        }
        FileOutputStream(getSurveyFile(), false).use {
            it.write(array.toString(2).toByteArray())
        }
        Log.d(TAG, "Wrote ${fingerprints.size} fingerprints to disk")
    }

    private fun getSurveyFile(): File =
        File(context.getExternalFilesDir(null), FILE_NAME)

    private fun medianOf(values: List<Int>): Int {
        if (values.isEmpty()) return 0
        val sorted = values.sorted()
        val n = sorted.size
        return if (n % 2 == 0) ((sorted[n / 2 - 1] + sorted[n / 2]) / 2.0).toInt()
        else sorted[n / 2]
    }
}
