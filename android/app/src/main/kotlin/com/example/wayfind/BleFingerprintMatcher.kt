package com.example.wayfind

import kotlin.math.pow
import kotlin.math.sqrt
import java.util.LinkedList
import android.util.Log

/**
 * Fingerprint record: one zone's radio map
 * beaconId is formatted as "major-minor"
 */
data class Fingerprint(
    val zoneName: String,
    val rssiMap: Map<String, Int>   // beaconId -> mean/median RSSI
)

/**
 * KNN-based fingerprint zone matcher.
 *
 * @param fingerprints  Training database loaded from FingerprintDatabase
 * @param k             Neighbours to vote on  (default 3)
 * @param historySize   Smoothing window size  (default 5)
 */
class BleFingerprintMatcher(
    private val fingerprints: List<Fingerprint>,
    private val k: Int = 3,
    private val historySize: Int = 5
) {
    private val predictionHistory = LinkedList<String>()

    /**
     * Predict best matching zone for the current scan.
     *
     * @param currentScan  Map of beaconId -> median RSSI from sliding window
     * @return Smoothed zone name, or null if no match possible
     */
    fun predict(currentScan: Map<String, Int>): String? {
        if (fingerprints.isEmpty() || currentScan.isEmpty()) return null

        // Distance to every stored fingerprint
        val distances = fingerprints.map { fingerprint ->
            fingerprint.zoneName to weightedDistance(currentScan, fingerprint.rssiMap)
        }

        // Top-k closest
        val topK = distances.sortedBy { it.second }.take(k)
        Log.w("BleFingerprintMatcher", "Normal predict done: $topK")
        // Majority vote
        val bestZone = topK
            .groupingBy { it.first }
            .eachCount()
            .maxByOrNull { it.value }
            ?.key

        return bestZone?.let { smoothPrediction(it) }
    }

    /**
     * Constrained prediction: only compares fingerprints whose zone name is
     * in [allowedZones].  Used during navigation to compare only the current
     * zone and the next zone on the path, ignoring all others.
     *
     * Falls back to unconstrained [predict] if fewer than 2 allowed
     * fingerprints are found in the database (safety net).
     *
     * @param currentScan   Map of beaconId -> median RSSI from sliding window
     * @param allowedZones  Set of zone names to consider (typically 2)
     * @return Smoothed zone name, or null if no match possible
     */
    fun predictConstrained(
        currentScan: Map<String, Int>,
        allowedZones: Set<String>
    ): String? {
        val subset = fingerprints.filter { it.zoneName in allowedZones }
        // Fall back to full search if we don't have enough fingerprints for the
        // requested zones (e.g. a zone was never surveyed)
        if (subset.size < 2) {
        Log.w("BleFingerprintMatcher",
            "predictConstrained fallback! Found ${subset.size} of ${allowedZones.size} " +
            "requested zones. Allowed=$allowedZones, " +
            "DB zones=${fingerprints.map { it.zoneName }}")
        return predict(currentScan)
    }
        if (currentScan.isEmpty()) return null

        val distances = subset.map { fingerprint ->
            fingerprint.zoneName to weightedDistance(currentScan, fingerprint.rssiMap)
        }

        val topK = distances.sortedBy { it.second }.take(k.coerceAtMost(subset.size))
        Log.w("BleFingerprintMatcher", "Constrained predict done: $topK")
        val bestZone = topK
            .groupingBy { it.first }
            .eachCount()
            .maxByOrNull { it.value }
            ?.key

        return bestZone?.let { smoothPrediction(it) }
    }

    // ── private helpers ──────────────────────────────────────────────────────

    /**
     * Weighted distance: 80% raw Euclidean + 20% mean-normalised pattern.
     *
     * WHY: pure mean-normalisation was stripping the absolute RSSI level,
     * so a very weak scan (e.g. all -94 dBm) looked identical in pattern
     * space to a strong fingerprint (all -54 dBm) — both normalise to {0,0,0}.
     * The raw component anchors matching to the actual signal strength while
     * the small pattern component still helps when there is a global path-loss
     * shift between survey time and use time.
     */
    private fun weightedDistance(
        current: Map<String, Int>,
        stored: Map<String, Int>
    ): Double {
        val rawDist     = euclideanRaw(current, stored)
        val patternDist = euclideanNormalised(normalize(current), normalize(stored))
        return 0.8 * rawDist + 0.2 * patternDist
    }

    /**
     * Raw Euclidean distance between two integer RSSI maps.
     * Missing beacons are penalised with a floor value of -100 dBm.
     */
    private fun euclideanRaw(
        current: Map<String, Int>,
        stored: Map<String, Int>
    ): Double {
        val allBeacons = current.keys + stored.keys
        var sum = 0.0
        for (beaconId in allBeacons) {
            val c = (current[beaconId] ?: -100).toDouble()
            val s = (stored[beaconId]  ?: -100).toDouble()
            sum += (c - s).pow(2)
        }
        return sqrt(sum)
    }

    /**
     * Euclidean distance between two already-normalised Double RSSI maps.
     * Missing beacons are penalised with 0.0 (they were already mean-centred).
     */
    private fun euclideanNormalised(
        current: Map<String, Double>,
        stored: Map<String, Double>
    ): Double {
        val allBeacons = current.keys + stored.keys
        var sum = 0.0
        for (beaconId in allBeacons) {
            val c = current[beaconId] ?: 0.0
            val s = stored[beaconId]  ?: 0.0
            sum += (c - s).pow(2)
        }
        return sqrt(sum)
    }

    /**
     * Mean-centre RSSI values (used only for the pattern component).
     */
    private fun normalize(rssiMap: Map<String, Int>): Map<String, Double> {
        if (rssiMap.isEmpty()) return emptyMap()
        val mean = rssiMap.values.average()
        return rssiMap.mapValues { (_, v) -> v - mean }
    }

    /**
     * Majority vote over a rolling history window to suppress rapid flipping.
     */
    private fun smoothPrediction(newPrediction: String): String {
        predictionHistory.add(newPrediction)
        if (predictionHistory.size > historySize) predictionHistory.removeFirst()

        return predictionHistory
            .groupingBy { it }
            .eachCount()
            .maxByOrNull { it.value }
            ?.key ?: newPrediction
    }
}
