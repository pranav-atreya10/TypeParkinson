import AVFoundation
import CoreMotion
import Foundation
import Observation

/// Records ten seconds of the phone's motion at 100 samples a second for the
/// tremor meter. User acceleration only, with gravity removed. Nothing is kept
/// except the result.
@Observable
final class MotionRecorder {
    private(set) var x: [Double] = []
    private(set) var y: [Double] = []
    private(set) var z: [Double] = []
    /// The latest movement strength (g), for the live trace.
    private(set) var recent: [Double] = []
    private(set) var isRecording = false
    private(set) var progress: Double = 0

    @ObservationIgnored private let manager = CMMotionManager()
    @ObservationIgnored private var playback: Task<Void, Never>?

    var hasSensors: Bool { manager.isDeviceMotionAvailable }

    /// `simulated` plays back a synthetic recording (the simulator has no motion sensors).
    func start(simulated: Bool, posture: TremorPosture, onFinish: @escaping () -> Void) {
        reset()
        isRecording = true
        let total = Int(TremorAnalysis.sampleRate * TremorAnalysis.duration)
        if simulated || !hasSensors {
            let data = TremorAnalysis.simulated(posture: posture)
            playback = Task {
                var i = 0
                while i < total, !Task.isCancelled {
                    let end = min(total, i + 5)
                    for j in i..<end { append(data.x[j], data.y[j], data.z[j], total: total) }
                    i = end
                    try? await Task.sleep(for: .milliseconds(50))
                }
                guard !Task.isCancelled else { return }
                isRecording = false
                onFinish()
            }
            return
        }
        manager.deviceMotionUpdateInterval = 1 / TremorAnalysis.sampleRate
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            MainActor.assumeIsolated {
                guard let self, let a = motion?.userAcceleration, self.isRecording else { return }
                self.append(a.x, a.y, a.z, total: total)
                if self.x.count >= total {
                    self.stop()
                    onFinish()
                }
            }
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        playback?.cancel()
        isRecording = false
    }

    private func reset() {
        stop()
        x = []; y = []; z = []; recent = []; progress = 0
    }

    private func append(_ ax: Double, _ ay: Double, _ az: Double, total: Int) {
        x.append(ax); y.append(ay); z.append(az)
        recent.append(sqrt(ax * ax + ay * ay + az * az))
        if recent.count > 160 { recent.removeFirst(recent.count - 160) }
        progress = Double(x.count) / Double(total)
    }
}

/// Listens to the microphone for the voice exercise and reports loudness
/// twenty times a second. Its temporary audio file is deleted when the meter stops.
@Observable
final class VoiceMeter {
    static let interval = 0.05

    private(set) var level: Double = 0
    private(set) var levels: [Double] = []
    private(set) var isRunning = false
    private(set) var progress: Double = 0

    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private let url = FileManager.default.temporaryDirectory.appendingPathComponent("voice-meter.caf")

    static func requestPermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    @discardableResult
    func start(simulated: Bool, duration: Double = VoiceAnalysis.duration, onFinish: @escaping () -> Void) -> Bool {
        stop()
        levels = []
        progress = 0
        isRunning = true
        if !simulated {
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker])
                try session.setActive(true)
                let recorder = try AVAudioRecorder(url: url, settings: [
                    AVFormatIDKey: kAudioFormatAppleIMA4, AVSampleRateKey: 22_050, AVNumberOfChannelsKey: 1,
                ])
                recorder.isMeteringEnabled = true
                guard recorder.record() else {
                    recorder.deleteRecording()
                    stop()
                    return false
                }
                self.recorder = recorder
            } catch {
                // A hardware failure must never turn into a synthetic voice result.
                // Sample playback is only allowed when explicitly requested above.
                stop()
                return false
            }
        }
        let steps = Int(duration / Self.interval)
        loop = Task {
            for step in 0..<steps {
                guard !Task.isCancelled else { return }
                let value: Double
                if let recorder {
                    recorder.updateMeters()
                    value = VoiceAnalysis.level(fromDecibels: Double(recorder.averagePower(forChannel: 0)))
                } else {
                    // Simulated voice: a quick rise, then a strong "ahh" with a little waver.
                    let t = Double(step) * Self.interval
                    let rise = min(1, t / 0.6)
                    let fade = t > duration - 0.5 ? max(0, (duration - t) / 0.5) : 1
                    value = (0.66 + 0.06 * sin(t * 5) + Double.random(in: -0.03...0.03)) * rise * fade
                }
                level = value
                levels.append(value)
                progress = Double(step + 1) / Double(steps)
                try? await Task.sleep(for: .milliseconds(Int(Self.interval * 1000)))
            }
            guard !Task.isCancelled else { return }
            stop()
            onFinish()
        }
        return true
    }

    func stop() {
        loop?.cancel()
        recorder?.stop()
        recorder?.deleteRecording()
        recorder = nil
        isRunning = false
        level = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
