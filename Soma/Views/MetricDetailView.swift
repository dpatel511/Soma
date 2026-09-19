import SwiftUI
import Charts

private struct RecoveryHRVChartPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
    let segment: Int
    let baseline: Double?
    let lowerBand: Double?
    let upperBand: Double?
}

private struct ScoreVersionBoundary: Identifiable {
    let id = UUID()
    let date: Date
    let version: Int
}

// MARK: - Metric Type

enum DashboardMetric: String, Identifiable {
    case recovery, sleep, strain, stress

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recovery: return "Recovery"
        case .sleep:    return "Sleep"
        case .strain:   return "Strain"
        case .stress:   return "Stress"
        }
    }

    var systemImage: String {
        switch self {
        case .recovery: return "heart.fill"
        case .sleep:    return "moon.zzz.fill"
        case .strain:   return "flame.fill"
        case .stress:   return "brain.head.profile"
        }
    }

    var accentColor: Color {
        switch self {
        case .recovery: return Color.somaGreen
        case .sleep:    return Color.somaBlue
        case .strain:   return Color.somaOrange
        case .stress:   return Color.somaYellow
        }
    }

    func score(from m: DailyMetrics) -> Double {
        switch self {
        case .recovery: return m.recoveryScore
        case .sleep:    return m.sleepScore
        case .strain:   return m.strainScore
        case .stress:   return m.stressScore
        }
    }

    func state(from m: DailyMetrics) -> ColorState {
        switch self {
        case .recovery: return m.recoveryState
        case .sleep:    return m.sleepState
        case .strain:   return m.strainState
        case .stress:   return m.stressState
        }
    }

    func dataCoverage(from m: DailyMetrics) -> Double? {
        switch self {
        case .recovery: return m.recoveryDataCoverage
        case .sleep:    return m.sleepDataCoverage
        case .strain:   return m.strainDataCoverage
        case .stress:   return m.stressDataCoverage
        }
    }

    func hasSufficientData(in m: DailyMetrics) -> Bool {
        switch self {
        case .recovery: return m.hasSufficientRecoveryData
        case .sleep:    return m.hasSufficientSleepData
        case .strain:   return m.hasSufficientStrainData
        case .stress:   return m.hasSufficientStressData
        }
    }
}

// MARK: - MetricInsightGenerator

struct MetricInsightGenerator {

    static func generate(
        for metric: DashboardMetric,
        metrics: DailyMetrics,
        sleepGoal: Double,
        history: [DailyMetrics] = []
    ) -> (observations: [String], actions: [String]) {
        switch metric {
        case .sleep:    return sleepInsights(metrics: metrics, sleepGoal: sleepGoal)
        case .recovery: return recoveryInsights(metrics: metrics, history: history)
        case .strain:   return strainInsights(metrics: metrics)
        case .stress:   return stressInsights(metrics: metrics)
        }
    }

    private static func sleepInsights(metrics: DailyMetrics, sleepGoal: Double) -> (observations: [String], actions: [String]) {
        var obs: [String] = []
        var acts: [String] = []

        if let actual = metrics.sleepDurationHours {
            let diff = sleepGoal - actual
            if diff > 0.1 {
                let debtStr = formatHours(diff)
                obs.append("You slept \(debtStr) less than your sleep goal")
                acts.append("Increase total sleep duration by \(debtStr)")
            } else {
                obs.append("You met your sleep duration goal")
            }
        }

        if let n = metrics.sleepInterruptions, n > 4 {
            obs.append("Sleep was interrupted \(n) times during the night")
            acts.append("Limit fluids 2 hours before bed to reduce interruptions")
        }

        if let hrv = metrics.sleepingHRV, hrv < 30 {
            obs.append("Sleeping HRV was low, indicating reduced overnight recovery")
            acts.append("Avoid alcohol and screen time before bed to improve HRV")
        }

        if let sHR = metrics.sleepingHR, let rhr = metrics.restingHR, sHR > rhr + 5 {
            obs.append("Sleeping heart rate was elevated compared to your resting HR")
            acts.append("Avoid late meals and alcohol which elevate overnight heart rate")
        }

        if let start = metrics.sleepStartTime {
            let hour = Calendar.current.component(.hour, from: start)
            if hour >= 0 && hour < 5 {
                obs.append("Your sleep start time was later than ideal")
                acts.append("Aim to be in bed before midnight for better recovery")
            }
        }

        if acts.isEmpty { acts.append("Maintain your current sleep routine") }
        return (obs, acts)
    }

    private static func recoveryInsights(
        metrics: DailyMetrics,
        history: [DailyMetrics]
    ) -> (observations: [String], actions: [String]) {
        var obs: [String] = []
        var acts: [String] = []

        // Match the score calculation: use only observations before the selected day,
        // and compare overnight SDNN with prior overnight SDNN.
        let priorDays = BaselineCalculator.priorMetrics(from: history, before: metrics.date)
        let hrvHist      = BaselineCalculator.extractHistory(from: priorDays, \.sleepingHRV)
        let rhrHist      = BaselineCalculator.extractHistory(from: priorDays, \.restingHR)
        let hrvBaseline  = BaselineCalculator.computePersonalBaseline(from: hrvHist.map { $0.1 })
        let rhrBaseline  = BaselineCalculator.computePersonalBaseline(from: rhrHist.map { $0.1 })

        // Yesterday's strain affects the 10% strain-recovery component
        let yesterdayStrain = priorDays.sorted { $0.date < $1.date }.last?.strainScore ?? 0

        // ── HRV component (40% weight) ──────────────────────────────────────
        if let hrv = metrics.sleepingHRV {
            if let base = hrvBaseline, base > 0 {
                let ratio = hrv / base
                if ratio < 0.85 {
                    let pct = Int((1.0 - ratio) * 100)
                    obs.append("HRV dropped \(pct)% below your baseline (\(String(format: "%.0f", hrv)) vs \(String(format: "%.0f", base)) ms) — this is the largest recovery driver at 40% weight")
                    acts.append("Overnight HRV is below your personal range. Consider rest or light movement and weigh the signal alongside how you feel")
                } else if ratio > 1.10 {
                    let pct = Int((ratio - 1.0) * 100)
                    obs.append("HRV is \(pct)% above baseline (\(String(format: "%.0f", hrv)) ms) — a strong recovery boost")
                } else {
                    obs.append("HRV is near your baseline (\(String(format: "%.0f", hrv)) ms) — neutral recovery impact")
                }
            } else {
                obs.append("Overnight HRV: \(String(format: "%.0f", hrv)) ms (baseline still building — need 7+ prior nights)")
            }
        } else {
            obs.append("Overnight HRV was not recorded, so the recovery estimate has lower coverage; daytime HRV was not substituted")
        }

        // ── RHR component (25% weight) ──────────────────────────────────────
        if let rhr = metrics.restingHR {
            if let base = rhrBaseline {
                let deviation = base - rhr   // positive = lower than baseline = good
                if deviation < -3 {
                    obs.append("Resting HR is \(Int(-deviation)) bpm above your usual \(String(format: "%.0f", base)) bpm — penalising recovery (25% weight)")
                    acts.append("Resting HR is above baseline. Consider hydration and rest, and monitor the trend alongside how you feel")
                } else if deviation > 3 {
                    obs.append("Resting HR is \(Int(deviation)) bpm below your baseline — a positive recovery signal")
                } else {
                    obs.append("Resting HR (\(Int(rhr)) bpm) is near your baseline — neutral impact")
                }
            } else {
                obs.append("Resting HR: \(Int(rhr)) bpm (baseline still building)")
            }
        }

        // ── Sleep quality component (25% weight) ────────────────────────────
        let sleepScore = metrics.sleepScore
        if sleepScore < 50 {
            obs.append("Sleep quality was poor (\(Int(sleepScore))/100) — dragging recovery down significantly (25% weight)")
            acts.append("Poor sleep is a major recovery blocker — aim for an earlier bedtime and cooler room tonight")
        } else if sleepScore < 70 {
            obs.append("Sleep quality was below average (\(Int(sleepScore))/100) — a moderate drag on recovery")
            acts.append("Improving tonight's sleep will directly lift tomorrow's recovery score")
        } else {
            obs.append("Sleep quality was good (\(Int(sleepScore))/100) — contributing positively")
        }

        // ── Strain recovery component (10% weight) ───────────────────────────
        if yesterdayStrain > 70 {
            obs.append("High strain yesterday (\(Int(yesterdayStrain))/100) reduced recovery capacity via the strain component (10% weight)")
            acts.append("After high-strain days, easy active recovery helps — avoid another intense session today")
        }

        // Overall fallback
        if obs.isEmpty {
            obs.append("The available recovery inputs are near your recent personal range")
            acts.append("Use the estimate alongside how you feel when choosing training intensity")
        } else if acts.isEmpty && metrics.recoveryScore < 50 {
            acts.append("Reduce training intensity today and prioritize sleep tonight")
        }

        return (obs, acts)
    }

    static func acrDescription(history: [DailyMetrics]) -> String? {
        let acr = TrainingGuidanceEngine.acrRatio(history: history)
        guard let acr else { return nil }
        let fmt = String(format: "%.2f", acr)
        if acr > 1.3 {
            return "Load ratio \(fmt) — recent recorded load is above your longer-term average. No automatic score penalty is applied."
        } else if acr < 0.8 {
            return "Load ratio \(fmt) — recent recorded load is below your longer-term average."
        }
        return "Load ratio \(fmt) — recent and longer-term recorded loads are similar."
    }

    private static func strainInsights(metrics: DailyMetrics) -> (observations: [String], actions: [String]) {
        var obs: [String] = []
        var acts: [String] = []

        let state = ColorState.strain(score: metrics.strainScore)
        obs.append("Strain category: \(state.label)")

        if metrics.strainScore >= 80 {
            acts.append("Ensure tomorrow includes light activity or full rest")
            acts.append("Prioritize 8+ hours of sleep for adequate recovery")
        } else if metrics.strainScore >= 60 {
            acts.append("Maintain hydration and adequate protein intake")
        } else if metrics.strainScore <= 20 {
            obs.append("Mostly resting or light activity today")
            acts.append("Consider adding light movement to support circulation")
        } else {
            acts.append("Continue with your current training approach")
        }

        if let wm = metrics.workoutMinutes, wm > 0 {
            obs.append("\(formatHours(wm / 60)) of workout time contributed to today's strain")
            obs.append("Strain is derived from Apple Health heart-rate samples, not measured live; strength work may be underrepresented")
        }
        if let coverage = metrics.workoutHeartRateCoverage {
            let percent = Int((coverage * 100).rounded())
            if coverage < 0.75 {
                obs.append("Workout heart-rate coverage is partial (\(percent)%); the strain estimate may change after Apple Health finishes syncing")
                acts.append("Keep your Watch and iPhone connected, then refresh after the workout sync completes")
            } else {
                obs.append("Workout heart-rate coverage: \(percent)%")
            }
        }
        return (obs, acts)
    }

    private static func stressInsights(metrics: DailyMetrics) -> (observations: [String], actions: [String]) {
        var obs: [String] = []
        var acts: [String] = []

        if metrics.stressScore > 60 {
            obs.append("Stress indicators are elevated today")
            acts.append("Try a 5-minute breathing exercise or short walk")
            acts.append("Reduce caffeine and screen exposure this evening")
        } else if metrics.stressScore > 30 {
            obs.append("Stress is at a moderate level")
            acts.append("Short mindfulness breaks can help maintain balance")
        } else {
            obs.append("Stress levels are low — your nervous system is calm")
            acts.append("Good state for focused work or training")
        }
        return (obs, acts)
    }

    private static func formatHours(_ h: Double) -> String {
        let total = Int((h * 60).rounded())
        let hrs = total / 60; let mins = total % 60
        if hrs == 0 { return "\(mins)m" }
        if mins == 0 { return "\(hrs)h" }
        return "\(hrs)h \(mins)m"
    }
}

// MARK: - MetricDetailView

struct MetricDetailView: View {
    let metric: DashboardMetric
    @ObservedObject var viewModel: DashboardViewModel

    @State private var selectedRange: TrendsViewModel.TimeRange = .week
    @State private var selectedDate: Date?
    @State private var intradayHRData: [(Date, Double)] = []
    @State private var intradayWorkouts: [(start: Date, end: Date)] = []
    @State private var intradayDate: Date = Date()
    @State private var selectedStressDate: Date?
    @State private var selectedStrainDate: Date?
    @Environment(\.dismiss) private var dismiss

    private var history: [DailyMetrics] {
        viewModel.loadHistory(days: selectedRange.days)
            .filter { metric.hasSufficientData(in: $0) }
    }

    private var analysisHistory: [DailyMetrics] {
        // Include a 30-day lookback before the visible range so the earliest plotted
        // day can still build a prior-only baseline without borrowing future values.
        viewModel.loadHistory(days: selectedRange.days + 30)
    }

    private var selectedMetrics: DailyMetrics? {
        if let date = selectedDate {
            return history.min {
                abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
            }
        }
        return history.max { $0.date < $1.date }
    }

    private var sleepGoal: Double {
        let stored = UserDefaults.standard.double(forKey: UserDefaultsKeys.baselineSleepHours)
        return stored > 0 ? stored : 7.0
    }

    var body: some View {
        NavigationStack {
            ZStack {
                SomaGradient.canvas(tint: metric.accentColor)

                ScrollView {
                    VStack(spacing: 18) {
                        rangePicker
                        scoreChart
                        if metric == .recovery {
                            recoveryHRVChart
                        }
                        if metric == .stress {
                            intradayStressChart
                        }
                        if metric == .strain {
                            intradayStrainChart
                            if let m = selectedMetrics, let zones = m.workoutZoneDetails, !zones.isEmpty {
                                workoutZoneChart(zones)
                            }
                        }
                        if let m = selectedMetrics {
                            if metric == .recovery {
                                recoveryDataQualityPanel(for: m)
                            }
                            insightsPanel(for: m)
                        }
                        // Sleep extras (sleep metric only)
                        if metric == .sleep {
                            if !weeklyGoalHistory.isEmpty {
                                WeeklyGoalCard(history: weeklyGoalHistory)
                                    .padding(.horizontal)
                            }
                            sleepRegularityPanel
                            sleepDebtChart
                            sleepCalendarGrid
                        }
                        statsRow
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle(metric.title)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(Color.somaBlue)
                }
            }
            .task {
                if metric == .stress || metric == .strain {
                    intradayDate = Date()
                    intradayHRData = await viewModel.fetchIntradayHR(for: Date())
                    intradayWorkouts = await viewModel.fetchWorkoutIntervals(for: Date())
                }
            }
            .onChange(of: selectedDate) { _, newDate in
                if metric == .stress || metric == .strain, let date = newDate {
                    Task {
                        intradayDate = date
                        intradayHRData = await viewModel.fetchIntradayHR(for: date)
                        intradayWorkouts = await viewModel.fetchWorkoutIntervals(for: date)
                    }
                }
            }
        }
    }

    // MARK: - Range Picker

    private var rangePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(TrendsViewModel.TimeRange.allCases, id: \.self) { range in
                    let on = range == selectedRange
                    Button {
                        Haptics.select()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            selectedRange = range
                        }
                        selectedDate = history.max { $0.date < $1.date }?.date
                    } label: {
                        Text(range.rawValue)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(on ? .black : Color.somaTextSecondary)
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .background(
                                Capsule().fill(on ? AnyShapeStyle(metric.accentColor) : AnyShapeStyle(Color.white.opacity(0.06)))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Score Chart

    private var scoreChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: metric.systemImage)
                    .foregroundColor(metric.accentColor)
                Text("\(metric.title) Score")
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
                tooltipView
            }

            Chart(history) { entry in
                AreaMark(
                    x: .value("Date", entry.date, unit: .day),
                    y: .value("Score", metric.score(from: entry))
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [metric.accentColor.opacity(0.35), metric.accentColor.opacity(0)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                LineMark(
                    x: .value("Date", entry.date, unit: .day),
                    y: .value("Score", metric.score(from: entry))
                )
                .foregroundStyle(metric.accentColor)
                .interpolationMethod(.catmullRom)
                PointMark(
                    x: .value("Date", entry.date, unit: .day),
                    y: .value("Score", metric.score(from: entry))
                )
                .foregroundStyle(isSelected(entry.date) ? metric.state(from: entry).color : metric.accentColor)
                .symbolSize(isSelected(entry.date) ? 80 : 25)

                if let sel = selectedDate {
                    RuleMark(x: .value("Selected", sel, unit: .day))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(Color.secondary.opacity(0.5))
                }
            }
            .chartYScale(domain: 0...100)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: axisDayStride)) { _ in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel(format: axisDayFormat)
                }
            }
            .chartYAxis { AxisMarks(position: .leading) }
            .frame(height: 220)
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { location in
                            guard let plotFrameAnchor = proxy.plotFrame else { return }
                            let plotFrame = geo[plotFrameAnchor]
                            let relativeX = location.x - plotFrame.origin.x
                            guard relativeX >= 0, relativeX <= plotFrame.width else { return }
                            if let tappedDate: Date = proxy.value(atX: relativeX) {
                                selectedDate = history.min {
                                    abs($0.date.timeIntervalSince(tappedDate)) < abs($1.date.timeIntervalSince(tappedDate))
                                }?.date
                            }
                        }
                }
            }
            .onAppear {
                selectedDate = history.max { $0.date < $1.date }?.date
            }
        }
        .padding(14)
        .background(SomaGradient.card)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.somaHairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 14, x: 0, y: 8)
        .padding(.horizontal)
    }

    // MARK: - Intraday Stress Chart

    /// Buckets daytime (8AM–8PM) HR samples into 30-minute bins and derives a relative stress level.
    /// Filtered to the same 8AM–8PM window as the daily stress score so the two are consistent.
    /// Exercise is excluded the same way the daily score excludes it — workout windows (plus a
    /// cooldown tail) and any high-effort samples are dropped — so the chart no longer spikes to
    /// 100 simply because the user worked out.
    /// Stress per bin = clamp((avgHR - rhrBaseline) / rhrBaseline, 0, 1) × 100
    private var intradayStressBuckets: [(Date, Double)] {
        guard !intradayHRData.isEmpty else { return [] }

        let rhrBaseline = history.compactMap { $0.restingHR }.suffix(7).reduce(0, +)
            / max(1, Double(history.compactMap { $0.restingHR }.suffix(7).count))
        let baseline = rhrBaseline > 0 ? rhrBaseline : 65.0

        // Match the daily stress score: restrict to the daytime window, then strip
        // exercise (workout windows + high-effort samples) so movement isn't read as stress.
        let daytime = StressCalculator.filterDaytime(intradayHRData, on: intradayDate)
        let sedentary = StressCalculator.filterSedentary(
            daytime,
            workoutIntervals: intradayWorkouts,
            maxHR: viewModel.maxHR
        )
        guard !sedentary.isEmpty else { return [] }

        let cal = Calendar.current
        var buckets: [Date: [Double]] = [:]
        for (date, hr) in sedentary {
            // Round down to nearest 30-min bucket
            var comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            comps.minute = (comps.minute ?? 0) < 30 ? 0 : 30
            comps.second = 0
            if let bucket = cal.date(from: comps) {
                buckets[bucket, default: []].append(hr)
            }
        }
        return buckets
            .sorted { $0.key < $1.key }
            .map { (date, hrs) in
                let avg = hrs.reduce(0, +) / Double(hrs.count)
                let stress = min(100, max(0, ((avg - baseline) / baseline) * 100))
                return (date, stress)
            }
    }

    private var intradayStressChart: some View {
        let dayLabel = Calendar.current.isDateInToday(intradayDate) ? "Today" : intradayDate.formatted(.dateTime.month(.abbreviated).day())
        let buckets = intradayStressBuckets
        let accentColor = metric.accentColor

        // Nearest bucket to the user's selection
        let selectedBucket: (Date, Double)? = selectedStressDate.flatMap { sel in
            buckets.min { abs($0.0.timeIntervalSince(sel)) < abs($1.0.timeIntervalSince(sel)) }
        }

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(dayLabel)'s Stress Pattern")
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
                if let (date, stress) = selectedBucket {
                    let label = stressLabel(for: stress)
                    Text("\(date.formatted(.dateTime.hour().minute())) · \(Int(stress.rounded()))  \(label)")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.somaCardElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            }

            if buckets.isEmpty {
                Text("No heart rate data available for \(dayLabel.lowercased()).")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 32)
            } else {
                Chart(buckets, id: \.0) { date, stress in
                    AreaMark(
                        x: .value("Time", date),
                        y: .value("Stress", stress)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [accentColor.opacity(0.35), accentColor.opacity(0)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    LineMark(
                        x: .value("Time", date),
                        y: .value("Stress", stress)
                    )
                    .foregroundStyle(accentColor)
                    .interpolationMethod(.catmullRom)
                    if let sel = selectedStressDate {
                        RuleMark(x: .value("Selected", sel))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .foregroundStyle(Color.secondary.opacity(0.5))
                    }
                }
                .chartYScale(domain: 0...100)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .hour, count: 4)) { _ in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel(format: .dateTime.hour())
                    }
                }
                .chartYAxis { AxisMarks(position: .leading) }
                .chartXSelection(value: $selectedStressDate)
                .frame(height: 160)

                Text("Daytime (8AM–8PM) heart-rate elevation above your resting baseline, with exercise excluded — so workouts don't register as stress. Matches how the daily stress score is computed.")
                    .font(.caption)
                    .foregroundColor(Color.somaGray)
            }
        }
        .padding(14)
        .background(SomaGradient.card)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.somaHairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 14, x: 0, y: 8)
        .padding(.horizontal)
    }

    private func stressLabel(for value: Double) -> String {
        switch value {
        case 70...: return "High"
        case 40..<70: return "Moderate"
        default: return "Low"
        }
    }

    // MARK: - Intraday Strain Chart

    /// Buckets raw HR samples into 30-min bins and computes zone-weighted strain load per bin.
    /// Uses the same zone model as StrainCalculator (50% maxHR threshold, zone weights 0–4).
    private var intradayStrainBuckets: [(Date, Double)] {
        guard !intradayHRData.isEmpty else { return [] }
        let maxHR = viewModel.maxHR
        let cal = Calendar.current

        // Group consecutive samples into 30-min buckets
        var buckets: [Date: [(Date, Double)]] = [:]
        for (date, hr) in intradayHRData {
            var comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            comps.minute = (comps.minute ?? 0) < 30 ? 0 : 30
            comps.second = 0
            if let bucket = cal.date(from: comps) {
                buckets[bucket, default: []].append((date, hr))
            }
        }

        return buckets
            .sorted { $0.key < $1.key }
            .compactMap { (bucketDate, samples) -> (Date, Double)? in
                guard samples.count > 1 else { return nil }
                let sorted = samples.sorted { $0.0 < $1.0 }
                var load = 0.0
                for i in 1..<sorted.count {
                    let (prevTime, prevHR) = sorted[i - 1]
                    let (currTime, currHR) = sorted[i]
                    let rawMinutes = currTime.timeIntervalSince(prevTime) / 60.0
                    guard rawMinutes > 0 else { continue }
                    let minutes = min(rawMinutes, 1.0)
                    let avgHR = (prevHR + currHR) / 2.0
                    guard avgHR >= 0.5 * maxHR else { continue }
                    let zone = HeartRateZone.zone(for: avgHR, maxHR: maxHR)
                    load += minutes * zone.weight
                }
                return load > 0 ? (bucketDate, load) : nil
            }
    }

    private var intradayStrainChart: some View {
        let strainColor = DashboardMetric.strain.accentColor
        let dayLabel = Calendar.current.isDateInToday(intradayDate) ? "Today" : intradayDate.formatted(.dateTime.month(.abbreviated).day())
        let buckets = intradayStrainBuckets

        let selectedBucket: (Date, Double)? = selectedStrainDate.flatMap { sel in
            buckets.min { abs($0.0.timeIntervalSince(sel)) < abs($1.0.timeIntervalSince(sel)) }
        }

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(dayLabel)'s Strain Pattern")
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
                if let (date, load) = selectedBucket {
                    Text("\(date.formatted(.dateTime.hour().minute())) · Load \(String(format: "%.1f", load))")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.somaCardElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            }

            if buckets.isEmpty {
                Text("No heart rate data available for \(dayLabel.lowercased()).")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 32)
            } else {
                Chart(buckets, id: \.0) { date, load in
                    BarMark(
                        x: .value("Time", date, unit: .minute),
                        y: .value("Load", load),
                        width: .fixed(6)
                    )
                    .foregroundStyle(strainColor.gradient)
                    .cornerRadius(2)
                    if let sel = selectedStrainDate {
                        RuleMark(x: .value("Selected", sel))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .foregroundStyle(Color.secondary.opacity(0.5))
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .hour, count: 4)) { _ in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel(format: .dateTime.hour())
                    }
                }
                .chartYAxis { AxisMarks(position: .leading) }
                .chartXSelection(value: $selectedStrainDate)
                .frame(height: 160)

                Text("Zone-weighted strain load per 30-min window. Only HR above 50% of your max contributes.")
                    .font(.caption)
                    .foregroundColor(Color.somaGray)
            }
        }
        .padding(14)
        .background(SomaGradient.card)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.somaHairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 14, x: 0, y: 8)
        .padding(.horizontal)
    }

    // MARK: - Workout Zone Breakdown (2.4)

    private func workoutZoneChart(_ zones: [WorkoutZoneBreakdown]) -> some View {
        let zoneColors: [(Color, String)] = [
            (Color.somaGray, "Z1"),
            (Color.somaBlue, "Z2"),
            (Color.somaGreen, "Z3"),
            (Color.somaYellow, "Z4"),
            (Color.somaRed, "Z5"),
        ]
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .foregroundColor(DashboardMetric.strain.accentColor)
                Text("Workout Zone Breakdown")
                    .font(.headline)
                    .foregroundColor(.primary)
            }

            ForEach(zones) { workout in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(workout.activityName)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        Spacer()
                        Text(String(format: "%.0f min total", workout.totalZoneMinutes))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    // Horizontal stacked bar
                    let totalMins = max(workout.totalZoneMinutes, 1)
                    let fractions: [Double] = [
                        workout.z1Minutes / totalMins,
                        workout.z2Minutes / totalMins,
                        workout.z3Minutes / totalMins,
                        workout.z4Minutes / totalMins,
                        workout.z5Minutes / totalMins,
                    ]
                    GeometryReader { geo in
                        HStack(spacing: 2) {
                            ForEach(0..<5, id: \.self) { i in
                                if fractions[i] > 0 {
                                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                                        .fill(zoneColors[i].0)
                                        .frame(width: max(4, geo.size.width * fractions[i]))
                                }
                            }
                        }
                    }
                    .frame(height: 12)
                    // Zone legend
                    HStack(spacing: 10) {
                        ForEach(0..<5, id: \.self) { i in
                            let mins = [workout.z1Minutes, workout.z2Minutes, workout.z3Minutes,
                                        workout.z4Minutes, workout.z5Minutes][i]
                            if mins > 0 {
                                HStack(spacing: 3) {
                                    Circle().fill(zoneColors[i].0).frame(width: 6, height: 6)
                                    Text("\(zoneColors[i].1): \(String(format: "%.0f", mins))m")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
                if zones.last?.id != workout.id {
                    Divider()
                }
            }
        }
        .padding(14)
        .background(SomaGradient.card)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.somaHairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 14, x: 0, y: 8)
        .padding(.horizontal)
    }

    // MARK: - Insights Panel

    private var recoveryHRVPoints: [RecoveryHRVChartPoint] {
        let ordered = history.sorted { $0.date < $1.date }
        var segment = 0

        return ordered.compactMap { metrics in
            guard let value = metrics.sleepingHRV else {
                segment += 1
                return nil
            }
            let prior = BaselineCalculator.priorMetrics(from: analysisHistory, before: metrics.date)
            let priorValues = BaselineCalculator.extractHistory(from: prior, \.sleepingHRV).map { $0.1 }
            let stats = BaselineCalculator.logHRVStats(values: priorValues)
            return RecoveryHRVChartPoint(
                date: metrics.date,
                value: value,
                segment: segment,
                baseline: stats.map { Foundation.exp($0.meanLn) },
                lowerBand: stats.map { Foundation.exp($0.meanLn - $0.sdLn) },
                upperBand: stats.map { Foundation.exp($0.meanLn + $0.sdLn) }
            )
        }
    }

    private var missingRecoveryHRVDates: [Date] {
        history.filter { $0.sleepingHRV == nil }.map { $0.date }
    }

    private var scoreVersionBoundaries: [ScoreVersionBoundary] {
        let ordered = history.sorted { $0.date < $1.date }
        guard ordered.count > 1 else { return [] }
        return ordered.indices.dropFirst().compactMap { index in
            let previous = ordered[index - 1].scoreAlgorithmVersion
            guard let current = ordered[index].scoreAlgorithmVersion,
                  current != previous else { return nil }
            return ScoreVersionBoundary(date: ordered[index].date, version: current)
        }
    }

    private var recoveryHRVChart: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "waveform.path.ecg")
                    .foregroundStyle(Color.somaGreen)
                Text("Overnight HRV vs Personal Range")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
            }

            if recoveryHRVPoints.isEmpty {
                Text("No overnight HRV has been recorded in this range.")
                    .font(.subheadline)
                    .foregroundStyle(Color.somaTextSecondary)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
            } else {
                Chart {
                    ForEach(recoveryHRVPoints) { point in
                        if let low = point.lowerBand, let high = point.upperBand {
                            AreaMark(
                                x: .value("Date", point.date, unit: .day),
                                yStart: .value("Lower personal range", low),
                                yEnd: .value("Upper personal range", high)
                            )
                            .foregroundStyle(Color.somaGreen.opacity(0.14))
                        }
                        if let baseline = point.baseline {
                            LineMark(
                                x: .value("Date", point.date, unit: .day),
                                y: .value("Baseline", baseline)
                            )
                            .foregroundStyle(Color.somaGray)
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        }
                        LineMark(
                            x: .value("Date", point.date, unit: .day),
                            y: .value("Overnight SDNN", point.value),
                            series: .value("Continuous observations", point.segment)
                        )
                        .foregroundStyle(Color.somaGreen)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        PointMark(
                            x: .value("Date", point.date, unit: .day),
                            y: .value("Overnight SDNN", point.value)
                        )
                        .foregroundStyle(Color.somaGreen)
                        .symbolSize(32)
                    }

                    ForEach(missingRecoveryHRVDates, id: \.self) { date in
                        RuleMark(x: .value("Missing overnight HRV", date, unit: .day))
                            .foregroundStyle(Color.somaYellow.opacity(0.45))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 4]))
                    }

                    ForEach(scoreVersionBoundaries) { boundary in
                        RuleMark(x: .value("Algorithm change", boundary.date, unit: .day))
                            .foregroundStyle(Color.somaBlue.opacity(0.75))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [6, 3]))
                            .annotation(position: .top, alignment: .leading) {
                                Text("v\(boundary.version)")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(Color.somaBlue)
                            }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: axisDayStride)) {
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel(format: axisDayFormat)
                    }
                }
                .chartYAxisLabel("SDNN (ms)")
                .frame(height: 220)
            }

            HStack(spacing: 14) {
                chartLegend(color: Color.somaGreen, label: "Overnight median")
                chartLegend(color: Color.somaGreen.opacity(0.3), label: "Personal range")
                chartLegend(color: Color.somaYellow, label: "Missing")
            }
            Text("The personal range is the prior-night log-domain baseline ± one personal standard deviation. It appears after seven recorded nights.")
                .font(.caption2)
                .foregroundStyle(Color.somaTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(SomaGradient.card)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.somaHairline, lineWidth: 1))
        .padding(.horizontal)
    }

    private func chartLegend(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).font(.caption2).foregroundStyle(Color.somaTextSecondary)
        }
    }

    private func recoveryDataQualityPanel(for metrics: DailyMetrics) -> some View {
        let prior = BaselineCalculator.priorMetrics(from: analysisHistory, before: metrics.date)
        let priorHRV = BaselineCalculator.extractHistory(from: prior, \.sleepingHRV).map { $0.1 }
        let baseline = BaselineCalculator.computePersonalBaseline(from: priorHRV)
        let coverage = metrics.recoveryDataCoverage.map { Int(($0 * 100).rounded()) }
        let confidence = metrics.recoveryConfidence?.rawValue.capitalized ?? "Unknown"

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "waveform.path.ecg.rectangle")
                    .foregroundStyle(Color.somaGreen)
                Text("Recovery Data Quality")
                    .font(.headline)
                    .foregroundStyle(.primary)
            }

            recoveryDataRow(
                label: "Overnight HRV",
                value: metrics.sleepingHRV.map { String(format: "%.0f ms", $0) } ?? "Not recorded"
            )
            recoveryDataRow(
                label: "Prior-night baseline",
                value: baseline.map { String(format: "%.0f ms", $0) } ?? "Building"
            )
            recoveryDataRow(
                label: "Baseline nights",
                value: "\(priorHRV.count) / \(BaselineCalculator.minDaysRequired) minimum"
            )
            recoveryDataRow(
                label: "HRV samples returned",
                value: metrics.sleepingHRVProvenance.map { "\($0.sampleCount)" } ?? "Not captured"
            )
            if let retained = metrics.sleepingHRVProvenance?.retainedSampleCount {
                recoveryDataRow(label: "Samples used", value: "\(retained)")
            }
            if let duplicates = metrics.sleepingHRVProvenance?.duplicateSampleCount, duplicates > 0 {
                recoveryDataRow(label: "Duplicates collapsed", value: "\(duplicates)")
            }
            recoveryDataRow(
                label: "Source app",
                value: provenanceList(metrics.sleepingHRVProvenance?.sourceNames)
            )
            recoveryDataRow(
                label: "Source device",
                value: provenanceList(metrics.sleepingHRVProvenance?.deviceNames)
            )
            recoveryDataRow(
                label: "Latest sample",
                value: metrics.sleepingHRVProvenance?.latestSampleDate?.formatted(date: .abbreviated, time: .shortened) ?? "Not captured"
            )
            recoveryDataRow(
                label: "Input coverage",
                value: coverage.map { "\($0)%" } ?? "Unknown"
            )
            recoveryDataRow(label: "Confidence", value: confidence)

            if let sources = metrics.sleepingHRVProvenance?.sourceNames, sources.count > 1 {
                Label(
                    "Multiple HealthKit sources contributed. Simultaneous observations were collapsed, but Soma did not automatically discard an entire source.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(Color.somaYellow)
                .fixedSize(horizontal: false, vertical: true)
            }

            Text("Apple Health SDNN · median of sleep-window samples · daytime HRV is not substituted. This is a wellness estimate, not a medical measurement.")
                .font(.caption)
                .foregroundStyle(Color.somaTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accentCard(Color.somaGreen, cornerRadius: 20, padding: 16)
        .padding(.horizontal)
    }

    private func recoveryDataRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Color.somaTextSecondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func provenanceList(_ values: [String]?) -> String {
        guard let values, !values.isEmpty else { return "Not reported" }
        return values.joined(separator: ", ")
    }

    private func insightsPanel(for m: DailyMetrics) -> some View {
        let score = Int(metric.score(from: m).rounded())
        let state = metric.state(from: m)
        let result = MetricInsightGenerator.generate(for: metric, metrics: m, sleepGoal: sleepGoal, history: analysisHistory)
        let acrHistory = BaselineCalculator.priorMetrics(from: analysisHistory, before: m.date)
        let acrNote = metric == .recovery ? MetricInsightGenerator.acrDescription(history: acrHistory) : nil

        return VStack(alignment: .leading, spacing: 14) {
            // Header — tinted to the metric's current state color so the insight card
            // reads as part of the metric, not a generic yellow note.
            HStack(spacing: 10) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(state.color)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(state.color.opacity(0.16)))
                Text("\(metric.title) Score: \(score) — \(state.label)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
            }

            // ACR sub-row for recovery (2.3)
            if let acr = acrNote {
                HStack(spacing: 6) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.caption)
                        .foregroundColor(Color.somaOrange)
                    Text(acr)
                        .font(.caption)
                        .foregroundColor(Color.somaOrange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 8).padding(.vertical, 6)
                .background(Color.somaOrange.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            if !result.observations.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Observations")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(Color.somaGray)
                        .textCase(.uppercase)
                    ForEach(result.observations, id: \.self) { obs in
                        HStack(alignment: .top, spacing: 8) {
                            Circle()
                                .fill(state.color)
                                .frame(width: 5, height: 5)
                                .padding(.top, 6)
                            Text(obs)
                                .font(.subheadline)
                                .foregroundColor(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            if !result.actions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Suggested Actions")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(Color.somaGray)
                        .textCase(.uppercase)
                    ForEach(result.actions, id: \.self) { action in
                        HStack(alignment: .top, spacing: 8) {
                            Circle()
                                .fill(Color.somaBlue)
                                .frame(width: 5, height: 5)
                                .padding(.top, 6)
                            Text(action)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accentCard(state.color, cornerRadius: 20, padding: 16)
        .padding(.horizontal)
    }

    // MARK: - Stats Row

    private var statsRow: some View {
        HStack(spacing: 12) {
            statPill(label: "Avg", value: avgScore)
            statPill(label: "Peak", value: peakScore)
            statPill(label: "Low", value: lowScore)
        }
        .padding(.horizontal)
    }

    private func statPill(label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            Text(label)
                .font(.caption2)
                .foregroundColor(Color.somaGray)
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(SomaGradient.card)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.somaHairline, lineWidth: 1))
    }

    // MARK: - Sleep Regularity Dashboard (3.2)

    /// All sleep metrics from the past 30 days (independent of the range picker — regularity is a long-term metric).
    private var last30History: [DailyMetrics] { viewModel.loadHistory(days: 30) }

    /// Last 7 days of sleep-vs-goal data for WeeklyGoalCard.
    private var weeklyGoalHistory: [(date: Date, actual: Double, goal: Double)] {
        let stored = UserDefaults.standard.double(forKey: UserDefaultsKeys.baselineSleepHours)
        let defaultGoal = stored > 0 ? stored : 7.0
        return viewModel.loadHistory(days: 7).compactMap { m in
            guard let actual = m.sleepDurationHours else { return nil }
            let goal = m.sleepNeedHours ?? defaultGoal
            return (date: m.date, actual: actual, goal: goal)
        }
    }

    // MARK: Sleep Regularity Index

    private var sleepRegularityIndex: Double? {
        let times = last30History.compactMap { $0.sleepStartTime }
        guard times.count >= 5 else { return nil }

        let cal = Calendar.current
        // Convert sleep start times to minutes-since-noon (normalises across midnight).
        // Using noon as pivot: PM times are positive, AM times (next day) get +24h offset.
        let minutesFromNoon: [Double] = times.map { t in
            let comps = cal.dateComponents([.hour, .minute], from: t)
            var min = Double((comps.hour ?? 0) * 60 + (comps.minute ?? 0))
            // Times before 10 AM are almost certainly "after midnight" — shift +24h.
            if min < 10 * 60 { min += 24 * 60 }
            // Pivot around noon (720 min) so signed distance is meaningful.
            return min - 12 * 60
        }

        let sorted = minutesFromNoon.sorted()
        let median = sorted[sorted.count / 2]

        let within30 = minutesFromNoon.filter { abs($0 - median) <= 30 }.count
        return Double(within30) / Double(minutesFromNoon.count) * 100
    }

    private var sleepRegularityPanel: some View {
        let sri = sleepRegularityIndex
        let accentColor = sleepRegularityColor(sri)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.clock")
                    .foregroundColor(accentColor)
                Text("Sleep Regularity")
                    .font(.headline)
                    .foregroundColor(.primary)
            }

            HStack(alignment: .bottom, spacing: 4) {
                if let s = sri {
                    Text("\(Int(s.rounded()))%")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundColor(accentColor)
                } else {
                    Text("--")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundColor(.secondary)
                }
                Text("nights within 30 min of your median bedtime")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 6)
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(accentColor.opacity(0.12))
                    Capsule().fill(accentColor)
                        .frame(width: geo.size.width * min(1, (sri ?? 0) / 100))
                        .animation(.easeOut(duration: 1.0), value: sri)
                }
            }
            .frame(height: 8)

            Text(sleepRegularityCaption(sri))
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(SomaGradient.card)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.somaHairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 14, x: 0, y: 8)
        .padding(.horizontal)
    }

    private func sleepRegularityColor(_ sri: Double?) -> Color {
        // Full red → orange → yellow → light green → green scale.
        guard let s = sri else { return Color.somaGray }
        if s >= 85 { return Color.somaGreen }
        if s >= 70 { return Color.somaLightGreen }
        if s >= 55 { return Color.somaYellow }
        if s >= 40 { return Color.somaOrange }
        return Color.somaRed
    }

    private func sleepRegularityCaption(_ sri: Double?) -> String {
        guard let s = sri else { return "Need at least 5 nights of data to compute regularity." }
        if s >= 85 { return "Excellent — consistent sleep timing strengthens your circadian rhythm and improves deep-sleep architecture." }
        if s >= 70 { return "Good — minor variation in your sleep schedule. Keeping bedtime within 30 min on weekends has the biggest impact." }
        if s >= 55 { return "Moderate — your sleep timing drifts night to night. Aim for a fixed bedtime ± 30 min." }
        return "High variability in sleep timing can suppress melatonin and reduce sleep quality. Aim for a fixed bedtime ± 30 min."
    }

    // MARK: 30-Day Sleep Debt Chart

    private var sleepDebtData: [(Date, Double)] {
        last30History.compactMap { m -> (Date, Double)? in
            guard let actual = m.sleepDurationHours else { return nil }
            // Use the fixed sleep goal — not sleepNeedHours, which already bakes in prior
            // debt and would compound when used to compute debt again.
            return (m.date, max(0, sleepGoal - actual))
        }
        .sorted { $0.0 < $1.0 }
    }

    private var sleepDebtChart: some View {
        let data = sleepDebtData
        let totalDebt = data.map { $0.1 }.reduce(0, +)
        let maxDebt = data.map { $0.1 }.max() ?? 1
        let accentColor = Color.somaBlue

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "zzz")
                    .foregroundColor(accentColor)
                Text("30-Day Sleep Debt")
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(formatHoursShort(totalDebt))
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(totalDebt > 7 ? Color.somaOrange : accentColor)
                    Text("cumulative debt")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            if data.isEmpty {
                Text("No sleep data available for the past 30 days.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
            } else {
                Chart(data, id: \.0) { date, debt in
                    BarMark(
                        x: .value("Date", date, unit: .day),
                        y: .value("Debt (h)", debt)
                    )
                    .foregroundStyle(debtBarColor(debt, max: maxDebt).gradient)
                    .cornerRadius(3)
                }
                .chartYScale(domain: 0...(max(maxDebt + 0.5, 2.0)))
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { val in
                        AxisGridLine()
                        AxisValueLabel {
                            if let v = val.as(Double.self) {
                                Text("\(String(format: "%.0f", v))h")
                                    .font(.system(size: 10))
                            }
                        }
                    }
                }
                .frame(height: 140)

                Text("Daily sleep debt = your personalised sleep need minus actual sleep. Zero is ideal.")
                    .font(.caption)
                    .foregroundColor(Color.somaGray)
            }
        }
        .padding(14)
        .background(SomaGradient.card)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.somaHairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 14, x: 0, y: 8)
        .padding(.horizontal)
    }

    private func debtBarColor(_ debt: Double, max maxDebt: Double) -> Color {
        // Full red → orange → yellow → light green → green scale.
        if debt <= 0.25 { return Color.somaGreen }
        if debt <= 0.75 { return Color.somaLightGreen }
        if debt <= 1.5  { return Color.somaYellow }
        if debt <= 2.5  { return Color.somaOrange }
        return Color.somaRed
    }

    private func formatHoursShort(_ h: Double) -> String {
        let total = Int((h * 60).rounded())
        let hrs = total / 60; let mins = total % 60
        if hrs == 0  { return "\(mins)m" }
        if mins == 0 { return "\(hrs)h" }
        return "\(hrs)h \(mins)m"
    }

    // MARK: GitHub-Style Sleep Score Calendar Grid

    /// Builds a 6-week (42-cell) grid aligned to calendar weeks.
    /// Each row is a week starting on Sunday. The last row is always the current week,
    /// so today is always visible. Future cells in the current week are shown as empty.
    private var calendarGridData: [Date?] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        // Anchor to the Sunday of the current week, then go back 5 full weeks.
        // This guarantees today always falls within the 42-cell grid.
        let weekdayOfToday = cal.component(.weekday, from: today) // 1=Sun … 7=Sat
        let offsetToSunday = weekdayOfToday - 1
        guard let sundayOfCurrentWeek = cal.date(byAdding: .day, value: -offsetToSunday, to: today),
              let gridStart = cal.date(byAdding: .day, value: -35, to: sundayOfCurrentWeek) else { return [] }

        // 6 rows × 7 columns = 42 cells
        return (0..<42).map { offset -> Date? in
            guard let date = cal.date(byAdding: .day, value: offset, to: gridStart) else { return nil }
            if date > today { return nil }   // future cells in the current week: empty
            return date
        }
    }

    private var sleepCalendarGrid: some View {
        let cells     = calendarGridData                             // 42 elements, nil = empty
        let dayLabels = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let accentColor = DashboardMetric.sleep.accentColor
        let cal       = Calendar.current
        let history   = viewModel.loadHistory(days: 45)             // 6 weeks needs up to 45 days

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .foregroundColor(accentColor)
                Text("Sleep Score Calendar")
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
                // Legend — Poor → Fair → Good → Great (red → yellow → light green → green)
                HStack(spacing: 6) {
                    ForEach(["Poor", "Fair", "Good", "Great"], id: \.self) { label in
                        HStack(spacing: 3) {
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(calendarLegendColor(label))
                                .frame(width: 10, height: 10)
                            Text(label)
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            // Day-of-week header
            HStack(spacing: 4) {
                ForEach(dayLabels, id: \.self) { day in
                    Text(day)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            // 6 rows × 7 columns
            VStack(spacing: 4) {
                ForEach(0..<6, id: \.self) { row in
                    HStack(spacing: 4) {
                        ForEach(0..<7, id: \.self) { col in
                            let idx = row * 7 + col
                            if idx < cells.count, let date = cells[idx] {
                                let entry = history.first { cal.isDate($0.date, inSameDayAs: date) }
                                let score: Double? = {
                                    guard let m = entry else { return nil }
                                    if m.sleepScore > 5 { return m.sleepScore }
                                    // Fall back to a duration-based proxy so cells show even when
                                    // the full score wasn't computed (e.g. older backfilled data).
                                    if let h = m.sleepDurationHours, h > 0.5 {
                                        let goal = m.sleepNeedHours ?? 7.5
                                        return min(100, max(5, h / goal * 75))
                                    }
                                    return m.sleepScore > 0 ? m.sleepScore : nil
                                }()
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(calendarCellColor(score))
                                    .frame(maxWidth: .infinity)
                                    .aspectRatio(1, contentMode: .fit)
                                    .overlay(
                                        Group {
                                            if let s = score {
                                                Text("\(Int(s.rounded()))")
                                                    .font(.system(size: 8, weight: .semibold))
                                                    .foregroundColor(.white.opacity(0.9))
                                            }
                                        }
                                    )
                            } else {
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(Color.secondary.opacity(0.05))
                                    .frame(maxWidth: .infinity)
                                    .aspectRatio(1, contentMode: .fit)
                            }
                        }
                    }
                }
            }

            Text("Each cell shows your sleep score for that night. Last 6 weeks, aligned to calendar weeks.")
                .font(.caption)
                .foregroundColor(Color.somaGray)
        }
        .padding(14)
        .background(SomaGradient.card)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.somaHairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 14, x: 0, y: 8)
        .padding(.horizontal)
    }

    private func calendarCellColor(_ score: Double?) -> Color {
        // Mirrors the sleep ColorState bands: red → orange → yellow → light green → green.
        guard let s = score else { return Color.white.opacity(0.06) }
        if s >= 90 { return Color.somaGreen }
        if s >= 75 { return Color.somaLightGreen }
        if s >= 60 { return Color.somaYellow }
        if s >= 40 { return Color.somaOrange }
        return Color.somaRed
    }

    private func calendarLegendColor(_ label: String) -> Color {
        switch label {
        case "Great": return Color.somaGreen
        case "Good":  return Color.somaLightGreen
        case "Fair":  return Color.somaYellow
        case "Poor":  return Color.somaOrange
        default:      return Color.white.opacity(0.06)
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private var tooltipView: some View {
        if let date = selectedDate {
            let nearest = history.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
            if let m = nearest {
                let score = Int(metric.score(from: m).rounded())
                let state = metric.state(from: m)
                let dateStr = m.date.formatted(.dateTime.month(.abbreviated).day())
                (
                    Text("\(dateStr) · \(score) — ")
                    + Text(state.label).foregroundColor(state.color)
                )
                .font(.caption)
                .fontWeight(.semibold)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.somaCardElevated)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
    }

    private func isSelected(_ date: Date) -> Bool {
        guard let sel = selectedDate else { return false }
        return Calendar.current.isDate(date, inSameDayAs: sel)
    }

    private var avgScore: String {
        guard !history.isEmpty else { return "--" }
        let avg = history.map { metric.score(from: $0) }.reduce(0, +) / Double(history.count)
        return String(format: "%.0f", avg)
    }

    private var peakScore: String {
        guard !history.isEmpty else { return "--" }
        return String(format: "%.0f", history.map { metric.score(from: $0) }.max() ?? 0)
    }

    private var lowScore: String {
        guard !history.isEmpty else { return "--" }
        return String(format: "%.0f", history.map { metric.score(from: $0) }.min() ?? 0)
    }

    private var axisDayStride: Int {
        switch selectedRange {
        case .week:      return 1
        case .twoWeeks:  return 2
        case .month:     return 5
        case .sixMonths: return 20
        case .year:      return 45
        }
    }

    private var axisDayFormat: Date.FormatStyle {
        switch selectedRange {
        case .week, .twoWeeks, .month:
            return .dateTime.month(.abbreviated).day()
        case .sixMonths, .year:
            return .dateTime.month(.abbreviated).year(.twoDigits)
        }
    }
}

#if DEBUG
#Preview("Recovery") {
    NavigationStack {
        MetricDetailView(metric: .recovery, viewModel: .preview)
    }
}

#Preview("Sleep") {
    NavigationStack {
        MetricDetailView(metric: .sleep, viewModel: .preview)
    }
}

#Preview("Strain") {
    NavigationStack {
        MetricDetailView(metric: .strain, viewModel: .preview)
    }
}

#Preview("Stress") {
    NavigationStack {
        MetricDetailView(metric: .stress, viewModel: .preview)
    }
}
#endif
