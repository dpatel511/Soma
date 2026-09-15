import Foundation

struct RecoveryInput {
    var todayHRV: Double?
    var hrvBaseline: Double?
    var todayRestingHR: Double?
    var rhrBaseline: Double?
    var sleepScore: Double        // 0–100
    var yesterdayStrain: Double   // 0–21
    /// Recent HRV values (oldest → newest) for the personal log-domain z-score.
    /// When supplied (≥ minDaysRequired), the HRV component uses a z-score against the
    /// individual's own variability instead of a fixed ±50% ratio band.
    var hrvHistory: [Double]? = nil
    /// Signed point adjustment applied after the weighted components (before clamping).
    /// Used to offset benign physiology the raw signals can't distinguish — e.g. normal
    /// late-luteal HRV suppression / RHR elevation (see MenstrualCycleCalculator).
    var recoveryAdjustment: Double = 0
}

struct RecoveryCalculator {

    /// Calculates recovery score 0–100.
    static func calculate(input: RecoveryInput) -> Double {
        let hrv = computeHRVComponent(todayHRV: input.todayHRV, baseline: input.hrvBaseline, history: input.hrvHistory)
        let rhr = computeRHRComponent(todayRHR: input.todayRestingHR, baseline: input.rhrBaseline)
        let sleep = clamp(input.sleepScore, 0, 100)
        let strainRecovery = clamp((1.0 - input.yesterdayStrain / 21.0), 0, 1) * 100

        var recovery = 0.40 * hrv + 0.25 * rhr + 0.25 * sleep + 0.10 * strainRecovery

        // Offset benign physiology (e.g. normal late-luteal HRV/RHR shifts) so it isn't
        // misread as poor recovery. Zero unless a caller supplies an adjustment.
        recovery += input.recoveryAdjustment

        return clamp(recovery, 0, 100)
    }

    // MARK: - Training Recommendation

    static func trainingRecommendation(
        recovery: Double,
        last3DayStrainAvg: Double,
        sleepDebtHours: Double
    ) -> String {
        var base: String
        switch recovery {
        case 67...100:
            base = "Your recent signals are near or above baseline. Consider a higher-intensity session if you feel ready."
        case 50..<67:
            base = "Your recent signals support a steady session if you feel ready."
        case 34..<50:
            base = "Some signals are below baseline. Consider keeping intensity low."
        default:
            base = "Several signals are below baseline. Consider prioritizing rest and sleep."
        }

        var suffixes: [String] = []
        if last3DayStrainAvg > 15 {
            suffixes.append("Consider a deload — high cumulative strain.")
        }
        if sleepDebtHours > 2 {
            suffixes.append("Sleep debt is elevated — aim for extra sleep tonight.")
        }

        if suffixes.isEmpty {
            return base
        }
        return base + " " + suffixes.joined(separator: " ")
    }

    // MARK: - Private

    private static func computeHRVComponent(todayHRV: Double?, baseline: Double?, history: [Double]?) -> Double {
        guard let hrv = todayHRV else { return 50 }

        // Preferred: personal z-score in log space. HRV is log-normal, and a deviation
        // only means something relative to the individual's own day-to-day variability.
        if let history, let z = BaselineCalculator.hrvZScore(today: hrv, values: history) {
            // z = 0 (at personal baseline) → 50; +2 SD → 100, −2 SD → 0.
            return clamp(50 + z * 25.0, 0, 100)
        }

        // Fallback (insufficient history): simple ratio vs the scalar baseline.
        guard let base = baseline, base > 0 else { return 50 }
        let ratio = hrv / base
        // clamp ratio [0.5, 1.5] → [0, 100]
        return BaselineCalculator.normalizeRatio(ratio, low: 0.5, high: 1.5)
    }

    private static func computeRHRComponent(todayRHR: Double?, baseline: Double?) -> Double {
        guard let rhr = todayRHR, let base = baseline else { return 50 }
        let deviation = base - rhr // positive = lower HR = better
        // clamp deviation [-10, 10] → [0, 100]
        return BaselineCalculator.normalizeRatio(deviation, low: -10, high: 10)
    }

    private static func clamp(_ value: Double, _ min: Double, _ max: Double) -> Double {
        BaselineCalculator.clamp(value, min: min, max: max)
    }
}
