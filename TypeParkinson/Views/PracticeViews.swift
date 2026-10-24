import Charts
import SwiftUI

/// The Practice tab: short activities that track how the person's hands are doing.
struct PracticeView: View {
    @Environment(AppModel.self) private var model
    @State private var active: PracticeActivity?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.s4) {
                    Text("Short activities that show how your hands and voice are doing. Every result goes to Progress.")
                        .font(Theme.font(.subheadline))
                        .foregroundStyle(Theme.secondaryText)
                        .padding(.horizontal, 4)
                    ForEach(PracticeActivity.allCases) { activity in
                        Button { active = activity } label: {
                            HStack(alignment: .bottom, spacing: 0) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(activity.duration.uppercased())
                                        .font(Theme.font(.caption2, weight: .heavy))
                                        .tracking(0.8)
                                        .foregroundStyle(.white.opacity(0.8))
                                    Text(activity.title)
                                        .font(Theme.rounded(.title2, weight: .heavy))
                                        .foregroundStyle(.white)
                                    Text(model.activity.lastResultText(for: activity) ?? activity.summary)
                                        .font(Theme.font(.footnote, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.88))
                                        .fixedSize(horizontal: false, vertical: true)
                                        .multilineTextAlignment(.leading)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                ActivityArt(activity: activity, tint: .white)
                                    .frame(width: 130, height: 110)
                            }
                            .padding(Theme.Space.s5)
                            .frame(maxWidth: .infinity, minHeight: 170, alignment: .bottomLeading)
                            .background(LinearGradient(colors: activity.gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                            .overlay(alignment: .topTrailing) {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 36, height: 36)
                                    .glassEffect(.regular, in: Circle())
                                    .padding(Theme.Space.s4)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                            .shadow(color: (activity.gradient.last ?? .black).opacity(0.28), radius: 14, y: 7)
                        }
                        .buttonStyle(PressableStyle())
                        .accessibilityLabel("\(activity.title). \(activity.summary)")
                    }
                    Button { model.startExercises() } label: {
                        HStack(spacing: Theme.Space.s3) {
                            IconBadge(symbol: "slider.horizontal.3", color: Theme.accent, size: 42)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Redo the setup exercises").font(Theme.font(.body, weight: .semibold))
                                Text("Rebuilds your touch profile and keyboard. About three minutes.")
                                    .font(Theme.font(.footnote))
                                    .foregroundStyle(Theme.secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").foregroundStyle(Theme.neutral400)
                        }
                    }
                    .buttonStyle(.card)
                }
                .padding(.horizontal, Theme.Space.s4)
                .padding(.bottom, Theme.Space.s8)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
            }
.background {
                ZStack(alignment: .top) {
                    Theme.bg.ignoresSafeArea()
                    AuraWash(colors: [Color(rgb: 0x9EE8E1), Color(rgb: 0xFFC2A8), Color(rgb: 0xE2B8FF), Color(rgb: 0xFFD98F)])
                }
            }
            .navigationTitle("Practice")
            .fullScreenCover(item: $active) { activity in
                ActivitySession(activity: activity)
                    .environment(model)
            }
            .onAppear(perform: openRequested)
            .onChange(of: model.practiceRequest) { _, _ in openRequested() }
        }
    }

    private func openRequested() {
        guard let request = model.practiceRequest else { return }
        model.practiceRequest = nil
        active = request
    }
}

/// A small drawing of each activity, in its colour or in white over its gradient.
struct ActivityArt: View {
    let activity: PracticeActivity
    var tint: Color?

    var body: some View {
        Canvas { context, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let color = tint ?? activity.color
            let faint = color.opacity(tint == nil ? 0.35 : 0.4)
            switch activity {
            case .spiral:
                let points = Spiral.template(center: c, radius: min(size.width, size.height) * 0.44, samples: 200)
                var path = Path()
                path.addLines(points)
                context.stroke(path, with: .color(faint), style: StrokeStyle(lineWidth: 7, lineCap: .round))
                var traced = Path()
                traced.addLines(Array(points.prefix(150)).enumerated().map { i, p in
                    CGPoint(x: p.x + sin(Double(i) * 1.7) * 1.4, y: p.y + cos(Double(i) * 2.3) * 1.4)
                })
                context.stroke(traced, with: .color(color), style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
            case .tapping:
                let r = min(size.height * 0.26, size.width * 0.16, 30)
                for (i, x) in [c.x - r * 1.4, c.x + r * 1.4].enumerated() {
                    context.fill(Path(ellipseIn: CGRect(x: x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                                 with: .color(i == 0 ? color : faint))
                    if i == 0 {
                        for ring in [r * 1.4, r * 1.8] {
                            context.stroke(Path(ellipseIn: CGRect(x: x - ring, y: c.y - ring, width: 2 * ring, height: 2 * ring)),
                                           with: .color(color.opacity(ring < r * 1.6 ? 0.45 : 0.2)), lineWidth: 2)
                        }
                    }
                }
            case .typing:
                let keys = ["t", "y", "p", "e"]
                let w = min(size.width / 4.6, 34)
                for (i, key) in keys.enumerated() {
                    let rect = CGRect(x: c.x - 2 * (w + 5) + CGFloat(i) * (w + 5), y: c.y - w * 0.6, width: w, height: w * 1.2)
                    let shape = Path(roundedRect: rect, cornerRadius: 8)
                    let highlighted = i == 2
                    context.fill(shape, with: .color(highlighted ? color : (tint == nil ? .white : color.opacity(0.25))))
                    let label = highlighted ? (tint == nil ? Color.white : (activity.gradient.last ?? .black)) : color
                    context.draw(Text(key).font(Theme.rounded(size: w * 0.55, weight: .bold)).foregroundStyle(label),
                                 at: CGPoint(x: rect.midX, y: rect.midY))
                }
            case .tremor:
                var wave = Path()
                let steps = 120
                for i in 0...steps {
                    let t = Double(i) / Double(steps)
                    let envelope = sin(t * .pi)
                    let y = c.y + sin(t * .pi * 14) * size.height * 0.32 * envelope
                    let p = CGPoint(x: size.width * 0.06 + t * size.width * 0.88, y: y)
                    if i == 0 { wave.move(to: p) } else { wave.addLine(to: p) }
                }
                context.stroke(wave, with: .color(color), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                var base = Path()
                base.move(to: CGPoint(x: size.width * 0.04, y: c.y))
                base.addLine(to: CGPoint(x: size.width * 0.96, y: c.y))
                context.stroke(base, with: .color(faint), lineWidth: 1.5)
            case .voice:
                let mic = CGRect(x: c.x - 11, y: c.y - 24, width: 22, height: 34)
                context.fill(Path(roundedRect: mic, cornerRadius: 11), with: .color(color))
                var stand = Path()
                stand.addArc(center: CGPoint(x: c.x, y: c.y - 2), radius: 18, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
                stand.move(to: CGPoint(x: c.x, y: c.y + 16))
                stand.addLine(to: CGPoint(x: c.x, y: c.y + 26))
                context.stroke(stand, with: .color(color), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                for (i, r) in [32.0, 44.0, 56.0].enumerated() {
                    for side in [-1.0, 1.0] {
                        var arc = Path()
                        arc.addArc(center: c, radius: r, startAngle: .degrees(side < 0 ? 150 : -30), endAngle: .degrees(side < 0 ? 210 : 30), clockwise: false)
                        context.stroke(arc, with: .color(color.opacity(0.75 - Double(i) * 0.2)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Session container

/// One run of an activity, full screen: the activity itself, then its result.
struct ActivitySession: View {
    let activity: PracticeActivity
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                switch activity {
                case .spiral: SpiralSession(close: { dismiss() })
                case .tapping: TappingSession(close: { dismiss() })
                case .typing: TypingSession(close: { dismiss() })
                case .tremor: TremorSession(close: { dismiss() })
                case .voice: VoiceSession(close: { dismiss() })
                }
            }
            .background(Theme.bg)
            .navigationTitle(activity.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 15, weight: .bold))
                    }
                    .accessibilityLabel("Close")
                }
            }
        }
        .tint(activity.color)
    }
}

/// Hand picker for activities done one hand at a time.
struct HandPicker: View {
    @Binding var hand: Hand
    var tint: Color = Theme.accent

    var body: some View {
        SegmentedChoice(options: [("Right hand", Hand.right), ("Left hand", Hand.left)], selection: $hand, tint: tint)
    }
}

/// The figures and comparison after an activity.
struct ResultPanel<Figures: View, Extra: View>: View {
    let color: Color
    let headline: String
    var trend: TrendLabel?
    @ViewBuilder var figures: Figures
    @ViewBuilder var extra: Extra
    let again: () -> Void
    let done: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.s5) {
                VStack(alignment: .leading, spacing: Theme.Space.s2) {
                    Label("Saved to Progress", systemImage: "checkmark.circle.fill")
                        .font(Theme.font(.subheadline, weight: .semibold))
                        .foregroundStyle(Theme.positive)
                    Text(headline)
                        .font(Theme.rounded(.title, weight: .bold))
                        .fixedSize(horizontal: false, vertical: true)
                    if let trend { trend }
                }
                Card { HStack(alignment: .top, spacing: Theme.Space.s4) { figures } }
                extra
                FootNote("A record of this activity only. It isn’t a medical assessment.")
            }
            .padding(Theme.Space.s5)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: Theme.Space.s2) {
                Button("Try again", action: again).buttonStyle(.primary(tint: color))
                Button("Done", action: done).buttonStyle(.secondary())
            }
            .padding(.horizontal, Theme.Space.s5)
            .padding(.vertical, Theme.Space.s3)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
            .background(.bar)
        }
        .sensoryFeedback(.success, trigger: headline)
    }
}

// MARK: - Spiral

private struct SpiralSession: View {
    @Environment(AppModel.self) private var model
    let close: () -> Void

    @State private var hand: Hand = .right
    @State private var trace: [TimedPoint] = []
    @State private var drawing: AnyHashable?
    @State private var message = "Put your finger on the dot in the middle."
    @State private var result: (SpiralResult, [TimedPoint], CGFloat)?
    @State private var revealed = false

    var body: some View {
        if let result {
            resultView(result.0, result.1, result.2)
        } else {
            drawingView
        }
    }

    private var drawingView: some View {
        VStack(spacing: Theme.Space.s4) {
            VStack(alignment: .leading, spacing: Theme.Space.s2) {
                Text("Trace the spiral from the centre out, at a comfortable speed.")
                    .font(Theme.font(.headline))
                    .fixedSize(horizontal: false, vertical: true)
                HandPicker(hand: $hand, tint: Theme.spiralColor)
            }
            .padding(.horizontal, Theme.Space.s5)
            GeometryReader { geo in
                let side = min(geo.size.width - 2 * Theme.Space.s5, geo.size.height - 40, 420)
                let radius = side / 2 - 18
                let center = CGPoint(x: side / 2, y: side / 2)
                VStack(spacing: Theme.Space.s3) {
                    ZStack {
                        SpiralTemplate(center: center, radius: radius)
                            .trim(from: 0, to: revealed ? 1 : 0)
                            .stroke(Theme.neutral400, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                            .opacity(0.55)
                        Path { $0.addLines(trace.map(\.point)) }
                            .stroke(Theme.spiralColor, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                        Circle().fill(Theme.spiralColor)
                            .frame(width: 26, height: 26)
                            .position(center)
                            .opacity(drawing == nil ? 1 : 0.3)
                            .scaleEffect(drawing == nil ? 1 : 0.7)
                            .animation(.spring(duration: 0.3), value: drawing == nil)
                        if let end = Spiral.template(center: center, radius: radius, samples: 10).last {
                            Image(systemName: "flag.fill")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(Theme.neutral600)
                                .position(x: end.x, y: end.y - 16)
                        }
                    }
                    .frame(width: side, height: side)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                    .onTouches(
                        began: { id, point in begin(id, point, center: center) },
                        moved: { id, point in
                            guard drawing == id else { return }
                            let p = displaced(point)
                            trace.append(TimedPoint(x: p.x, y: p.y, t: ProcessInfo.processInfo.systemUptime))
                        },
                        ended: { id, _ in
                            guard drawing == id else { return }
                            drawing = nil
                            finish(center: center, radius: radius, side: side)
                        })
                    Text(message)
                        .font(Theme.font(.subheadline))
                        .foregroundStyle(Theme.secondaryText)
                        .multilineTextAlignment(.center)
                        .contentTransition(.opacity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.top, Theme.Space.s3)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2)) { revealed = true }
        }
    }

    private func displaced(_ point: CGPoint) -> CGPoint {
        let jitter = model.simulator.slideJitter()
        return CGPoint(x: point.x + jitter.dx, y: point.y + jitter.dy)
    }

    private func begin(_ id: AnyHashable, _ point: CGPoint, center: CGPoint) {
        guard drawing == nil else { return }
        guard hypot(point.x - center.x, point.y - center.y) <= 40 else {
            message = "Start on the dot in the middle."
            return
        }
        drawing = id
        message = "Keep going, out to the flag."
        let p = displaced(point)
        trace = [TimedPoint(x: p.x, y: p.y, t: ProcessInfo.processInfo.systemUptime)]
    }

    private func finish(center: CGPoint, radius: CGFloat, side: CGFloat) {
        guard let analysis = Spiral.analyze(trace, center: center, radius: radius), analysis.coverage >= 0.7 else {
            message = "Not quite to the flag. Start again from the dot."
            withAnimation(.easeOut(duration: 0.3)) { trace = [] }
            return
        }
        model.activity.add(SpiralRecord(date: .now, hand: hand, result: analysis,
                                        trace: Spiral.normalized(trace, center: center, radius: radius)))
        withAnimation(.smooth(duration: 0.35)) { result = (analysis, trace, side) }
    }

    private func resultView(_ r: SpiralResult, _ finished: [TimedPoint], _ side: CGFloat) -> some View {
        let previous = model.activity.spirals.dropLast().last { $0.hand == hand }
        let trend = previous.map {
            TrendLabel.compare(r.deviation, to: $0.result.deviation, lowerIsBetter: true, tolerance: 0.7,
                               better: "\(($0.result.deviation - r.deviation).oneDecimal) pt closer than last time",
                               worse: "\((r.deviation - $0.result.deviation).oneDecimal) pt further than last time")
        }
        return ResultPanel(color: Theme.spiralColor, headline: headline(r), trend: trend) {
            StatTile(value: r.deviation, decimals: 1, unit: "pt", label: "from the line, on average", color: Theme.spiralColor)
            StatTile(value: r.smoothness * 100, unit: "%", label: "smoothness")
            StatTile(value: r.duration, decimals: 1, unit: "s", label: "to draw")
        } extra: {
            Card {
                Text("Your drawing").font(Theme.font(.headline))
                let scale = 220 / side
                ZStack {
                    SpiralTemplate(center: CGPoint(x: side / 2, y: side / 2), radius: side / 2 - 18)
                        .stroke(Theme.neutral400.opacity(0.5), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    Path { $0.addLines(finished.map(\.point)) }
                        .stroke(Theme.spiralColor, style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
                }
                .frame(width: side, height: side)
                .scaleEffect(scale)
                .frame(width: 220, height: 220)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Your spiral drawn over the guide")
            }
        } again: {
            withAnimation(.smooth) {
                result = nil
                trace = []
                message = "Put your finger on the dot in the middle."
            }
        } done: {
            close()
        }
    }

    private func headline(_ r: SpiralResult) -> String {
        if r.deviation < 5 && r.smoothness > 0.88 { return "Smooth and close to the line." }
        if r.smoothness < 0.75 { return "Close enough, with some wobble." }
        return "Nicely done."
    }
}

/// The guide spiral as a shape, so it can be drawn on with `trim`.
struct SpiralTemplate: Shape {
    var center: CGPoint
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        Path { $0.addLines(Spiral.template(center: center, radius: radius, samples: 360)) }
    }
}

// MARK: - Tapping

private struct TappingSession: View {
    @Environment(AppModel.self) private var model
    let close: () -> Void

    @State private var hand: Hand = .right
    @State private var events: [TapEvent] = []
    @State private var expected: Int?
    @State private var started: TimeInterval?
    @State private var remaining = Tapping.duration
    @State private var flash: Int?
    @State private var result: TappingResult?
    @State private var timer: Task<Void, Never>?

    var body: some View {
        if let result {
            resultView(result)
        } else {
            tappingView
        }
    }

    private var tappingView: some View {
        VStack(spacing: Theme.Space.s4) {
            VStack(alignment: .leading, spacing: Theme.Space.s2) {
                Text("Tap left, then right, as quickly and evenly as you can for ten seconds.")
                    .font(Theme.font(.headline))
                    .fixedSize(horizontal: false, vertical: true)
                if started == nil { HandPicker(hand: $hand, tint: Theme.tappingColor) }
            }
            .padding(.horizontal, Theme.Space.s5)
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(events.count)")
                        .font(Theme.rounded(size: 56, weight: .bold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("taps").font(Theme.font(.subheadline)).foregroundStyle(Theme.secondaryText)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text(remaining.formatted(.number.precision(.fractionLength(1))))
                        .font(Theme.rounded(size: 34, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.tappingColor)
                    Text("seconds left").font(Theme.font(.subheadline)).foregroundStyle(Theme.secondaryText)
                }
            }
            .padding(.horizontal, Theme.Space.s5)
            ProgressView(value: Tapping.duration - remaining, total: Tapping.duration)
                .tint(Theme.tappingColor)
                .padding(.horizontal, Theme.Space.s5)
            GeometryReader { geo in
                let centers = targetCenters(geo.size)
                ZStack {
                    ForEach(0..<2) { i in
                        let isNext = expected == nil || expected == i
                        Circle()
                            .fill(Theme.tappingColor.opacity(isNext ? 1 : 0.28))
                            .overlay(Circle().stroke(Theme.tappingColor.opacity(0.35), lineWidth: flash == i ? 14 : 0))
                            .frame(width: 112, height: 112)
                            .scaleEffect(flash == i ? 0.92 : 1)
                            .position(centers[i])
                            .animation(.spring(duration: 0.18), value: flash)
                            .accessibilityLabel(i == 0 ? "Left target" : "Right target")
                    }
                    if started == nil {
                        Text("Starts on your first tap")
                            .font(Theme.font(.footnote, weight: .semibold))
                            .foregroundStyle(Theme.secondaryText)
                            .position(x: geo.size.width / 2, y: centers[0].y + 92)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                .onTouches(began: { _, point in tap(point, centers: centers) })
            }
            .padding(.horizontal, Theme.Space.s4)
            .padding(.bottom, Theme.Space.s4)
        }
        .padding(.top, Theme.Space.s3)
        .sensoryFeedback(.impact(weight: .light), trigger: events.count)
        .onDisappear { timer?.cancel() }
    }

    private func targetCenters(_ size: CGSize) -> [CGPoint] {
        let y = size.height / 2
        let spread = min(size.width / 2 - 70, 110)
        return [CGPoint(x: size.width / 2 - spread, y: y), CGPoint(x: size.width / 2 + spread, y: y)]
    }

    private func tap(_ raw: CGPoint, centers: [CGPoint]) {
        guard result == nil else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if let started, now - started >= Tapping.duration {
            finish()
            return
        }
        let d = model.simulator.tapDisplacement()
        let point = CGPoint(x: raw.x + d.dx * 0.6, y: raw.y + d.dy * 0.6)
        let distances = centers.map { hypot(point.x - $0.x, point.y - $0.y) }
        let nearest = distances[0] <= distances[1] ? 0 : 1
        let inside = distances[nearest] <= 66
        if started == nil {
            started = now
            startTimer()
        }
        let hit = inside && (expected == nil || expected == nearest)
        events.append(TapEvent(time: now, hit: hit))
        if hit { expected = 1 - nearest }
        flash = nearest
        Task {
            try? await Task.sleep(for: .milliseconds(120))
            if flash == nearest { flash = nil }
        }
    }

    private func startTimer() {
        timer = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                guard !Task.isCancelled, let started else { return }
                let left = max(0, Tapping.duration - (ProcessInfo.processInfo.systemUptime - started))
                remaining = left
                if left <= 0 {
                    finish()
                    return
                }
            }
        }
    }

    private func finish() {
        guard result == nil, started != nil else { return }
        timer?.cancel()
        timer = nil
        let r = Tapping.analyze(events)
        model.activity.add(TappingRecord(date: .now, hand: hand, result: r))
        withAnimation(.smooth(duration: 0.35)) { result = r }
    }

    private func resultView(_ r: TappingResult) -> some View {
        let previous = model.activity.tapping.dropLast().last { $0.hand == hand }
        let trend = previous.map {
            TrendLabel.compare(Double(r.taps), to: Double($0.result.taps), lowerIsBetter: false, tolerance: 1,
                               better: "\(r.taps - $0.result.taps) more taps than last time",
                               worse: "\($0.result.taps - r.taps) fewer taps than last time")
        }
        let intervals = zip(events, events.dropFirst()).enumerated().map { ($0.offset + 1, ($0.element.1.time - $0.element.0.time) * 1000) }
        return ResultPanel(color: Theme.tappingColor,
                           headline: r.consistency > 0.8 ? "A steady rhythm." : r.taps > 40 ? "Quick tapping." : "All done.",
                           trend: trend) {
            StatTile(value: Double(r.taps), label: "taps in 10 seconds", color: Theme.tappingColor)
            StatTile(value: r.consistency * 100, unit: "%", label: "even rhythm")
            StatTile(value: r.accuracy * 100, unit: "%", label: "on target")
        } extra: {
            if intervals.count >= 3 {
                Card {
                    Text("Time between taps").font(Theme.font(.headline))
                    Chart(intervals, id: \.0) { item in
                        BarMark(x: .value("Tap", item.0), y: .value("Milliseconds", item.1), width: .ratio(0.7))
                            .foregroundStyle(Theme.tappingColor.gradient)
                            .cornerRadius(3)
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis {
                        AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                            AxisGridLine().foregroundStyle(Theme.divider)
                            AxisValueLabel { if let ms = value.as(Double.self) { Text("\(Int(ms)) ms") } }
                        }
                    }
                    .frame(height: 140)
                    Text("Even bars mean an even rhythm.")
                        .font(Theme.font(.footnote))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
        } again: {
            withAnimation(.smooth) {
                result = nil
                events = []
                expected = nil
                started = nil
                remaining = Tapping.duration
            }
        } done: {
            close()
        }
    }
}

// MARK: - Typing

private struct TypingSession: View {
    @Environment(AppModel.self) private var model
    let close: () -> Void

    @State private var phrase = PracticePhrases.random()
    @State private var record: TypingRecord?
    @State private var autoCorrected = 0
    @State private var round = 0

    var body: some View {
        if let record {
            resultView(record)
        } else {
            TypingTaskView(target: phrase, settings: model.settings, simulation: model.simulator.keyboardSimulation) { outcome in
                let wpm = TypingScore.wordsPerMinute(characters: phrase.count, seconds: outcome.phrase.time)
                let r = TypingRecord(date: .now, phrase: phrase, wordsPerMinute: wpm,
                                     accuracy: TypingScore.accuracy(errors: outcome.phrase.errors, length: phrase.count),
                                     corrections: outcome.phrase.corrections)
                model.activity.add(r)
                autoCorrected = outcome.autoCorrected
                withAnimation(.smooth(duration: 0.35)) { record = r }
            }
            .id(round)
            .padding(.top, Theme.Space.s3)
        }
    }

    private func resultView(_ r: TypingRecord) -> some View {
        let previous = model.activity.typing.dropLast().last
        let trend = previous.map {
            TrendLabel.compare(r.wordsPerMinute, to: $0.wordsPerMinute, lowerIsBetter: false, tolerance: 1,
                               better: "\((r.wordsPerMinute - $0.wordsPerMinute).wholeNumber) words a minute faster",
                               worse: "\(($0.wordsPerMinute - r.wordsPerMinute).wholeNumber) words a minute slower")
        }
        return ResultPanel(color: Theme.typingColor,
                           headline: r.accuracy >= 0.97 ? "Word perfect." : "Done. Nice work.",
                           trend: trend) {
            StatTile(value: r.wordsPerMinute, unit: "wpm", label: "words a minute", color: Theme.typingColor)
            StatTile(value: r.accuracy * 100, unit: "%", label: "accurate")
            StatTile(value: Double(r.corrections), label: "corrections")
        } extra: {
            if autoCorrected > 0 {
                Card {
                    Label("Smart correction fixed \(autoCorrected) word\(autoCorrected == 1 ? "" : "s") from where your touches landed.",
                          systemImage: "wand.and.stars")
                        .font(Theme.font(.subheadline))
                        .foregroundStyle(Theme.accent)
                }
            }
        } again: {
            withAnimation(.smooth) {
                phrase = PracticePhrases.random(excluding: phrase)
                record = nil
                round += 1
            }
        } done: {
            close()
        }
    }
}
