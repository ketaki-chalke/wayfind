package com.example.wayfind

/**
 * Fingerprint training database.
 *
 * Beacon IDs are formatted as "major-minor" (e.g. "400-1").
 *
 * To add real fingerprints:
 *  1. Switch to Survey Mode in the app.
 *  2. Stand in each zone and tap Start Recording for ~30 s.
 *  3. Tap Stop & Save — the fingerprint is persisted automatically.
 *
 * Surveyed fingerprints override hardcoded ones with the same zone name.
 */
object FingerprintDatabase {

    /**
     * Human-readable names for each beacon, keyed by "major-minor".
     * Used for display in logs and the RSSI bar chart — does NOT affect KNN matching.
     */
    val beaconNames: Map<String, String> = mapOf(
        "400-1" to "Top corridor",
        "400-2" to "Topmost corridor",
        "400-3" to "Right corridor",
        "400-4" to "Left corridor",
        "400-5" to "Bottom corridor"
    )

    /**
     * Hardcoded training fingerprints merged with surveyed ones at runtime.
     * Start with an empty list and use Survey Mode to record real zones.
     */
    val fingerprints: List<Fingerprint> = listOf(
        // Empty — use Survey Mode to record your zones
    )
}