import CoreGraphics
import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// One letter as it was typed: what the keyboard registered and where the finger actually was.
struct TypedTouch: Equatable {
    var character: Character
    /// The raw touch location in the keyboard's coordinates, before any offset correction.
    /// `nil` for letters that didn't come from a touch (VoiceOver, a picked suggestion).
    var point: CGPoint?
    var time: TimeInterval
}

/// What the decoder made of a word.
struct DecodedWord: Equatable {
    /// Exactly what was typed.
    var typed: String
    /// The most likely intended word, in the typed word's capitalisation.
    var best: String
    /// Next most likely words, best first, not including `best`.
    var alternatives: [String]
    /// Confident enough to replace the typed word without asking.
    var shouldReplace: Bool
}

/// Works out the word a person most likely meant from where each touch
/// landed. Bayes' rule over candidate words:
///
///     score(word) = log P(touches | word) + log P(word)
///
/// P(touches | word) comes from the person's `TouchModel`, aligning touches to
/// letters so a shaky double contact can be dropped and a missed letter
/// supplied. P(word) comes from `WordList`'s ranks, with the system dictionary
/// as a fallback. Runs on the device, in a few milliseconds per word.
final class IntentDecoder {
    var model: TouchModel
    /// 0 to 1: how readily it replaces what was typed.
    var strength: Double

    /// Cost of treating a touch as an accidental extra contact.
    static let dropCost = 3.2
    /// Cheaper when it repeats the previous letter within this window: a bounce.
    static let bounceWindow: TimeInterval = 0.3
    static let bounceDropCost = 0.6
    /// Cost of a letter the person meant but no touch landed for.
    static let insertCost = 3.6
    /// Penalty for a typed string that isn't a word at all.
    static let nonWordPenalty = 12.0
    /// Cost of two neighbouring letters typed in the wrong order ("teh").
    static let transposeCost = 2.0

    #if canImport(UIKit)
    private let checker = UITextChecker()
    #endif
    private let language: String
    private var validity: [String: Bool] = [:]

    init(model: TouchModel = TouchModel(), strength: Double = 0.6) {
        self.model = model
        self.strength = strength
        #if canImport(UIKit)
        language = UITextChecker.availableLanguages.first { $0.hasPrefix("en") } ?? "en_US"
        #else
        language = "en_US"
        #endif
    }

    /// Cached dictionary decisions can contain words from the current typing session.
    /// Keep the numerical touch model, but discard those words when the keyboard closes.
    func clearTransientText() {
        validity.removeAll()
    }

    /// The letter keys' centres in a layout.
    static func keyCenters(_ layout: KeyboardLayout) -> [Character: CGPoint] {
        var centers: [Character: CGPoint] = [:]
        for key in layout.keys where key.isLetter && key.label.count == 1 {
            if let c = key.label.lowercased().first {
                centers[c] = CGPoint(x: key.frame.midX, y: key.frame.midY)
            }
        }
        return centers
    }

    /// `nil` when there's nothing to decide: too short, not all letters, or no touch locations.
    func decode(_ touches: [TypedTouch], keyCenters: [Character: CGPoint]) -> DecodedWord? {
        let typed = String(touches.map(\.character))
        guard typed.count >= 2, typed.allSatisfy(\.isLetter),
              touches.contains(where: { $0.point != nil }), !keyCenters.isEmpty else { return nil }
        // Leave acronyms and names in capitals alone.
        if typed.dropFirst().contains(where: \.isUppercase) { return nil }
        let lower = touches.map { TypedTouch(character: Character($0.character.lowercased()), point: $0.point, time: $0.time) }
        let literal = String(lower.map(\.character))

        var candidates = spatialCandidates(lower, keyCenters: keyCenters)
        candidates.insert(literal)
        for guess in spellingGuesses(literal) { candidates.insert(guess) }

        var scored: [(word: String, score: Double)] = []
        for word in candidates {
            guard let prior = logPrior(word) else { continue }
            scored.append((word, alignmentScore(word, lower, keyCenters: keyCenters) + prior))
        }
        let literalScore = alignmentScore(literal, lower, keyCenters: keyCenters) + (logPrior(literal) ?? -Self.nonWordPenalty)
        scored.sort { $0.score > $1.score }

        guard let top = scored.first else {
            return DecodedWord(typed: typed, best: typed, alternatives: [], shouldReplace: false)
        }
        // A real, common word that was typed is only replaced on strong evidence.
        let literalIsCommon = (WordList.ranks[literal] ?? .max) < 400
        let margin = 1.2 + 3.5 * (1 - strength) + (literalIsCommon ? 2.5 : 0)
        let replace = top.word != literal && top.score - literalScore > margin
        let best = replace ? top.word : literal
        // Single letters other than "a" and "I" are never what someone meant by a whole word.
        let alternatives = scored.map(\.word)
            .filter { $0 != best && ($0.count > 1 || $0 == "a" || $0 == "i") }
            .prefix(3)
        return DecodedWord(typed: typed, best: Self.matchCase(best, to: typed),
                           alternatives: alternatives.map { Self.matchCase($0, to: typed) }, shouldReplace: replace)
    }

    // MARK: Scoring

    /// log P(touches | word): the best alignment of touches to the word's letters,
    /// where a touch can match a letter, be dropped as an extra contact, a
    /// letter can be supplied with no touch, or two neighbouring letters swapped.
    func alignmentScore(_ word: String, _ touches: [TypedTouch], keyCenters: [Character: CGPoint]) -> Double {
        let letters = Array(word)
        let n = touches.count, m = letters.count
        guard m > 0 else { return -.infinity }
        // dp[i][j]: best score aligning the first i touches with the first j letters.
        var dp = Array(repeating: Array(repeating: -Double.infinity, count: m + 1), count: n + 1)
        dp[0][0] = 0
        for i in 0...n {
            for j in 0...m {
                let here = dp[i][j]
                guard here > -.infinity else { continue }
                if i < n, j < m {
                    dp[i + 1][j + 1] = max(dp[i + 1][j + 1], here + match(touches[i], letters[j], keyCenters))
                }
                if i + 1 < n, j + 1 < m, letters[j] != letters[j + 1] {
                    let swapped = match(touches[i], letters[j + 1], keyCenters) + match(touches[i + 1], letters[j], keyCenters)
                    dp[i + 2][j + 2] = max(dp[i + 2][j + 2], here + swapped - Self.transposeCost)
                }
                if i < n {
                    dp[i + 1][j] = max(dp[i + 1][j], here + dropScore(i, touches, keyCenters))
                }
                if j < m {
                    // A letter with no touch costs only the insertion: every touch already
                    // contributes its own likelihood, so no baseline is added for a letter alone.
                    dp[i][j + 1] = max(dp[i][j + 1], here - Self.insertCost)
                }
            }
        }
        return dp[n][m]
    }

    /// Learns from a word the person kept: each matched touch says where they aim for that letter.
    func learn(word: String, touches: [TypedTouch], keyCenters: [Character: CGPoint]) {
        let letters = Array(word.lowercased())
        guard letters.count == touches.count else { return }
        for (touch, letter) in zip(touches, letters) {
            guard let p = touch.point, let c = keyCenters[letter] else { continue }
            model.learn(dx: p.x - c.x, dy: p.y - c.y)
        }
    }

    private func match(_ touch: TypedTouch, _ letter: Character, _ centers: [Character: CGPoint]) -> Double {
        guard let p = touch.point else {
            return touch.character == letter ? matchNeutral() : matchNeutral() - 6
        }
        guard let c = centers[letter] else { return -12 }
        return model.logLikelihood(dx: p.x - c.x, dy: p.y - c.y)
    }

    /// The likelihood of a touch exactly on its key: the baseline a supplied letter is measured against.
    private func matchNeutral() -> Double {
        model.logLikelihood(dx: model.meanX, dy: model.meanY)
    }

    private func dropScore(_ i: Int, _ touches: [TypedTouch], _ centers: [Character: CGPoint]) -> Double {
        let touch = touches[i]
        let isBounce = i > 0 && touches[i - 1].character == touch.character
            && touch.time - touches[i - 1].time < Self.bounceWindow
        return match(touch, touch.character, centers) - (isBounce ? Self.bounceDropCost : Self.dropCost)
    }

    /// log P(word), or nil for something that isn't a word.
    func logPrior(_ word: String) -> Double? {
        if let rank = WordList.ranks[word] { return -log(Double(rank) + 20) }
        return isWord(word) ? -9.0 : nil
    }

    private func isWord(_ word: String) -> Bool {
        if let known = validity[word] { return known }
        #if canImport(UIKit)
        let range = NSRange(location: 0, length: (word as NSString).length)
        let valid = checker.rangeOfMisspelledWord(in: word, range: range, startingAt: 0, wrap: false,
                                                  language: language).location == NSNotFound
        #else
        let valid = false
        #endif
        if validity.count > 4000 { validity.removeAll() }
        validity[word] = valid
        return valid
    }

    // MARK: Candidates

    /// Letter sequences the touches could plausibly have meant: the nearest few
    /// keys for each touch, plus dropping bounces, kept to a beam.
    private func spatialCandidates(_ touches: [TypedTouch], keyCenters: [Character: CGPoint]) -> Set<String> {
        let perTouch = 4
        let beamWidth = 80
        var beam: [(text: String, score: Double)] = [("", 0)]
        for (i, touch) in touches.enumerated() {
            var options: [(Character?, Double)]
            if let p = touch.point {
                options = keyCenters.map { letter, c in (Optional(letter), model.logLikelihood(dx: p.x - c.x, dy: p.y - c.y)) }
                    .sorted { $0.1 > $1.1 }
                    .prefix(perTouch)
                    .map { $0 }
            } else {
                options = [(touch.character, 0)]
            }
            options.append((nil, dropScore(i, touches, keyCenters)))
            var next: [(String, Double)] = []
            for (text, score) in beam {
                for (letter, s) in options {
                    next.append((letter.map { text + String($0) } ?? text, score + s))
                }
            }
            beam = Array(next.sorted { $0.1 > $1.1 }.prefix(beamWidth))
        }
        return Set(beam.map(\.text).filter { $0.count >= 1 && logPrior($0) != nil })
    }

    /// The system's spelling suggestions cover transposed and missing letters the beam can't reach.
    private func spellingGuesses(_ word: String) -> [String] {
        #if canImport(UIKit)
        guard !isWord(word) else { return [] }
        let range = NSRange(location: 0, length: (word as NSString).length)
        return (checker.guesses(forWordRange: range, in: word, language: language) ?? [])
            .filter { !$0.contains(" ") && $0.allSatisfy { $0.isLetter || $0 == "'" } }
            .map { $0.lowercased() }
            .prefix(6)
            .map { $0 }
        #else
        return []
        #endif
    }

    static func matchCase(_ word: String, to typed: String) -> String {
        guard let first = typed.first, first.isUppercase else { return word }
        return word.prefix(1).uppercased() + word.dropFirst()
    }
}

extension TouchPattern {
    /// How readily smart correction replaces a typed word for this pattern.
    var correctionStrength: Double {
        switch self {
        case .steady: 0.4
        case .tremor: 0.75
        case .slowness: 0.5
        case .suddenMovements: 0.9
        case .mixed: 0.7
        }
    }
}
