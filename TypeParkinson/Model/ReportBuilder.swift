import Charts
import SwiftUI

/// Makes the files on Progress's "Share with your care team": a one-page PDF
/// summary and a CSV of every result. Both are written to a temporary folder
/// and only leave the device if the person shares them.
enum ReportBuilder {
    static func pdf(model: AppModel, range: ProgressRange) -> URL? {
        let page = ReportPage(log: model.activity.log, estimate: model.patternEstimate,
                              name: model.account?.name, range: range)
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: page)
        renderer.proposedSize = ProposedViewSize(width: 612, height: 792)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("TypeParkinson report \(Date.now.formatted(.iso8601.year().month().day())).pdf")
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else { return nil }
        renderer.render { _, draw in
            context.beginPDFPage(nil)
            draw(context)
            context.endPDFPage()
        }
        context.closePDF()
        return url
    }

    static func csv(log: ActivityLog) -> URL? {
        let dateFormat = Date.ISO8601FormatStyle()
        var rows = ["date,activity,measure,value,unit,detail"]
        func row(_ date: Date, _ activity: String, _ measure: String, _ value: Double, _ unit: String, _ detail: String = "") {
            // A CSV is comma-delimited even when the phone uses decimal commas.
            let number = String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), value)
            let fields = [date.formatted(dateFormat), activity, measure, number, unit, csvDetail(detail)]
            rows.append(fields.joined(separator: ","))
        }
        for c in log.checkIns {
            let kind = c.isSetup ? "setup taps" : "daily check"
            row(c.date, kind, "distance from target", c.distance, "pt", c.feeling.map { "felt \($0.label.lowercased())" } ?? "")
            row(c.date, kind, "spread", c.spread, "pt")
            row(c.date, kind, "on target", c.hitRate * 100, "%")
        }
        for s in log.spirals {
            row(s.date, "spiral", "distance from line", s.result.deviation, "pt", s.hand.rawValue.lowercased())
            row(s.date, "spiral", "smoothness", s.result.smoothness * 100, "%", s.hand.rawValue.lowercased())
            row(s.date, "spiral", "time", s.result.duration, "s", s.hand.rawValue.lowercased())
        }
        for t in log.tapping {
            row(t.date, "rhythm tapping", "taps in 10 s", t.result.tapsPerTenSeconds, "taps", t.hand.rawValue.lowercased())
            row(t.date, "rhythm tapping", "even rhythm", t.result.consistency * 100, "%", t.hand.rawValue.lowercased())
            row(t.date, "rhythm tapping", "on target", t.result.accuracy * 100, "%", t.hand.rawValue.lowercased())
        }
        for t in log.typing {
            row(t.date, "typing", "speed", t.wordsPerMinute, "wpm")
            row(t.date, "typing", "accuracy", t.accuracy * 100, "%")
        }
        for t in log.tremor {
            let detail = "\(t.hand.rawValue.lowercased()); \(t.result.posture.title)"
            row(t.date, "tremor", "strongest shake rate", t.result.frequency, "Hz", detail)
            row(t.date, "tremor", "shake strength", t.result.amplitude, "mg", detail)
            row(t.date, "tremor", "reading duration", t.result.duration, "s", detail)
        }
        for v in log.voice {
            row(v.date, "voice", "relative loudness", v.result.level, "0-1")
            row(v.date, "voice", "time in loud zone", v.result.inTarget * 100, "%")
            row(v.date, "voice", "steadiness", v.result.steadiness * 100, "%")
            row(v.date, "voice", "voiced duration", v.result.duration, "s")
        }
        for dose in log.doses {
            row(dose.date, "medication", "logged dose", 1, "entry", dose.name)
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("TypeParkinson data.csv")
        do {
            try rows.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    /// Medication names are user-entered text: preserve CSV punctuation and
    /// prevent spreadsheet apps from interpreting a name as a formula.
    private static func csvDetail(_ value: String) -> String {
        let first = value.trimmingCharacters(in: .whitespacesAndNewlines).first
        let text = first.map { "=+-@".contains($0) } == true ? "'" + value : value
        return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

/// The PDF's one page, US Letter at 72 dpi.
private struct ReportPage: View {
    let log: ActivityLog
    let estimate: TouchPatternEstimate?
    let name: String?
    let range: ProgressRange

    var body: some View {
        let checks = log.checkIns.filter { range.includes($0.date) && !$0.isSetup }
        let spirals = log.spirals.filter { range.includes($0.date) }
        let tapping = log.tapping.filter { range.includes($0.date) }
        let typing = log.typing.filter { range.includes($0.date) }
        let tremor = log.tremor.filter { range.includes($0.date) }
        let voice = log.voice.filter { range.includes($0.date) }
        let doses = log.doses.filter { range.includes($0.date) }
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("TypeParkinson report").font(.system(size: 26, weight: .bold, design: .rounded))
                    Text([name, "\(range.rawValue == "All" ? "All results" : "Last \(range.rawValue)") · made \(Date.now.formatted(date: .long, time: .omitted))"]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            HStack(spacing: 12) {
                figure("\(checks.count)", "daily checks")
                figure(checks.isEmpty ? "–" : checks.map(\.distance).mean.oneDecimal + " pt", "average distance from target")
                figure("\(spirals.count + tapping.count + typing.count + tremor.count + voice.count)", "practice sessions")
            }
            HStack(spacing: 12) {
                figure(tremor.isEmpty ? "–" : tremor.map(\.result.frequency).mean.oneDecimal + " Hz", "average shake rate")
                figure(voice.isEmpty ? "–" : (voice.map(\.result.inTarget).mean * 100).oneDecimal + "%", "voice time in loud zone")
                figure("\(doses.count)", "logged doses")
            }
            if let estimate {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Touch pattern: \(estimate.primary.name)").font(.system(size: 13, weight: .semibold))
                    Text(estimate.primary.explanation + " " + TouchPattern.classified
                        .map { "\($0.name) \(estimate.probability($0).formatted(.percent.precision(.fractionLength(0))))" }
                        .joined(separator: ", ") + ".")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible())], spacing: 14) {
                miniChart("Daily check · distance from target (pt)", checks.map { TrendPoint(date: $0.date, value: $0.distance) }, Theme.checkColor)
                miniChart("Spiral · distance from line (pt)", spirals.map { TrendPoint(date: $0.date, value: $0.result.deviation) }, Theme.spiralColor)
                miniChart("Rhythm tapping · taps in 10 s", tapping.map { TrendPoint(date: $0.date, value: $0.result.tapsPerTenSeconds) }, Theme.tappingColor)
                miniChart("Typing · words a minute", typing.map { TrendPoint(date: $0.date, value: $0.wordsPerMinute) }, Theme.typingColor)
            }
            Spacer(minLength: 0)
            Text("Made by TypeParkinson from the person’s own on-device exercises and practice. It describes how their touches behaved and is not a medical assessment or diagnosis. Lower distances mean touches landed closer to where they aimed.")
                .font(.system(size: 8.5))
                .foregroundStyle(.secondary)
        }
        .padding(40)
        .frame(width: 612, height: 792, alignment: .topLeading)
        .background(.white)
        .foregroundStyle(.black)
    }

    private func figure(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 22, weight: .bold, design: .rounded))
            Text(label).font(.system(size: 9.5)).foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(rgb: 0xF2F2F7), in: RoundedRectangle(cornerRadius: 10))
    }

    private func miniChart(_ title: String, _ points: [TrendPoint], _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 10, weight: .semibold))
            if points.count >= 2 {
                Chart(points) { p in
                    LineMark(x: .value("Date", p.date), y: .value("Value", p.value))
                        .foregroundStyle(color)
                        .interpolationMethod(.monotone)
                    PointMark(x: .value("Date", p.date), y: .value("Value", p.value))
                        .foregroundStyle(color)
                        .symbolSize(14)
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 3)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated).day()).font(.system(size: 7)) } }
                .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in AxisGridLine(); AxisValueLabel().font(.system(size: 7)) } }
                .frame(height: 90)
            } else {
                Text(points.isEmpty ? "No results in this period." : "One result: \(points[0].value.oneDecimal).")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .frame(height: 90, alignment: .center)
            }
        }
        .padding(10)
        .background(Color(rgb: 0xF7F7FA), in: RoundedRectangle(cornerRadius: 10))
    }
}
