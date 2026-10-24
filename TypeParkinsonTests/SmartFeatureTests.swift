import CoreGraphics
import Foundation
import Testing
@testable import TypeParkinson

// MARK: - Smart correction

@Suite struct IntentDecoderTests {
    private let layout = KeyboardLayout(size: .standard, width: 390, options: .init())
    private var centers: [Character: CGPoint] { IntentDecoder.keyCenters(layout) }

    /// Touches at the centres of the typed letters, optionally nudged, a deliberate 0.4 s apart unless timed.
    private func touches(_ typed: String, nudges: [Int: CGVector] = [:], times: [TimeInterval]? = nil) -> [TypedTouch] {
        typed.enumerated().map { i, c in
            let center = centers[Character(c.lowercased())]!
            let nudge = nudges[i] ?? .zero
            return TypedTouch(character: c, point: CGPoint(x: center.x + nudge.dx, y: center.y + nudge.dy),
                              time: times?[i] ?? Double(i) * 0.4)
        }
    }

    @Test func aTouchThatSlidOntoTheNeighbouringKeyIsFixed() throws {
        // Meant "the": the h landed 15 pt into j.
        let decoded = try #require(IntentDecoder().decode(touches("tje", nudges: [1: CGVector(dx: -15, dy: 0)]), keyCenters: centers))
        #expect(decoded.best == "the")
        #expect(decoded.shouldReplace)
    }

    @Test func tremorBouncesAreDropped() throws {
        // A third l and a second o arrived within a bounce of the previous contact.
        let times: [TimeInterval] = [0, 0.4, 0.8, 1.2, 1.3, 1.7, 1.78]
        let decoded = try #require(IntentDecoder().decode(touches("hellloo", times: times), keyCenters: centers))
        #expect(decoded.best == "hello")
        #expect(decoded.shouldReplace)
    }

    @Test func aMissedLetterIsSupplied() throws {
        let decoded = try #require(IntentDecoder().decode(touches("tomorow"), keyCenters: centers))
        #expect(decoded.best == "tomorrow")
        #expect(decoded.shouldReplace)
    }

    @Test func swappedLettersAreFixed() throws {
        let decoded = try #require(IntentDecoder().decode(touches("teh"), keyCenters: centers))
        #expect(decoded.best == "the")
        #expect(decoded.shouldReplace)
    }

    @Test func aRealWordTypedCleanlyIsLeftAlone() throws {
        for word in ["the", "cat", "dinner", "medicine"] {
            let decoded = try #require(IntentDecoder().decode(touches(word, nudges: [0: CGVector(dx: 3, dy: 2)]), keyCenters: centers))
            #expect(decoded.best == word, "\(word) became \(decoded.best)")
            #expect(!decoded.shouldReplace)
        }
    }

    @Test func capitalisationIsKept() throws {
        let decoded = try #require(IntentDecoder().decode(touches("Teh"), keyCenters: centers))
        #expect(decoded.best == "The")
    }

    @Test func acronymsAndSingleLettersAreNotDecoded() {
        let decoder = IntentDecoder()
        #expect(decoder.decode(touches("I"), keyCenters: centers) == nil)
        let caps = "NASA".map { TypedTouch(character: $0, point: centers[Character($0.lowercased())], time: 0) }
        #expect(decoder.decode(caps, keyCenters: centers) == nil)
    }

    @Test func aPersonalOffsetChangesWhatsLikely() throws {
        // This person's touches land about 30 pt right of where they aim, so a touch
        // centred on j most likely meant h.
        let shifted = IntentDecoder(model: TouchModel(meanX: 30, meanY: 0, sigmaX: 7, sigmaY: 7), strength: 0.6)
        let decoded = try #require(shifted.decode(touches("tje", nudges: [0: CGVector(dx: 30, dy: 0), 2: CGVector(dx: 30, dy: 0)]),
                                                  keyCenters: centers))
        #expect(decoded.best == "the")
    }

    @Test func clearingTransientWordsPreservesPersonalLearning() throws {
        let model = TouchModel(meanX: 30, meanY: 0, sigmaX: 7, sigmaY: 7, samples: 50)
        let decoder = IntentDecoder(model: model, strength: 0.6)
        let input = touches("tje", nudges: [0: CGVector(dx: 30, dy: 0), 2: CGVector(dx: 30, dy: 0)])
        let before = try #require(decoder.decode(input, keyCenters: centers))
        #expect(before.best == "the")
        decoder.clearTransientText()
        #expect(decoder.model == model)
        let after = try #require(decoder.decode(input, keyCenters: centers))
        #expect(after.best == "the")
    }
}

@Suite struct TouchModelTests {
    @Test func learnsWherePeopleActuallyTouch() {
        var model = TouchModel()
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<600 {
            let dx = 6 + Double.random(in: -5...5, using: &generator)
            let dy = -4 + Double.random(in: -5...5, using: &generator)
            model.learn(dx: dx, dy: dy)
        }
        #expect(abs(model.meanX - 6) < 1)
        #expect(abs(model.meanY + 4) < 1)
        // Uniform ±5 has a standard deviation of about 2.9.
        #expect(model.sigmaX > 2 && model.sigmaX < 5)
    }

    @Test func ignoresWildOutliers() {
        var model = TouchModel(meanX: 0, meanY: 0, sigmaX: 6, sigmaY: 6, samples: 50)
        model.learn(dx: 200, dy: 0)
        #expect(model.meanX == 0)
        #expect(model.samples == 50)
    }

    @Test func startsFromTheExercises() {
        let model = TouchModel(taps: TouchProfile.sample.taps, pattern: .tremor)
        #expect(model.meanX > 5)
        #expect(model.sigmaX >= TouchModel.minimumSigma)
    }
}

// MARK: - Pattern classifier

@Suite struct PatternClassifierTests {
    @Test func shakyExercisesReadAsTremor() {
        let estimate = PatternClassifier.classify(PatternClassifier.features(profile: .sample))
        #expect(estimate.primary == .tremor)
        let total = TouchPattern.classified.map { estimate.probability($0) }.reduce(0, +)
        #expect(abs(total - 1) < 0.001)
    }

    @Test func preciseTouchesReadAsSteady() {
        var f = PatternClassifier.Features()
        f.scatter = 2.5
        f.extraContacts = 0
        f.holdMovement = 2
        f.holdDuration = 0.3
        f.pathDeviation = 3
        f.typingRate = 3
        #expect(PatternClassifier.classify(f).primary == .steady)
    }

    @Test func slowAccurateTouchesReadAsSlowness() {
        var f = PatternClassifier.Features()
        f.scatter = 4
        f.extraContacts = 0.1
        f.holdDuration = 0.9
        f.typingRate = 0.7
        f.tappingRate = 24
        #expect(PatternClassifier.classify(f).primary == .slowness)
    }

    @Test func noMeasurementsMeansMixedWithNoEvidence() {
        let estimate = PatternClassifier.classify(PatternClassifier.Features())
        #expect(estimate.primary == .mixed)
        #expect(estimate.evidence == 0)
    }
}

// MARK: - Sensors and practice

@Suite struct SensorAnalysisTests {
    @Test func findsTheTremorFrequencyAndStrength() {
        let data = TremorAnalysis.simulated(posture: .rest, frequency: 5.2, amplitude: 0.03)
        let result = TremorAnalysis.analyze(x: data.x, y: data.y, z: data.z, posture: .rest)
        #expect(abs(result.frequency - 5.2) <= 0.2)
        // x carries 0.03 g and y 0.018 g at that rate (with a slow ±25% wobble): about 35 mg combined.
        #expect(result.amplitude > 25 && result.amplitude < 45)
        #expect(result.summary == "A slow, rhythmic shake.")
    }

    @Test func aStillPhoneReadsAsVeryLittleShake() {
        let n = 1000
        let quiet = (0..<n).map { _ in Double.random(in: -0.0005...0.0005) }
        let result = TremorAnalysis.analyze(x: quiet, y: quiet, z: quiet, posture: .hold)
        #expect(result.amplitude < 4)
        #expect(result.summary == "Very little shake.")
    }

    @Test func fastFineShakeIsDescribedAsSuch() {
        let n = 1000
        let x = (0..<n).map { 0.02 * sin(2 * .pi * 10 * Double($0) / 100) }
        let zeros = Array(repeating: 0.0, count: n)
        let result = TremorAnalysis.analyze(x: x, y: zeros, z: zeros, posture: .hold)
        #expect(abs(result.frequency - 10) <= 0.2)
        #expect(result.summary == "A fast, fine shake.")
    }

    @Test func voiceInTheLoudZone() {
        let levels = Array(repeating: 0.1, count: 10) + Array(repeating: 0.7, count: 100)
        let r = VoiceAnalysis.analyze(levels, interval: 0.05)
        #expect(r.inTarget == 1)
        #expect(r.steadiness > 0.95)
        #expect(abs(r.duration - 5) < 0.01)
    }

    @Test func silenceIsNotAVoice() {
        let r = VoiceAnalysis.analyze(Array(repeating: 0.05, count: 100), interval: 0.05)
        #expect(r.duration == 0)
        #expect(r.inTarget == 0)
    }

    @Test func decibelsMapToLoudness() {
        #expect(VoiceAnalysis.level(fromDecibels: -160) == 0)
        #expect(VoiceAnalysis.level(fromDecibels: 0) == 1)
        #expect(abs(VoiceAnalysis.level(fromDecibels: -30) - 0.5) < 0.001)
    }

    @Test func aPerfectSpiralScoresWell() throws {
        let center = CGPoint(x: 200, y: 200), radius = 150.0
        let trace = Spiral.template(center: center, radius: radius, samples: 400).enumerated()
            .map { TimedPoint(x: $0.element.x, y: $0.element.y, t: Double($0.offset) * 0.02) }
        let r = try #require(Spiral.analyze(trace, center: center, radius: radius))
        #expect(r.deviation < 1)
        #expect(r.smoothness > 0.95)
        #expect(r.coverage > 0.95)
    }

    @Test func aShakySpiralScoresLowerSmoothness() throws {
        let center = CGPoint(x: 200, y: 200), radius = 150.0
        let trace = Spiral.template(center: center, radius: radius, samples: 400).enumerated()
            .map { i, p in TimedPoint(x: p.x + (i.isMultiple(of: 2) ? 4 : -4), y: p.y + (i % 3 == 0 ? 4 : -3), t: Double(i) * 0.02) }
        let r = try #require(Spiral.analyze(trace, center: center, radius: radius))
        #expect(r.smoothness < 0.85)
        #expect(r.deviation > 2)
    }

    @Test func anEvenRhythmIsConsistent() {
        let events = (0..<20).map { TapEvent(time: Double($0) * 0.25, hit: true) }
        let r = Tapping.analyze(events)
        #expect(r.consistency > 0.99)
        #expect(r.accuracy == 1)
        #expect(r.taps == 20)
    }

    @Test func typingScores() {
        #expect(abs(TypingScore.wordsPerMinute(characters: 30, seconds: 30) - 12) < 0.001)
        #expect(TypingScore.accuracy(errors: 3, length: 30) == 0.9)
    }
}

// MARK: - History, insights, achievements

@Suite struct HistoryTests {
    private let calendar = Calendar(identifier: .gregorian)

    @Test func streakCountsBackFromTodayOrYesterday() {
        let today = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
        let days = Set((1...4).compactMap { calendar.date(byAdding: .day, value: -$0, to: today) })
        // Not done today yet: the streak still stands.
        #expect(ActivityStore.streak(days: days, now: today.addingTimeInterval(3600), calendar: calendar) == 4)
        #expect(ActivityStore.streak(days: days.union([today]), now: today, calendar: calendar) == 5)
        let gap = Set([calendar.date(byAdding: .day, value: -3, to: today)!])
        #expect(ActivityStore.streak(days: gap, now: today, calendar: calendar) == 0)
    }

    @Test func olderLogsWithoutNewListsStillLoad() throws {
        let json = #"{"checkIns":[],"spirals":[],"tapping":[],"typing":[]}"#
        let log = try JSONDecoder().decode(ActivityLog.self, from: Data(json.utf8))
        #expect(log.tremor.isEmpty && log.voice.isEmpty && log.doses.isEmpty)
    }

    @Test func storeSavesAndReloads() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("activity-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = ActivityStore(url: url)
        store.add(VoiceRecord(date: .now, result: VoiceResult(level: 0.7, inTarget: 0.8, steadiness: 0.9, duration: 5)))
        #expect(ActivityStore(url: url).log.voice.count == 1)
    }

    @Test func sampleHistoryProducesInsights() {
        let insights = InsightEngine.insights(log: .sample())
        #expect(insights.contains { $0.id == "dose" })
        #expect(insights.contains { $0.id == "time" })
    }

    @Test func insightsNeedEnoughData() {
        #expect(InsightEngine.insights(log: ActivityLog()).isEmpty)
    }

    @Test func achievementsTrackProgress() {
        let badges = Achievements.all(log: ActivityLog(), streak: 2, phrases: 4)
        #expect(badges.first { $0.id == "streak-3" }?.progress ?? 0 > 0.6)
        #expect(badges.first { $0.id == "first-check" }?.earned == false)
        #expect(badges.first { $0.id == "phrases" }?.progress == 0.5)
    }
}

// MARK: - Keyboard details

@Suite struct KeyboardDetailTests {
    private let layout = KeyboardLayout(size: .standard, width: 382, options: .init())

    @Test func aBriefBrushIsIgnored() {
        let interpreter = KeyTouchInterpreter()
        let e = layout.keys.first { $0.id == "e" }!
        let p = CGPoint(x: e.frame.midX, y: e.frame.midY)
        interpreter.began(0, at: p, time: 0)
        guard case .ignoredBrush = interpreter.ended(0, at: p, time: 0.02, layout: layout,
                                                     behavior: KeyboardBehavior(minimumPress: 0.04)) else {
            Issue.record("expected the brush to be ignored")
            return
        }
        interpreter.began(1, at: p, time: 1)
        guard case .press = interpreter.ended(1, at: p, time: 1.1, layout: layout, behavior: KeyboardBehavior(minimumPress: 0.04)) else {
            Issue.record("expected a normal tap to type")
            return
        }
    }

    @Test func pressesCarryWhereTheFingerWas() throws {
        let interpreter = KeyTouchInterpreter()
        let g = layout.keys.first { $0.id == "g" }!
        let p = CGPoint(x: g.frame.midX + 4, y: g.frame.midY + 2)
        interpreter.began(0, at: p, time: 0)
        guard case .press(let press) = interpreter.ended(0, at: p, time: 0.1, layout: layout, behavior: .standard) else {
            Issue.record("expected a press")
            return
        }
        #expect(press.point == p)
        #expect(press.layout != nil)
    }

    @Test func newSettingsDefaultSensiblyAndUnknownThemesFallBack() throws {
        let json = #"{"keySize":"Large","theme":"Neon"}"#
        let settings = try JSONDecoder().decode(KeyboardSettings.self, from: Data(json.utf8))
        #expect(settings.theme == .classic)
        #expect(settings.smartCorrectionEnabled)
        #expect(settings.touchModel == nil)
    }

    @Test func partialWordsAndCase() {
        #expect(WordSuggester.partialWord(in: "see you tom") == "tom")
        #expect(WordSuggester.partialWord(in: "hello ") == "")
        #expect(WordSuggester.matchCase("tomorrow", to: "Tom") == "Tomorrow")
        #expect(WordSuggester.matchCase("tomorrow", to: "TOM") == "TOMORROW")
    }

    @Test func proposedSettingsFollowThePattern() {
        let shaky = TouchProfile.sample.proposedSettings(pattern: .tremor)
        #expect(shaky.brushFilterEnabled && shaky.repeatFilterEnabled && shaky.smartCorrectionEnabled)
        #expect(shaky.touchModel != nil)
        let jumps = TouchProfile.sample.proposedSettings(pattern: .suddenMovements)
        #expect(jumps.keySize == .extraLarge)
    }
}

// MARK: - Care-team exports

@MainActor
@Suite(.serialized) struct ReportExportTests {
    private func contents(_ log: ActivityLog) throws -> String {
        let url = try #require(ReportBuilder.csv(log: log))
        defer { try? FileManager.default.removeItem(at: url) }
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test func anEmptyHistoryHasOnlyTheColumnHeader() throws {
        #expect(try contents(ActivityLog()) == "date,activity,measure,value,unit,detail")
    }

    @Test func sensorAndMedicationHistoryAreIncluded() throws {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        var log = ActivityLog()
        log.tremor = [TremorRecord(date: date, hand: .right,
                                  result: TremorResult(frequency: 5.2, amplitude: 34.9, posture: .rest, duration: 10, spectrum: []))]
        log.voice = [VoiceRecord(date: date, result: VoiceResult(level: 0.7, inTarget: 0.8, steadiness: 0.9, duration: 5))]
        log.doses = [DoseRecord(date: date, medicationID: UUID(), name: "Carbidopa-levodopa")]
        let csv = try contents(log)
        #expect(csv.contains(",tremor,strongest shake rate,5.200,Hz,"))
        #expect(csv.contains(",tremor,shake strength,34.900,mg,"))
        #expect(csv.contains(",voice,time in loud zone,80.000,%,"))
        #expect(csv.contains(",voice,voiced duration,5.000,s,"))
        #expect(csv.contains(",medication,logged dose,1.000,entry,\"Carbidopa-levodopa\""))
        #expect(csv.split(separator: "\n").count == 9)
    }

    @Test func medicationPunctuationAndLineBreaksStayInOneField() throws {
        var log = ActivityLog()
        log.doses = [DoseRecord(date: .now, medicationID: UUID(), name: "Medicine, \"morning\"\nwith food")]
        let csv = try contents(log)
        #expect(csv.hasSuffix("\"Medicine, \"\"morning\"\"\nwith food\""))
    }

    @Test func medicationNamesCannotBecomeSpreadsheetFormulas() throws {
        for name in ["=1+1", "+SUM(A1)", "-2+3", "@SUM(A1)", "  =1+1", "\t=1+1"] {
            var log = ActivityLog()
            log.doses = [DoseRecord(date: .now, medicationID: UUID(), name: name)]
            #expect(try contents(log).hasSuffix("\"'" + name + "\""))
        }
    }
}

// MARK: - Hold-to-delete Undo

@MainActor
@Suite struct TextComposerUndoTests {
    private func composer() -> TextComposer {
        TextComposer(settings: nil, smartCorrection: false, suggestions: false, autoCapitalize: false)
    }

    @Test func oneHoldIsRestoredByOneUndo() {
        let text = composer()
        text.insert(phrase: "hello")
        text.beginRepeatDelete()
        for _ in 0..<3 { text.repeatDelete() }
        #expect(text.text == "he")
        text.correct(.undo)
        #expect(text.text == "hello")
    }

    @Test func separateHoldsHaveSeparateUndoGroups() {
        let text = composer()
        text.insert(phrase: "hello")
        text.beginRepeatDelete()
        for _ in 0..<2 { text.repeatDelete() }
        text.beginRepeatDelete()
        text.repeatDelete()
        #expect(text.text == "he")
        text.correct(.undo)
        #expect(text.text == "hel")
        text.correct(.undo)
        #expect(text.text == "hello")
    }

    @Test func editingDuringARepeatStartsANewUndoGroup() {
        let text = composer()
        text.insert(phrase: "hello")
        text.beginRepeatDelete()
        text.repeatDelete()
        text.insert(phrase: "again")
        #expect(text.text == "hell again")
        text.repeatDelete()
        text.repeatDelete()
        #expect(text.text == "hell aga")
        text.correct(.undo)
        #expect(text.text == "hell again")
    }

    @Test func repeatingDeleteClearsAnObsoleteCorrectionChip() throws {
        let layout = KeyboardLayout(size: .standard, width: 390, options: .init())
        let text = TextComposer(settings: nil, smartCorrection: true, suggestions: false, autoCapitalize: false)
        for (index, letter) in "teh".enumerated() {
            let key = try #require(layout.keys.first { $0.id == String(letter) })
            text.press(KeyPress(key: key, uncorrectedKey: key,
                                point: CGPoint(x: key.frame.midX, y: key.frame.midY),
                                time: Double(index) * 0.4, layout: layout))
        }
        let space = try #require(layout.keys.first { $0.action == .space })
        text.press(KeyPress(key: space, uncorrectedKey: space))
        _ = try #require(text.correction)
        text.beginRepeatDelete()
        text.repeatDelete()
        #expect(text.correction == nil)
    }
}
