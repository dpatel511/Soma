import SwiftUI

// MARK: - TODAY TAB
// "How am I today, and what should I do?" — the daily operating system.
// Hero readiness → Why → Today's Plan → Key Signals → Supporting Scores → Alert Center.

struct TodayView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @ObservedObject var insightsVM: InsightsViewModel
    let checkInStore: CheckInStore
    let healthKit: HealthDataProviding

    @AppStorage(UserDefaultsKeys.userFirstName) private var firstName: String = ""

    @State private var activeMetric: DashboardMetric?
    @State private var showSettings = false
    @State private var showCheckIn = false
    @State private var showReadinessDetail = false
    @State private var expandedInsight: UUID?

    private var metrics: DailyMetrics { viewModel.todayMetrics }

    private var readiness: Double {
        viewModel.trainingGuidance?.readinessScore ?? metrics.recoveryScore
    }
    private var readinessState: ColorState { ColorState.recovery(score: readiness) }
    private var readinessDataCoverage: Double? {
        let values = [metrics.recoveryDataCoverage, metrics.sleepDataCoverage].compactMap { $0 }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                SomaGradient.canvas(tint: readinessState.color)

                ScrollView {
                    VStack(spacing: Space.lg) {
                        heroCard
                        contributorsSection
                        if let guidance = viewModel.trainingGuidance {
                            planSection(guidance)
                        }
                        baselineSignalsSection
                        scoresSection
                        sleepBalanceCard
                        alertCenterSection
                        Color.clear.frame(height: 12)
                    }
                    .padding(.horizontal, Space.md)
                    .padding(.top, Space.sm)
                }
                .scrollIndicators(.hidden)
                .refreshable { await viewModel.refresh(force: true)?.value }

                if viewModel.isLoading && metrics.recoveryScore == 0 {
                    ProgressView().tint(.white)
                }
            }
            .navigationTitle(firstName.isEmpty ? "Today" : "Hi, \(firstName)")
            .navigationBarTitleDisplayMode(.large)
            .toolbar { toolbarContent }
            .sheet(item: $activeMetric) { MetricDetailView(metric: $0, viewModel: viewModel) }
            .sheet(isPresented: $showReadinessDetail) {
                if let guidance = viewModel.trainingGuidance {
                    ReadinessDetailView(guidance: guidance, viewModel: viewModel)
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showCheckIn) {
                CheckInView(viewModel: CheckInViewModel(checkInStore: checkInStore, healthKit: healthKit))
            }
        }
        .onAppear {
            viewModel.loadCached()
            viewModel.refresh(force: true)
            insightsVM.generateInsights()
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 16) {
                if !checkInStore.hasCompletedToday() {
                    Button { Haptics.tap(); showCheckIn = true } label: {
                        Image(systemName: "checkmark.circle").foregroundStyle(Color.somaGreen)
                    }
                }
                Button { Haptics.tap(); showSettings = true } label: {
                    Image(systemName: "gearshape").foregroundStyle(Color.somaTextSecondary)
                }
            }
        }
    }

    // MARK: 1 — Hero

    /// The readiness hero opens the full Readiness breakdown popup when training
    /// guidance is available (it carries the factors the detail view needs).
    @ViewBuilder
    private var heroCard: some View {
        if viewModel.trainingGuidance != nil {
            Button {
                Haptics.tap()
                showReadinessDetail = true
            } label: {
                heroSection
            }
            .buttonStyle(.plain)
        } else {
            heroSection
        }
    }

    private var heroSection: some View {
        VStack(spacing: 14) {
            // Tap affordance — signals the hero opens the detailed breakdown.
            if viewModel.trainingGuidance != nil {
                HStack(spacing: 4) {
                    Spacer()
                    Text("DETAILS").eyebrow()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.somaTextTertiary)
                }
            }

            ReadinessRing(
                score: readiness,
                title: "READINESS",
                stateLabel: readinessState.label,
                color: readinessState.color,
                size: 150,
                lineWidth: 13
            )

            Text(headline)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.somaTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Space.sm)
                .padding(.top, 8)

            if let coverage = readinessDataCoverage {
                Text("DATA COVERAGE · \(Int((coverage * 100).rounded()))%")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .tracking(1.0)
                    .foregroundStyle(coverage >= 0.75 ? Color.somaTextTertiary : Color.somaYellow)
                    .accessibilityLabel("Readiness data coverage \(Int((coverage * 100).rounded())) percent")
            }

            Divider().overlay(Color.somaHairline)
                .padding(.top, 2)

            // Contributors — the supporting scores behind today's readiness.
            HStack(spacing: 0) {
                heroCell("Recovery", Int(metrics.recoveryScore), readinessState.color)
                heroDivider
                heroCell("Sleep", Int(metrics.sleepScore), .somaBlue)
                heroDivider
                heroCell("HRV", metrics.hrvAverage.map { Int($0) }, .somaPurple)
                heroDivider
                heroCell("RHR", metrics.restingHR.map { Int($0) }, .somaOrange)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.md)
        .premiumCard(cornerRadius: Radius.xl, padding: Space.md, glow: readinessState.color)
    }

    private func heroCell(_ label: String, _ value: Int?, _ color: Color) -> some View {
        VStack(spacing: 3) {
            Text(value.map(String.init) ?? "—")
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.somaTextTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private var heroDivider: some View {
        Rectangle().fill(Color.somaHairline).frame(width: 1, height: 28)
    }

    private var headline: String {
        switch readiness {
        case 80...100: return "Recent signals are favorable. Train to how you feel."
        case 65..<80:  return "Signals support training if energy and soreness agree."
        case 45..<65:  return "Mixed signals today. Consider a steady session."
        case 25..<45:  return "Several signals are below baseline. Consider keeping it light."
        default:       return "Recovery signals are low. Consider rest and extra sleep."
        }
    }

    // MARK: 1.5 — Sleep Balance
    // Last night vs. today's *debt-adjusted* goal. `sleepNeedHours` already folds
    // in the rolling 3-night debt + strain (see SleepCalculator.calculateSleepNeed),
    // so closing this gap is exactly "hit my goal and pay down the debt."

    @ViewBuilder
    private var sleepBalanceCard: some View {
        if let slept = metrics.sleepDurationHours, slept > 0 {
            // Goal shown = the HIGHER of your set goal and the debt-adjusted need.
            // `sleepNeedHours` folds in the rolling 3-night debt + strain (see
            // SleepCalculator.calculateSleepNeed). When you're carrying debt from the
            // last 3 nights the goal rises to pay it down; once those nights age out
            // the need drops back to the set goal and the cycle repeats.
            let setGoal = metrics.sleepGoalHours ?? metrics.sleepNeedHours ?? 8.0
            let need = metrics.sleepNeedHours ?? setGoal
            let goal = max(setGoal, need)
            let isDebtAdjusted = goal > setGoal + 0.01   // raised by 3-night debt
            let fraction = min(1.0, slept / max(goal, 0.1))
            let gap = goal - slept                 // > 0 → still short of goal
            let isShort = gap > 0.05
            let accent = Color.somaBlue
            let deltaColor = isShort ? Color.somaOrange : Color.somaGreen

            Button { Haptics.tap(); activeMetric = .sleep } label: {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("LAST NIGHT'S SLEEP").eyebrow()
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(formatHours(slept))
                                    .font(.system(size: 30, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                Text("/ \(formatHours(goal)) goal")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(Color.somaTextSecondary)
                                if isDebtAdjusted {
                                    Text("3-NIGHT DEBT")
                                        .font(.system(size: 9, weight: .heavy))
                                        .tracking(0.5)
                                        .foregroundStyle(Color.somaOrange)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Capsule().fill(Color.somaOrange.opacity(0.16)))
                                }
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Color.somaTextTertiary)
                    }

                    // Progress toward the debt-adjusted goal.
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.08)).frame(height: 8)
                            Capsule()
                                .fill(LinearGradient(colors: [accent.opacity(0.55), accent],
                                                     startPoint: .leading, endPoint: .trailing))
                                .frame(width: max(8, geo.size.width * fraction), height: 8)
                        }
                    }
                    .frame(height: 8)

                    HStack(spacing: 6) {
                        Image(systemName: isShort ? "moon.zzz.fill" : "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(deltaColor)
                        Text(sleepDeltaText(gap: gap))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(deltaColor)
                    }

                    // Tonight's target: bedtime that delivers the full debt-adjusted
                    // need by the user's wake time. Debt only spans the last 3 nights.
                    if let bedtime = viewModel.bedtimeTarget {
                        Divider().overlay(Color.somaHairline).padding(.vertical, 2)
                        HStack(spacing: 11) {
                            Image(systemName: "bed.double.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(accent)
                                .frame(width: 32, height: 32)
                                .background(Circle().fill(accent.opacity(0.16)))
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 5) {
                                    Text("Sleep by")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(Color.somaTextSecondary)
                                    Text(bedtime, format: .dateTime.hour().minute())
                                        .font(.system(size: 17, weight: .bold, design: .rounded))
                                        .foregroundStyle(.white)
                                    Text("tonight")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(Color.somaTextSecondary)
                                }
                                Text(isShort
                                     ? "Clears debt from your last 3 nights"
                                     : "Keeps you rested through your next wake-up")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.somaTextTertiary)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            .accentCard(accent, cornerRadius: Radius.lg)
        }
    }

    private func sleepDeltaText(gap: Double) -> String {
        if gap > 0.05 {
            return "\(formatHours(gap)) under your sleep goal"
        }
        let over = -gap
        if over < 0.05 { return "Goal met — fully rested" }
        return "Goal met · \(formatHours(over)) to spare"
    }

    private func formatHours(_ h: Double) -> String {
        let total = Int((h * 60).rounded())
        let hrs = total / 60, mins = total % 60
        if hrs == 0 { return "\(mins)m" }
        if mins == 0 { return "\(hrs)h" }
        return "\(hrs)h \(mins)m"
    }

    // MARK: 2 — Why (contributors)

    private var contributorsSection: some View {
        let drivers = topDrivers()
        return VStack(alignment: .leading, spacing: Space.sm) {
            SectionHeader(title: "Why")
            if drivers.isEmpty {
                Text("Wear your Apple Watch overnight to unlock today's drivers.")
                    .font(.footnote)
                    .foregroundStyle(Color.somaTextSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .premiumCard(cornerRadius: Radius.md, padding: 14)
            } else {
                ForEach(drivers) { insight in
                    contributorRow(insight)
                }
            }
        }
    }

    private func contributorRow(_ insight: Insight) -> some View {
        let color = colorFor(priorityName: insight.priority.colorStateName)
        let isOpen = expandedInsight == insight.id
        return Button {
            Haptics.tap()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                expandedInsight = isOpen ? nil : insight.id
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Image(systemName: insight.icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(color)
                        .frame(width: 34, height: 34)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(color.opacity(0.16)))
                    Text(insight.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.somaTextTertiary)
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                }
                if isOpen {
                    Text(insight.description)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.somaTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .buttonStyle(.plain)
        .accentCard(color, cornerRadius: Radius.md, padding: 14)
    }

    // MARK: 3 — Today's Plan

    private func planSection(_ g: DailyTrainingGuidance) -> some View {
        let accent = Color(hex: g.activityLevel.colorHex)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 11) {
                Image(systemName: g.activityLevel.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(accent.opacity(0.16)))
                VStack(alignment: .leading, spacing: 1) {
                    Text("TODAY'S PLAN").eyebrow()
                    Text(g.activityLevel.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                }
                Spacer()
                if g.targetStrainMax > 0 {
                    HStack(spacing: 5) {
                        Image(systemName: "target").font(.system(size: 11, weight: .bold)).foregroundStyle(accent)
                        Text("\(g.targetStrainMin)–\(g.targetStrainMax)")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Capsule().fill(accent.opacity(0.14)))
                }
            }

            if !g.suggestedWorkouts.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(g.suggestedWorkouts, id: \.self) { w in
                            Text(w)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.somaTextSecondary)
                                .padding(.horizontal, 11).padding(.vertical, 6)
                                .background(Capsule().fill(Color.white.opacity(0.06)))
                        }
                    }
                }
            }

            if !g.explanation.isEmpty {
                Text(g.explanation)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.somaTextTertiary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accentCard(accent, cornerRadius: Radius.lg)
    }

    // MARK: 4 — Baseline-relative signals

    private struct BaselineSignal: Identifiable {
        let id: String
        let icon: String
        let title: String
        let value: String
        let unit: String
        let comparison: String?
        let color: Color
        let trend: SignalTrend
    }

    @ViewBuilder
    private var baselineSignalsSection: some View {
        let cols = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        let signals = baselineSignals
        if !signals.isEmpty {
            VStack(alignment: .leading, spacing: Space.sm) {
                SectionHeader(title: "Key Signals", subtitle: "Compared with your recent personal data")
                LazyVGrid(columns: cols, spacing: 12) {
                    ForEach(signals) { signal in
                        SignalTile(
                            icon: signal.icon,
                            title: signal.title,
                            value: signal.value,
                            unit: signal.unit,
                            baseline: signal.comparison == nil ? "Calibrating" : nil,
                            deviationText: signal.comparison,
                            color: signal.color,
                            trend: signal.trend
                        )
                    }
                }
            }
        }
    }

    private var baselineSignals: [BaselineSignal] {
        let prior = viewModel.loadHistory(days: 30).filter {
            !Calendar.current.isDate($0.date, inSameDayAs: metrics.date)
        }
        var signals: [BaselineSignal] = []

        if let hrv = metrics.hrvAverage {
            let baseline = BaselineCalculator.computePersonalBaseline(
                from: prior.compactMap(\.hrvAverage).filter { $0 > 0 }
            )
            let delta = baseline.map { hrv - $0 }
            signals.append(BaselineSignal(
                id: "hrv", icon: "waveform.path.ecg", title: "HRV",
                value: String(format: "%.0f", hrv), unit: "ms",
                comparison: delta.map { signed($0, decimals: 0, unit: "ms") },
                color: .somaPurple, trend: trend(for: delta, threshold: 1)
            ))
        }

        if let rhr = metrics.restingHR {
            let baseline = BaselineCalculator.computePersonalBaseline(
                from: prior.compactMap(\.restingHR).filter { $0 > 0 }
            )
            let delta = baseline.map { rhr - $0 }
            signals.append(BaselineSignal(
                id: "rhr", icon: "heart.fill", title: "Resting HR",
                value: String(format: "%.0f", rhr), unit: "bpm",
                comparison: delta.map { signed($0, decimals: 0, unit: "bpm") },
                color: .somaOrange, trend: trend(for: delta, threshold: 1)
            ))
        }

        if let sleep = metrics.sleepDurationHours, sleep > 0 {
            let baseline = BaselineCalculator.computePersonalBaseline(
                from: prior.compactMap(\.sleepDurationHours).filter { $0 > 0 }
            )
            let delta = baseline.map { sleep - $0 }
            signals.append(BaselineSignal(
                id: "sleep-duration", icon: "moon.zzz.fill", title: "Sleep Duration",
                value: formatHours(sleep), unit: "",
                comparison: delta.map { sleepComparison($0) },
                color: .somaBlue, trend: trend(for: delta, threshold: 0.1)
            ))
        }

        if let temperature = metrics.wristTempDeviation {
            signals.append(BaselineSignal(
                id: "wrist-temperature", icon: "thermometer.medium", title: "Wrist Temp",
                value: String(format: "%+.1f", temperature), unit: "°C",
                comparison: "vs personal baseline",
                color: abs(temperature) > 0.5 ? .somaYellow : .somaGreen,
                trend: trend(for: temperature, threshold: 0.1)
            ))
        }

        return signals
    }

    private func signed(_ value: Double, decimals: Int, unit: String) -> String {
        let formatted = String(format: "%+.*f", decimals, value)
        return "\(formatted) \(unit) vs personal avg"
    }

    private func sleepComparison(_ delta: Double) -> String {
        let minutes = Int((delta * 60).rounded())
        return "\(minutes >= 0 ? "+" : "")\(minutes) min vs personal avg"
    }

    private func trend(for delta: Double?, threshold: Double) -> SignalTrend {
        guard let delta else { return .flat }
        if delta > threshold { return .up }
        if delta < -threshold { return .down }
        return .flat
    }

    private func trend(for value: Double, threshold: Double) -> SignalTrend {
        if value > threshold { return .up }
        if value < -threshold { return .down }
        return .flat
    }

    // MARK: 5 — Supporting scores

    private var scoresSection: some View {
        let cols = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        return VStack(alignment: .leading, spacing: Space.sm) {
            SectionHeader(title: "Supporting Scores")
            LazyVGrid(columns: cols, spacing: 12) {
                coreTile(.recovery)
                coreTile(.sleep)
                coreTile(.strain)
                coreTile(.stress)
            }
        }
    }

    /// One of the four core Whoop-style 0–100 scores, tappable to its detail.
    private func coreTile(_ m: DashboardMetric) -> some View {
        let score = m.score(from: metrics)
        let state = m.state(from: metrics)
        let hasSufficientData = m.dataCoverage(from: metrics).map { $0 >= 0.5 } ?? true
        return Button { Haptics.tap(); activeMetric = m } label: {
            SignalTile(
                icon: m.systemImage, title: m.title,
                value: hasSufficientData ? "\(Int(score.rounded()))" : "—", unit: "",
                baseline: hasSufficientData ? state.label : "Low data",
                deviationText: nil, color: state.color,
                trend: hasSufficientData ? coreTrend(m) : .flat
            )
        }
        .buttonStyle(.plain)
    }

    /// Direction of the latest score vs. the prior 6-day average from the sparkline.
    private func coreTrend(_ m: DashboardMetric) -> SignalTrend {
        let values = viewModel.sparklineData[m.rawValue] ?? []
        guard values.count >= 2, let last = values.last else { return .flat }
        let prior = values.dropLast()
        let avg = prior.reduce(0, +) / Double(prior.count)
        if last > avg + 2 { return .up }
        if last < avg - 2 { return .down }
        return .flat
    }

    // MARK: 6 — Alert Center

    private var alertCenterSection: some View {
        let alerts = activeAlerts()
        return Group {
            if !alerts.isEmpty {
                VStack(alignment: .leading, spacing: Space.sm) {
                    SectionHeader(title: "Alert Center")
                    ForEach(alerts) { a in
                        AlertRow(icon: a.icon, title: a.title, detail: a.description,
                                 color: colorFor(priorityName: a.priority.colorStateName))
                    }
                }
            }
        }
    }

    // MARK: - Derivations

    private func topDrivers() -> [Insight] {
        Array(insightsVM.insights.sorted { $0.priority < $1.priority }.prefix(3))
    }

    private func activeAlerts() -> [Insight] {
        var alerts = insightsVM.insights.filter { $0.priority == .high }
        if viewModel.illnessArcActive {
            alerts.insert(Insight(
                icon: "thermometer.medium",
                title: "Elevated Temperature Trend — \(viewModel.illnessArcDays) night\(viewModel.illnessArcDays == 1 ? "" : "s")",
                description: "Wrist temperature is above baseline. This is not a diagnosis; strain targets are paused while you monitor the trend and how you feel.",
                priority: .high
            ), at: 0)
        }
        // Dedup with the Why section so we don't show the same card twice.
        let shownIDs = Set(topDrivers().map { $0.id })
        return Array(alerts.filter { !shownIDs.contains($0.id) }.prefix(4))
    }

    private func colorFor(priorityName: String) -> Color {
        switch priorityName {
        case "red":    return .somaRed
        case "yellow": return .somaYellow
        default:        return .somaGreen
        }
    }
}
