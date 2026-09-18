import Foundation

// MARK: - Workout-Aware Types

extension StrainCalculator {

    struct WorkoutInterval {
        let start: Date
        let end: Date
        let activityName: String
    }

    struct WorkoutStrainDetail: Identifiable {
        let id = UUID()
        let intervalIndex: Int
        let activityName: String
        let strain: Double  // raw StrainLoad for this workout
        let heartRateCoverage: Double
        /// Zone minutes within this workout window. Key = zone, value = minutes.
        let zoneMinutes: [HeartRateZone: Double]
    }

    struct WorkoutStrainResult {
        let total: Double            // total StrainLoad for the day
        let workoutStrain: Double    // StrainLoad from workout windows
        let incidentalStrain: Double // StrainLoad from non-workout windows
        let workoutHeartRateCoverage: Double?
        let details: [WorkoutStrainDetail]
    }
}

struct StrainCalculator {

    // MARK: - Calibration Constants

    /// Estimated daily capacity used during the first 7-day calibration period.
    static let estimatedCalibrationCapacity: Double = 500

    /// Minimum days of history required before leaving calibration.
    static let calibrationDays: Int = 7

    /// Number of days used for the rolling personal capacity average.
    static let rollingCapacityDays: Int = 14

    // MARK: - StrainLoad

    /// Computes raw StrainLoad from timed HR samples.
    ///
    /// StrainLoad = Σ (minutesInZone × zoneWeight)
    ///
    /// Zones are based on MaxHR percentage thresholds, with convex (TRIMP-inspired)
    /// weights so high-intensity work is valued for its disproportionate physiological cost:
    ///   Zone 1 (50–60%): weight 0    — recovery intensity, no strain contribution
    ///   Zone 2 (60–70%): weight 0.8
    ///   Zone 3 (70–80%): weight 1.7
    ///   Zone 4 (80–90%): weight 2.9
    ///   Zone 5 (90–100%): weight 4.6
    ///
    /// Gap capping: HealthKit HR samples are sparse outside workouts (every 5–10 min).
    /// Each inter-sample interval is capped at 1 minute so a long gap between passive
    /// readings is never misinterpreted as continuous cardiovascular effort.
    ///
    /// Passive HR filter: samples whose average HR is below 50% of maxHR represent
    /// resting physiology and are skipped entirely.
    static func calculate(samples: [(Date, Double)], maxHR: Double) -> Double {
        guard samples.count > 1 else { return 0 }

        var zoneMinutes: [HeartRateZone: Double] = [:]
        HeartRateZone.allCases.forEach { zoneMinutes[$0] = 0 }

        for i in 1..<samples.count {
            let (prevTime, prevHR) = samples[i - 1]
            let (currTime, currHR) = samples[i]
            let rawMinutes = currTime.timeIntervalSince(prevTime) / 60.0
            guard rawMinutes > 0 else { continue }

            // Cap interval to 1 minute — prevents sparse passive readings from
            // inflating StrainLoad when the Watch samples infrequently.
            let minutes = min(rawMinutes, 1.0)

            let avgHR = (prevHR + currHR) / 2.0

            // Skip resting/passive heart rate — below 50% maxHR is not effort.
            guard avgHR >= 0.5 * maxHR else { continue }

            let zone = HeartRateZone.zone(for: avgHR, maxHR: maxHR)
            zoneMinutes[zone, default: 0] += minutes
        }

        #if DEBUG
        let load = zoneMinutes.reduce(0.0) { $0 + $1.value * $1.key.weight }
        print("[StrainCalculator] Zone minutes — Z1: \(String(format: "%.1f", zoneMinutes[.zone1] ?? 0)) Z2: \(String(format: "%.1f", zoneMinutes[.zone2] ?? 0)) Z3: \(String(format: "%.1f", zoneMinutes[.zone3] ?? 0)) Z4: \(String(format: "%.1f", zoneMinutes[.zone4] ?? 0)) Z5: \(String(format: "%.1f", zoneMinutes[.zone5] ?? 0)) | StrainLoad: \(String(format: "%.1f", load))")
        return load
        #else
        return zoneMinutes.reduce(0.0) { $0 + $1.value * $1.key.weight }
        #endif
    }

    // MARK: - Strain Score

    /// Converts raw StrainLoad to a monotonic 0–100 score relative to personal capacity.
    ///
    /// Uses an exponential saturation curve rather than a linear ratio. A day at the
    /// rolling personal capacity maps to ~63 instead of 100, preserving headroom for
    /// genuinely harder days while still limiting extreme values asymptotically.
    ///
    /// StrainScore = 100 × (1 − exp(−StrainLoad / Capacity))
    static func score(load: Double, capacity: Double) -> Double {
        guard load > 0, capacity > 0 else { return 0 }
        return 100.0 * (1.0 - Foundation.exp(-load / capacity))
    }

    // MARK: - Capacity Model

    /// Returns the personal daily capacity to use for scoring.
    ///
    /// - During the first 7 days (calibration): returns `estimatedCalibrationCapacity` (500).
    /// - After 7+ days: returns the rolling 14-day average of StrainLoad values.
    ///
    /// - Parameter loadHistory: Historical StrainLoad values ordered oldest→newest.
    static func capacity(fromLoads loadHistory: [Double]) -> Double {
        guard loadHistory.count >= calibrationDays else {
            return estimatedCalibrationCapacity
        }
        let recent = loadHistory.suffix(rollingCapacityDays)
        guard !recent.isEmpty else { return estimatedCalibrationCapacity }
        return recent.reduce(0, +) / Double(recent.count)
    }

    /// Returns true while the calibration period is still active (< 7 days of data).
    static func isCalibrating(loadHistory: [Double]) -> Bool {
        loadHistory.count < calibrationDays
    }

    // MARK: - Max HR Estimation

    /// Estimates max HR using the Tanaka formula: 208 − 0.7 × age.
    ///
    /// Preferred over the classic 220 − age (Haskell), which has a standard error
    /// of ±10–12 bpm and systematically overestimates max HR in younger adults and
    /// underestimates it in older adults. Because every HR-zone threshold (and the
    /// 50%-passive filter) is derived from max HR, that bias would shift the entire
    /// strain calculation. Tanaka tracks measured max HR far more closely across the
    /// adult age range. Users with a measured/observed max should override this in
    /// Settings (`maxHeartRate`).
    static func estimatedMaxHR(age: Int) -> Double {
        208.0 - 0.7 * Double(age)
    }

    // MARK: - Workout-Aware Strain

    /// Partitions StrainLoad across workout vs incidental windows by tagging each
    /// consecutive HR sample pair, preserving the full timeline continuity.
    ///
    /// Why not filter samples then call calculate()?
    /// Filtering breaks time continuity: two samples that were far apart in the
    /// original timeline end up adjacent after filtering, producing an inflated
    /// interval duration. Instead, we iterate all pairs in order and tag each one.
    static func calculateWorkoutAware(
        workoutIntervals: [WorkoutInterval],
        allSamples: [(Date, Double)],
        maxHR: Double
    ) -> WorkoutStrainResult {
        guard !workoutIntervals.isEmpty else {
            let total = calculate(samples: allSamples, maxHR: maxHR)
            return WorkoutStrainResult(
                total: total,
                workoutStrain: 0,
                incidentalStrain: total,
                workoutHeartRateCoverage: nil,
                details: []
            )
        }

        var totalLoad = 0.0
        var wLoad     = 0.0
        var iLoad     = 0.0
        var detailLoads = [Int: Double]()                     // workoutIntervals index → load
        var detailZones = [Int: [HeartRateZone: Double]]()    // workoutIntervals index → zone minutes
        var detailCoveredMinutes = [Int: Double]()

        for i in 1..<allSamples.count {
            let (prevTime, prevHR) = allSamples[i - 1]
            let (currTime, currHR) = allSamples[i]
            let rawMinutes = currTime.timeIntervalSince(prevTime) / 60.0
            guard rawMinutes > 0 else { continue }

            let minutes = min(rawMinutes, 1.0)
            let midpoint = prevTime.addingTimeInterval(currTime.timeIntervalSince(prevTime) / 2)
            let workoutIndices = workoutIntervals.indices.filter {
                midpoint >= workoutIntervals[$0].start && midpoint <= workoutIntervals[$0].end
            }
            for index in workoutIndices {
                detailCoveredMinutes[index, default: 0] += minutes
            }
            // Overlapping workout records each receive coverage, but load is assigned
            // once to the first matching interval so daily strain cannot double count.
            let workoutIndex = workoutIndices.first

            let avgHR   = (prevHR + currHR) / 2.0
            guard avgHR >= 0.5 * maxHR else { continue }

            let zone          = HeartRateZone.zone(for: avgHR, maxHR: maxHR)
            if let idx = workoutIndex {
                detailZones[idx, default: [:]][zone, default: 0] += minutes
            }
            let intervalLoad  = minutes * zone.weight
            guard intervalLoad > 0 else { continue }

            totalLoad += intervalLoad

            // Tag this pair by its midpoint's membership in a workout window.
            if let idx = workoutIndex {
                wLoad += intervalLoad
                detailLoads[idx, default: 0] += intervalLoad
            } else {
                iLoad += intervalLoad
            }
        }

        let details: [WorkoutStrainDetail] = workoutIntervals.enumerated().map { idx, interval in
            let durationMinutes = max(0, interval.end.timeIntervalSince(interval.start) / 60.0)
            let coveredMinutes = detailCoveredMinutes[idx] ?? 0
            let coverage = durationMinutes > 0 ? min(coveredMinutes / durationMinutes, 1) : 0
            return WorkoutStrainDetail(
                intervalIndex: idx,
                activityName: interval.activityName,
                strain: detailLoads[idx] ?? 0,
                heartRateCoverage: coverage,
                zoneMinutes: detailZones[idx] ?? [:]
            )
        }

        let totalWorkoutMinutes = workoutIntervals.reduce(0.0) {
            $0 + max(0, $1.end.timeIntervalSince($1.start) / 60.0)
        }
        let coveredWorkoutMinutes = detailCoveredMinutes.values.reduce(0, +)
        let workoutCoverage = totalWorkoutMinutes > 0
            ? min(coveredWorkoutMinutes / totalWorkoutMinutes, 1)
            : 0

        return WorkoutStrainResult(total: totalLoad,
                                   workoutStrain: wLoad,
                                   incidentalStrain: iLoad,
                                   workoutHeartRateCoverage: workoutCoverage,
                                   details: details)
    }
}
