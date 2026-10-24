import Charts
import SwiftUI

enum ProgressRange: String, CaseIterable, Identifiable {
    case week = "7 days"
    case month = "30 days"
    case all = "All"

    var id: String { rawValue }

    func includes(_ date: Date, now: Date = .now) -> Bool {
        switch self {
        case .week: date >= now.addingTimeInterval(-7 * 86_400)
        case .month: date >= now.addingTimeInterval(-30 * 86_400)
        case .all: true
        }
    }
}

/// One measurement over time.
struct TrendPoint: Identifiable, Equatable {
    var date: Date
    var value: Double
    var id: Date { date }
}

/// The Progress tab: the touch pattern, a chart per measurement, and a report to share.
struct ProgressScreen: View {
    @Environment(AppModel.self) private var model
    @State private var range: ProgressRange = .month
    @State private var shared: SharedFile?
    @State private var exporting = false

    var body: some View {
        let log = model.activity.log
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.s4) {
                    SegmentedChoice(options: ProgressRange.allCases.map { ($0.rawValue, $0) }, selection: $range)
                    summary(log)
                    AchievementsRow(achievements: Achievements.all(log: log, streak: model.activity.streak(), phrases: model.phrases.count))
                    let insights = InsightEngine.insights(log: log)
                    if !insights.isEmpty {
                        VStack(alignment: .leading, spacing: Theme.Space.s3) {
                            SectionHeader("Insights")
                            ForEach(insights) { InsightRow(insight: $0) }
                        }
                    }
                    if let estimate = model.patternEstimate {
                        PatternCard(estimate: estimate)
                    }
                    TrendCard(title: "Daily check", subtitle: "Average distance from the target",
                              unit: "pt", decimals: 1, lowerIsBetter: true, color: Theme.checkColor,
                              points: log.checkIns.filter { range.includes($0.date) }.map { TrendPoint(date: $0.date, value: $0.distance) },
                              empty: "Do a daily check to start this chart.") { model.startRecalibration() }
                    FeelingCard(checkIns: log.checkIns.filter { range.includes($0.date) && $0.feeling != nil })
                    TrendCard(title: "Spiral", subtitle: "Average distance from the line",
                              unit: "pt", decimals: 1, lowerIsBetter: true, color: Theme.spiralColor,
                              points: log.spirals.filter { range.includes($0.date) }.map { TrendPoint(date: $0.date, value: $0.result.deviation) },
                              empty: "Trace a spiral to start this chart.") { model.startPractice(.spiral) }
                    TrendCard(title: "Rhythm tapping", subtitle: "Taps in ten seconds",
                              unit: "taps", decimals: 0, lowerIsBetter: false, color: Theme.tappingColor,
                              points: log.tapping.filter { range.includes($0.date) }.map { TrendPoint(date: $0.date, value: $0.result.tapsPerTenSeconds) },
                              empty: "Try rhythm tapping to start this chart.") { model.startPractice(.tapping) }
                    TrendCard(title: "Typing", subtitle: "Words a minute",
                              unit: "wpm", decimals: 0, lowerIsBetter: false, color: Theme.typingColor,
                              points: log.typing.filter { range.includes($0.date) }.map { TrendPoint(date: $0.date, value: $0.wordsPerMinute) },
                              empty: "Do some typing practice to start this chart.") { model.startPractice(.typing) }
                    TrendCard(title: "Tremor meter", subtitle: "Shake strength while resting",
                              unit: "mg", decimals: 1, lowerIsBetter: true, color: Theme.tremorColor,
                              points: log.tremor.filter { range.includes($0.date) && $0.result.posture == .rest }.map { TrendPoint(date: $0.date, value: $0.result.amplitude) },
                              empty: "Take a tremor reading to start this chart.") { model.startPractice(.tremor) }
                    TrendCard(title: "Voice", subtitle: "Share of each “ahh” in the loud zone",
                              unit: "%", decimals: 0, lowerIsBetter: false, color: Theme.voiceColor,
                              points: log.voice.filter { range.includes($0.date) }.map { TrendPoint(date: $0.date, value: $0.result.inTarget * 100) },
                              empty: "Try the voice exercise to start this chart.") { model.startPractice(.voice) }
                    exportCard(log)
                    FootNote("A record of your own exercises and practice. It describes how your touches behave and isn’t a medical assessment.")
                        .padding(.horizontal, 4)
                }
                .padding(.horizontal, Theme.Space.s4)
                .padding(.bottom, Theme.Space.s8)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
            }
.background {
                ZStack(alignment: .top) {
                    Theme.bg.ignoresSafeArea()
                    AuraWash(colors: AuraWash.progress)
                }
            }
            .navigationTitle("Progress")
            .sheet(item: $shared) { file in
                ShareSheet(items: [file.url]).presentationDetents([.medium, .large])
            }
        }
    }

    private func summary(_ log: ActivityLog) -> some View {
        let checks = log.checkIns.filter { range.includes($0.date) && !$0.isSetup }.count
        let practice = log.spirals.filter { range.includes($0.date) }.count
            + log.tapping.filter { range.includes($0.date) }.count
            + log.typing.filter { range.includes($0.date) }.count
            + log.tremor.filter { range.includes($0.date) }.count
            + log.voice.filter { range.includes($0.date) }.count
        return VStack(alignment: .leading, spacing: Theme.Space.s4) {
            Text(range == .all ? "ALL YOUR RESULTS" : "THE LAST \(range.rawValue.uppercased())")
                .font(Theme.font(.caption, weight: .heavy))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.75))
            HStack(alignment: .top, spacing: Theme.Space.s3) {
                StatTile(value: Double(model.activity.streak()), label: "day streak", color: .white)
                StatTile(value: Double(checks), label: checks == 1 ? "daily check" : "daily checks", color: .white)
                StatTile(value: Double(practice), label: practice == 1 ? "practice" : "practices", color: .white)
            }
        }
        .padding(Theme.Space.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AuraBackground(mood: model.auraMood))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .shadow(color: model.auraMood.glow.opacity(0.3), radius: 18, y: 8)
        .environment(\.colorScheme, .dark)
    }

    private func exportCard(_ log: ActivityLog) -> some View {
        Card {
            HStack(spacing: Theme.Space.s3) {
                IconBadge(symbol: "doc.richtext", color: Theme.accent, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Share with your care team").font(Theme.rounded(.title3, weight: .bold))
                    Text("A one-page summary of your checks and practice, or every result as a spreadsheet.")
                        .font(Theme.font(.subheadline))
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: Theme.Space.s2) {
                Button {
                    exporting = true
                    shared = ReportBuilder.pdf(model: model, range: range).map(SharedFile.init)
                    exporting = false
                } label: {
                    Label("PDF report", systemImage: "doc.text")
                }
                .buttonStyle(.primary)
                Button {
                    shared = ReportBuilder.csv(log: log).map(SharedFile.init)
                } label: {
                    Label("Data (CSV)", systemImage: "tablecells")
                }
                .buttonStyle(.secondary(minHeight: 54))
            }
            .disabled((log.isEmpty && log.doses.isEmpty) || exporting)
        }
    }
}

// MARK: - Achievements

private struct AchievementsRow: View {
    let achievements: [Achievement]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s3) {
            SectionHeader(title: "Achievements") {
                Text("\(achievements.filter(\.earned).count) of \(achievements.count)")
                    .font(Theme.rounded(.subheadline, weight: .bold))
                    .foregroundStyle(Theme.secondaryText)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Space.s3) {
                    ForEach(achievements) { badge in
                        VStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .fill(badge.earned
                                          ? AnyShapeStyle(LinearGradient(colors: badge.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                                          : AnyShapeStyle(Theme.surface))
                                if !badge.earned {
                                    Circle()
                                        .trim(from: 0, to: badge.progress)
                                        .stroke(badge.colors.first ?? Theme.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                                        .rotationEffect(.degrees(-90))
                                        .padding(2)
                                }
                                Image(systemName: badge.symbol)
                                    .font(.system(size: 26, weight: .bold))
                                    .foregroundStyle(badge.earned ? .white : Theme.neutral400)
                            }
                            .frame(width: 72, height: 72)
                            .shadow(color: badge.earned ? (badge.colors.last ?? .clear).opacity(0.35) : .clear, radius: 8, y: 4)
                            Text(badge.title)
                                .font(Theme.font(.caption, weight: .semibold))
                                .foregroundStyle(badge.earned ? Theme.text : Theme.secondaryText)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                        }
                        .frame(width: 86)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(badge.title): \(badge.earned ? "earned" : badge.detail)")
                    }
                }
                .padding(.horizontal, Theme.Space.s4)
                .padding(.vertical, 4)
            }
            .padding(.horizontal, -Theme.Space.s4)
        }
    }
}

// MARK: - Pattern

struct PatternCard: View {
    let estimate: TouchPatternEstimate

    var body: some View {
        Card(spacing: Theme.Space.s4) {
            HStack(spacing: Theme.Space.s3) {
                IconBadge(symbol: estimate.primary.symbol, color: Theme.accent, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("TOUCH PATTERN")
                        .font(Theme.font(.caption, weight: .bold))
                        .tracking(0.6)
                        .foregroundStyle(Theme.secondaryText)
                    Text(estimate.primary.name).font(Theme.rounded(.title2, weight: .bold))
                }
            }
            Text(estimate.primary.explanation)
                .font(Theme.font(.subheadline))
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: Theme.Space.s2) {
                ForEach(TouchPattern.classified) { pattern in
                    let p = estimate.probability(pattern)
                    HStack(spacing: Theme.Space.s3) {
                        Text(pattern.name)
                            .font(Theme.font(.footnote, weight: pattern == estimate.primary ? .semibold : .regular))
                            .frame(width: 128, alignment: .leading)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Theme.surface)
                                Capsule().fill(pattern == estimate.primary ? Theme.accent : Theme.neutral400)
                                    .frame(width: max(6, geo.size.width * p))
                            }
                        }
                        .frame(height: 10)
                        Text(p.formatted(.percent.precision(.fractionLength(0))))
                            .font(Theme.rounded(.footnote, weight: .semibold))
                            .monospacedDigit()
                            .frame(width: 42, alignment: .trailing)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("What your keyboard does about it").font(Theme.font(.subheadline, weight: .semibold))
                ForEach(estimate.primary.adaptations, id: \.self) { item in
                    Label(item, systemImage: "checkmark")
                        .font(Theme.font(.footnote))
                        .foregroundStyle(Theme.text)
                }
            }
            FootNote("Estimated on your iPhone by a small machine-learning model from \(estimate.evidence) measurements of your exercises and practice. It describes your touches, not any condition.")
        }
    }
}

// MARK: - Charts

private struct TrendCard: View {
    let title: String
    let subtitle: String
    let unit: String
    let decimals: Int
    let lowerIsBetter: Bool
    let color: Color
    let points: [TrendPoint]
    let empty: String
    let start: () -> Void

    @State private var selected: Date?

    var body: some View {
        Card {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Theme.rounded(.title3, weight: .bold))
                    Text(subtitle).font(Theme.font(.footnote)).foregroundStyle(Theme.secondaryText)
                }
                Spacer()
                if let latest = points.last {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        BigNumber(value: latest.value, decimals: decimals, size: 28, color: color)
                        Text(unit).font(Theme.rounded(.footnote, weight: .semibold)).foregroundStyle(Theme.secondaryText)
                    }
                }
            }
            if points.count >= 2, let first = points.first, let last = points.last {
                let delta = last.value - first.value
                let tolerance = decimals == 0 ? 0.9 : 0.4
                TrendLabel.compare(last.value, to: first.value, lowerIsBetter: lowerIsBetter, tolerance: tolerance,
                                   better: "\(abs(delta).formatted(.number.precision(.fractionLength(decimals)))) \(unit) \(lowerIsBetter ? "closer" : "more") than at the start",
                                   worse: "\(abs(delta).formatted(.number.precision(.fractionLength(decimals)))) \(unit) \(lowerIsBetter ? "further" : "fewer") than at the start",
                                   same: "Steady over this period")
                chart
            } else if points.count == 1 {
                Text("One result so far. Do it again on another day to see a trend.")
                    .font(Theme.font(.subheadline))
                    .foregroundStyle(Theme.secondaryText)
            } else {
                HStack {
                    Text(empty).font(Theme.font(.subheadline)).foregroundStyle(Theme.secondaryText)
                    Spacer()
                    Button("Start", action: start).buttonStyle(TPButtonStyle(minHeight: 40, fullWidth: false, tint: color))
                }
            }
        }
    }

    private var chart: some View {
        let selectedPoint = selected.flatMap { date in points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) } }
        return Chart {
            ForEach(points) { point in
                AreaMark(x: .value("Date", point.date), y: .value(unit, point.value))
                    .foregroundStyle(LinearGradient(colors: [color.opacity(0.22), color.opacity(0)], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Date", point.date), y: .value(unit, point.value))
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .interpolationMethod(.monotone)
                PointMark(x: .value("Date", point.date), y: .value(unit, point.value))
                    .foregroundStyle(color)
                    .symbolSize(point == selectedPoint ? 110 : 28)
            }
            if let selectedPoint {
                RuleMark(x: .value("Selected", selectedPoint.date))
                    .foregroundStyle(Theme.neutral400)
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        VStack(spacing: 0) {
                            Text("\(selectedPoint.value.formatted(.number.precision(.fractionLength(decimals)))) \(unit)")
                                .font(Theme.rounded(.subheadline, weight: .bold))
                            Text(selectedPoint.date.shortDay).font(Theme.font(.caption2)).foregroundStyle(Theme.secondaryText)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
                    }
            }
        }
        .chartXSelection(value: $selected)
        .chartYScale(domain: .automatic(includesZero: false))
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(Theme.divider)
                AxisValueLabel()
            }
        }
        .frame(height: 170)
        .accessibilityLabel("\(title) chart, \(points.count) results")
    }
}

private struct FeelingCard: View {
    let checkIns: [CheckInRecord]

    var body: some View {
        if checkIns.count >= 2 {
            Card {
                VStack(alignment: .leading, spacing: 2) {
                    Text("How typing felt").font(Theme.rounded(.title3, weight: .bold))
                    Text("From your daily checks").font(Theme.font(.footnote)).foregroundStyle(Theme.secondaryText)
                }
                Chart(checkIns) { check in
                    BarMark(x: .value("Date", check.date, unit: .day), y: .value("Feeling", check.feeling?.rawValue ?? 0))
                        .foregroundStyle(Theme.accent.opacity(0.35 + 0.16 * Double(check.feeling?.rawValue ?? 0)))
                        .cornerRadius(4)
                }
                .chartYScale(domain: 0...4)
                .chartYAxis {
                    AxisMarks(position: .leading, values: [1, 2, 3, 4]) { value in
                        AxisGridLine().foregroundStyle(Theme.divider)
                        AxisValueLabel {
                            if let v = value.as(Int.self), let feeling = Feeling(rawValue: v) { Text(feeling.label) }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    }
                }
                .frame(height: 150)
            }
        }
    }
}
