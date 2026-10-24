import Charts
import SwiftUI
import UIKit

// MARK: - Tremor meter

struct TremorSession: View {
    @Environment(AppModel.self) private var model
    let close: () -> Void

    private enum Phase: Equatable { case ready, countdown(Int), recording, result }

    @State private var phase: Phase = .ready
    @State private var posture: TremorPosture = .rest
    @State private var hand: Hand = .right
    @State private var recorder = MotionRecorder()
    @State private var result: TremorResult?
    @State private var sessionTask: Task<Void, Never>?

    var body: some View {
        switch phase {
        case .result:
            if let result { resultView(result) }
        default:
            measureView
        }
    }

    private var measureView: some View {
        VStack(spacing: Theme.Space.s5) {
            VStack(alignment: .leading, spacing: Theme.Space.s3) {
                SegmentedChoice(options: TremorPosture.allCases.map { ($0.title, $0) }, selection: $posture, tint: Theme.tremorColor)
                    .disabled(phase != .ready)
                HandPicker(hand: $hand, tint: Theme.tremorColor)
                    .disabled(phase != .ready)
                Text(posture.instruction)
                    .font(Theme.font(.headline))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Theme.Space.s5)

            ZStack {
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .fill(LinearGradient(colors: PracticeActivity.tremor.gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                VStack(spacing: Theme.Space.s4) {
                    ZStack {
                        Circle().stroke(.white.opacity(0.2), lineWidth: 10)
                        Circle()
                            .trim(from: 0, to: recorder.progress)
                            .stroke(.white, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.linear(duration: 0.1), value: recorder.progress)
                        switch phase {
                        case .countdown(let n):
                            Text("\(n)")
                                .font(Theme.rounded(size: 64, weight: .heavy))
                                .foregroundStyle(.white)
                                .contentTransition(.numericText(countsDown: true))
                        case .recording:
                            VStack(spacing: 2) {
                                Text(max(0, TremorAnalysis.duration * (1 - recorder.progress)).formatted(.number.precision(.fractionLength(0))))
                                    .font(Theme.rounded(size: 52, weight: .heavy))
                                    .foregroundStyle(.white)
                                    .monospacedDigit()
                                    .contentTransition(.numericText(countsDown: true))
                                Text("hold still").font(Theme.font(.subheadline, weight: .semibold)).foregroundStyle(.white.opacity(0.8))
                            }
                        default:
                            Image(systemName: posture == .rest ? "hand.raised.fill" : "iphone.gen3")
                                .font(.system(size: 50, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(width: 170, height: 170)
                    LiveTrace(values: recorder.recent)
                        .stroke(.white, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                        .frame(height: 70)
                        .padding(.horizontal, Theme.Space.s4)
                        .opacity(phase == .recording ? 1 : 0.35)
                }
                .padding(Theme.Space.s5)
            }
            .padding(.horizontal, Theme.Space.s4)

            if phase == .ready {
                VStack(spacing: Theme.Space.s2) {
                    Button { begin() } label: { Label("Start 10-second reading", systemImage: "waveform.path.ecg") }
                        .buttonStyle(.primary(tint: Theme.tremorColor))
                    if !recorder.hasSensors {
                        Text("This simulator has no motion sensors, so a sample reading is shown.")
                            .font(Theme.font(.footnote))
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                .padding(.horizontal, Theme.Space.s5)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, Theme.Space.s3)
        .onDisappear {
            sessionTask?.cancel()
            recorder.stop()
        }
    }

    private func begin() {
        sessionTask?.cancel()
        sessionTask = Task {
            for n in stride(from: 3, through: 1, by: -1) {
                guard !Task.isCancelled else { return }
                withAnimation(.snappy) { phase = .countdown(n) }
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
            guard !Task.isCancelled else { return }
            phase = .recording
            recorder.start(simulated: model.simulateTremor, posture: posture) {
                let r = TremorAnalysis.analyze(x: recorder.x, y: recorder.y, z: recorder.z, posture: posture)
                model.activity.add(TremorRecord(date: .now, hand: hand, result: r))
                result = r
                withAnimation(.smooth(duration: 0.35)) { phase = .result }
            }
        }
    }

    private func resultView(_ r: TremorResult) -> some View {
        let previous = model.activity.log.tremor.dropLast().last { $0.result.posture == r.posture && $0.hand == hand }
        let trend = previous.map {
            TrendLabel.compare(r.amplitude, to: $0.result.amplitude, lowerIsBetter: true, tolerance: max(2, $0.result.amplitude * 0.12),
                               better: "Less shake than last time", worse: "More shake than last time")
        }
        let points = zip(TremorResult.spectrumFrequencies, r.spectrum).map { (f: $0, a: $1) }
        return ResultPanel(color: Theme.tremorColor, headline: r.summary, trend: trend) {
            StatTile(value: r.frequency, decimals: 1, unit: "Hz", label: "strongest shake rate", color: Theme.tremorColor)
            StatTile(value: r.amplitude, decimals: 1, unit: "mg", label: "\(r.strengthLabel.lowercased()) movement")
        } extra: {
            Card {
                Text("Shake by speed").font(Theme.font(.headline))
                Chart {
                    RectangleMark(xStart: .value("From", 3.0), xEnd: .value("To", 7.0))
                        .foregroundStyle(Theme.tremorColor.opacity(0.08))
                        .annotation(position: .overlay, alignment: .topLeading) {
                            Text("3–7 Hz").font(Theme.font(.caption2, weight: .semibold)).foregroundStyle(Theme.tremorColor)
                                .padding(4)
                        }
                    ForEach(points, id: \.f) { p in
                        BarMark(x: .value("Hz", p.f), y: .value("Strength", p.a), width: .fixed(6))
                            .foregroundStyle(abs(p.f - r.frequency) < 0.3 ? Theme.tremorColor : Theme.tremorColor.opacity(0.45))
                            .cornerRadius(2)
                    }
                }
                .chartXScale(domain: 0.5...15.5)
                .chartXAxis {
                    AxisMarks(values: [1, 3, 5, 7, 9, 11, 13]) { value in
                        AxisValueLabel { if let f = value.as(Double.self) { Text("\(Int(f))") } }
                    }
                }
                .chartYAxis(.hidden)
                .frame(height: 150)
                Text("Shakes per second (Hz). Slow, rhythmic shake shows on the left; the fine shake everyone has sits around 8–12 Hz.")
                    .font(Theme.font(.footnote))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Card {
                Label("What this is", systemImage: "info.circle.fill")
                    .font(Theme.font(.subheadline, weight: .semibold))
                    .foregroundStyle(Theme.tremorColor)
                Text("A measurement from your phone’s motion sensors, to track over time and share with your doctor. It isn’t a diagnosis: many things change how a hand shakes, including coffee, tiredness and medication timing.")
                    .font(Theme.font(.footnote))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } again: {
            withAnimation(.smooth) {
                result = nil
                phase = .ready
            }
        } done: {
            close()
        }
    }
}

/// A line through the most recent samples, scaled to fit.
struct LiveTrace: Shape {
    var values: [Double]

    func path(in rect: CGRect) -> Path {
        guard values.count > 1 else {
            return Path { $0.move(to: CGPoint(x: rect.minX, y: rect.midY)); $0.addLine(to: CGPoint(x: rect.maxX, y: rect.midY)) }
        }
        let mean = values.reduce(0, +) / Double(values.count)
        let span = max(0.01, values.map { abs($0 - mean) }.max() ?? 0.01)
        return Path { path in
            for (i, v) in values.enumerated() {
                let x = rect.minX + rect.width * CGFloat(i) / CGFloat(values.count - 1)
                let y = rect.midY - CGFloat((v - mean) / span) * rect.height / 2 * 0.9
                if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
        }
    }
}

// MARK: - Voice

struct VoiceSession: View {
    @Environment(AppModel.self) private var model
    let close: () -> Void

    private enum Phase: Equatable { case ready, countdown(Int), listening, denied, result }

    @State private var phase: Phase = .ready
    @State private var meter = VoiceMeter()
    @State private var result: VoiceResult?
    @State private var trace: [Double] = []
    @State private var sessionTask: Task<Void, Never>?

    var body: some View {
        if phase == .result, let result {
            resultView(result)
        } else {
            listenView
        }
    }

    private var listenView: some View {
        let inZone = meter.level >= VoiceAnalysis.target
        return VStack(spacing: Theme.Space.s5) {
            Text("Take a deep breath and say “ahh” as loud as you comfortably can, for six seconds. Think loud!")
                .font(Theme.font(.headline))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.Space.s5)

            GeometryReader { geo in
                let height = geo.size.height
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                        .fill(LinearGradient(colors: PracticeActivity.voice.gradient, startPoint: .top, endPoint: .bottom))
                    // The level, rising from the bottom.
                    RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                        .fill(.white.opacity(inZone ? 0.42 : 0.24))
                        .frame(height: max(0, height * meter.level))
                        .animation(.spring(duration: 0.12), value: meter.level)
                    // The target line.
                    Rectangle()
                        .fill(.white)
                        .frame(height: 3)
                        .overlay(alignment: .trailing) {
                            Text("LOUD ZONE")
                                .font(Theme.font(.caption2, weight: .heavy))
                                .tracking(0.8)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .glassEffect(.regular, in: Capsule())
                                .offset(y: -16)
                                .padding(.trailing, Theme.Space.s3)
                        }
                        .offset(y: -height * VoiceAnalysis.target)
                    VStack(spacing: 4) {
                        switch phase {
                        case .countdown(let n):
                            Text("\(n)").font(Theme.rounded(size: 72, weight: .heavy)).contentTransition(.numericText(countsDown: true))
                        case .listening:
                            Text("\(Int((meter.level * 100).rounded()))")
                                .font(Theme.rounded(size: 72, weight: .heavy))
                                .monospacedDigit()
                                .contentTransition(.numericText())
                            Text(inZone ? "Loud enough. Hold it!" : "Louder!")
                                .font(Theme.rounded(.title3, weight: .bold))
                        case .denied:
                            Image(systemName: "mic.slash.fill").font(.system(size: 44))
                            Text("Microphone is off").font(Theme.rounded(.title3, weight: .bold))
                        default:
                            Image(systemName: "mic.fill").font(.system(size: 52, weight: .semibold))
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                .overlay(alignment: .top) {
                    ProgressView(value: meter.progress)
                        .tint(.white)
                        .padding(Theme.Space.s4)
                        .opacity(phase == .listening ? 1 : 0)
                }
            }
            .padding(.horizontal, Theme.Space.s4)

            Group {
                if phase == .ready {
                    Button {
                        sessionTask?.cancel()
                        sessionTask = Task { await begin() }
                    } label: { Label("Start", systemImage: "mic.fill") }
                        .buttonStyle(.primary(tint: Theme.voiceColor))
                } else if phase == .denied {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                    .buttonStyle(.primary(tint: Theme.voiceColor))
                }
                if model.simulateTremor {
                    Text("Sample voice reading. No microphone measurement is being taken.")
                        .font(Theme.font(.footnote))
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, Theme.Space.s5)
            .padding(.bottom, Theme.Space.s4)
        }
        .padding(.top, Theme.Space.s3)
        .sensoryFeedback(.impact(weight: .medium), trigger: inZone) { _, new in new }
        .onDisappear {
            sessionTask?.cancel()
            meter.stop()
        }
    }

    private func begin() async {
        let simulated = model.simulateTremor
        if !simulated, !(await VoiceMeter.requestPermission()) {
            guard !Task.isCancelled else { return }
            phase = .denied
            return
        }
        for n in stride(from: 3, through: 1, by: -1) {
            guard !Task.isCancelled else { return }
            withAnimation(.snappy) { phase = .countdown(n) }
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
        }
        guard !Task.isCancelled else { return }
        phase = .listening
        let started = meter.start(simulated: simulated) {
            trace = meter.levels
            let r = VoiceAnalysis.analyze(meter.levels, interval: VoiceMeter.interval)
            model.activity.add(VoiceRecord(date: .now, result: r))
            result = r
            withAnimation(.smooth(duration: 0.35)) { phase = .result }
        }
        if !started {
            phase = .ready
            model.notice = "The microphone couldn’t start. No reading was saved. Close other apps using the microphone, then try again."
        }
    }

    private func resultView(_ r: VoiceResult) -> some View {
        let previous = model.activity.log.voice.dropLast().last
        let trend = previous.map {
            TrendLabel.compare(r.inTarget, to: $0.result.inTarget, lowerIsBetter: false, tolerance: 0.05,
                               better: "More time in the loud zone than last time", worse: "Less time in the loud zone than last time")
        }
        let points = trace.enumerated().map { (t: Double($0.offset) * VoiceMeter.interval, v: $0.element) }
        return ResultPanel(color: Theme.voiceColor,
                           headline: r.inTarget >= 0.7 ? "Loud and clear." : r.duration < 2 ? "Let’s try that again, louder." : "Good effort. Aim for the loud zone.",
                           trend: trend) {
            StatTile(value: r.inTarget * 100, unit: "%", label: "in the loud zone", color: Theme.voiceColor)
            StatTile(value: Double(r.score), label: "loudness")
            StatTile(value: r.steadiness * 100, unit: "%", label: "steady")
        } extra: {
            if points.count > 4 {
                Card {
                    Text("Your “ahh”").font(Theme.font(.headline))
                    Chart {
                        RuleMark(y: .value("Loud zone", VoiceAnalysis.target))
                            .foregroundStyle(Theme.voiceColor)
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                            .annotation(position: .top, alignment: .leading) {
                                Text("Loud zone").font(Theme.font(.caption2, weight: .semibold)).foregroundStyle(Theme.voiceColor)
                            }
                        ForEach(points, id: \.t) { p in
                            AreaMark(x: .value("Seconds", p.t), y: .value("Loudness", p.v))
                                .foregroundStyle(LinearGradient(colors: [Theme.voiceColor.opacity(0.4), Theme.voiceColor.opacity(0.02)],
                                                                startPoint: .top, endPoint: .bottom))
                                .interpolationMethod(.monotone)
                            LineMark(x: .value("Seconds", p.t), y: .value("Loudness", p.v))
                                .foregroundStyle(Theme.voiceColor)
                                .interpolationMethod(.monotone)
                        }
                    }
                    .chartYScale(domain: 0...1)
                    .chartYAxis(.hidden)
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) { value in
                            AxisValueLabel { if let t = value.as(Double.self) { Text("\(Int(t)) s") } }
                        }
                    }
                    .frame(height: 140)
                }
            }
            Card {
                Label("Why practise loudness", systemImage: "info.circle.fill")
                    .font(Theme.font(.subheadline, weight: .semibold))
                    .foregroundStyle(Theme.voiceColor)
                Text("Parkinson’s often makes a voice quieter without the person noticing. Speech therapists use loud, sustained “ahh” practice to recalibrate it. This is practice and a record for you, not therapy or a diagnosis; ask your doctor about speech therapy.")
                    .font(Theme.font(.footnote))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } again: {
            withAnimation(.smooth) {
                result = nil
                phase = .ready
            }
        } done: {
            close()
        }
    }
}
