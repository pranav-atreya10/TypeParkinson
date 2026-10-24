import Foundation
import Observation

/// Text typed with the TypeParkinson keyboard inside the app (Speak, typing
/// practice, the check). The same rules as the system keyboard: smart
/// correction at the end of each word, suggestions, shift and layers, and an
/// undo that puts back exactly what was typed. The cursor is always at the end.
@Observable
final class TextComposer {
    private(set) var text = ""
    var shift: ShiftState = .off
    var mode: KeyboardMode = .letters
    private(set) var suggestions: [String] = []
    private(set) var correction: SuggestionBar.Correction?

    /// Words smart correction changed (and weren't changed back).
    private(set) var autoCorrections = 0
    /// Backspaces, deleted words and undos: the person fixing things themselves.
    private(set) var manualCorrections = 0
    private(set) var startTime: Date?

    var smartCorrection: Bool
    var showsSuggestions: Bool
    var autoCapitalize: Bool

    @ObservationIgnored private let decoder: IntentDecoder
    @ObservationIgnored private let suggester = WordSuggester()
    @ObservationIgnored private var history: [String] = []
    @ObservationIgnored private var wordTouches: [TypedTouch] = []
    @ObservationIgnored private var lastLayout: KeyboardLayout?
    @ObservationIgnored private var isRepeatingDelete = false

    init(settings: KeyboardSettings?, smartCorrection: Bool? = nil, suggestions: Bool? = nil, autoCapitalize: Bool = true) {
        self.smartCorrection = smartCorrection ?? (settings?.smartCorrectionEnabled ?? false)
        self.showsSuggestions = suggestions ?? (settings?.suggestionsEnabled ?? false)
        self.autoCapitalize = autoCapitalize
        decoder = IntentDecoder(model: settings?.touchModel ?? TouchModel(), strength: settings?.correctionStrength ?? 0.6)
        updateShift()
    }

    var isEmpty: Bool { text.isEmpty }

    // MARK: Keys

    func press(_ press: KeyPress) {
        isRepeatingDelete = false
        correction = nil
        switch press.key.action {
        case .character(let c):
            let typed = shift != .off ? c.uppercased() : c
            if c.count == 1, let letter = typed.first, letter.isLetter {
                append(typed)
                wordTouches.append(TypedTouch(character: letter, point: press.point, time: press.time))
                if let layout = press.layout { lastLayout = layout }
            } else if [".", ",", "!", "?", ";", ":"].contains(c) {
                commitWord(then: typed)
            } else {
                append(typed)
                wordTouches = []
            }
            if shift == .once { shift = .off }
            if c == "'" { mode = .letters }
        case .space:
            commitWord(then: " ")
            if mode == .numbers || mode == .symbols { mode = .letters }
        case .returnKey:
            commitWord(then: "\n")
        case .backspace:
            deleteLast()
        case .shift:
            shift = switch shift {
            case .off: .once
            case .once: .capsLock
            case .capsLock: .off
            }
            return
        case .mode(let newMode):
            mode = newMode
        case .nextKeyboard:
            return
        }
        updateShift()
        updateSuggestions()
    }

    func correct(_ action: CorrectionAction) {
        isRepeatingDelete = false
        correction = nil
        switch action {
        case .backspace:
            deleteLast()
        case .deleteWord:
            guard !text.isEmpty else { return }
            remember()
            let spaces = text.reversed().prefix { $0.isWhitespace }.count
            let word = text.dropLast(spaces).reversed().prefix { !$0.isWhitespace }.count
            text.removeLast(word + spaces)
            wordTouches = []
            manualCorrections += 1
        case .undo:
            guard let previous = history.popLast() else { return }
            text = previous
            wordTouches = []
            manualCorrections += 1
        }
        updateShift()
        updateSuggestions()
    }

    /// Each separate hold should be recoverable with one Undo.
    func beginRepeatDelete() {
        isRepeatingDelete = false
    }

    func repeatDelete() {
        correction = nil
        guard !text.isEmpty else { return }
        deleteLast(recordUndo: !isRepeatingDelete)
        isRepeatingDelete = true
        updateShift()
        updateSuggestions()
    }

    /// Replaces the word being typed with a suggestion.
    func pick(_ word: String) {
        isRepeatingDelete = false
        correction = nil
        remember()
        let partial = WordSuggester.partialWord(in: text)
        text.removeLast(partial.count)
        text += word + " "
        wordTouches = []
        if shift == .once { shift = .off }
        updateShift()
        updateSuggestions()
    }

    func insert(phrase: String) {
        isRepeatingDelete = false
        correction = nil
        start()
        remember()
        if let last = text.last, !last.isWhitespace { text += " " }
        text += phrase
        wordTouches = []
        updateShift()
        updateSuggestions()
    }

    /// Puts back what was typed (`nil`) or swaps in an alternative.
    func revertCorrection(to alternative: String?) {
        isRepeatingDelete = false
        guard let correction else { return }
        self.correction = nil
        let current = correction.corrected + correction.separator
        guard text.hasSuffix(current) else { return }
        remember()
        text.removeLast(current.count)
        text += (alternative ?? correction.typed) + correction.separator
        if alternative == nil { autoCorrections = max(0, autoCorrections - 1) }
        updateShift()
        updateSuggestions()
    }

    func clear() {
        isRepeatingDelete = false
        guard !text.isEmpty else { return }
        remember()
        text = ""
        wordTouches = []
        correction = nil
        updateShift()
        updateSuggestions()
    }

    // MARK: Internals

    private func commitWord(then separator: String) {
        let touches = wordTouches
        wordTouches = []
        let typed = String(touches.map(\.character))
        guard smartCorrection, !touches.isEmpty, let layout = lastLayout,
              WordSuggester.partialWord(in: text) == typed else {
            append(separator)
            return
        }
        let centers = IntentDecoder.keyCenters(layout)
        guard let decoded = decoder.decode(touches, keyCenters: centers), decoded.shouldReplace else {
            append(separator)
            return
        }
        remember()
        text.removeLast(typed.count)
        text += decoded.best + separator
        autoCorrections += 1
        correction = SuggestionBar.Correction(typed: typed, corrected: decoded.best, separator: separator,
                                              alternatives: decoded.alternatives.filter { $0.lowercased() != typed.lowercased() })
    }

    private func append(_ s: String) {
        start()
        remember()
        text += s
    }

    private func deleteLast(recordUndo: Bool = true) {
        guard !text.isEmpty else { return }
        if recordUndo { remember() }
        text.removeLast()
        if !wordTouches.isEmpty { wordTouches.removeLast() }
        manualCorrections += 1
    }

    private func start() {
        if startTime == nil { startTime = .now }
    }

    private func remember() {
        history.append(text)
        if history.count > 80 { history.removeFirst() }
    }

    private func updateShift() {
        guard shift != .capsLock else { return }
        guard autoCapitalize, mode == .letters else {
            shift = .off
            return
        }
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let startsSentence = trimmed.isEmpty || text.hasSuffix("\n")
            || (text.hasSuffix(" ") && [".", "!", "?"].contains(trimmed.last))
        shift = startsSentence ? .once : .off
    }

    private func updateSuggestions() {
        guard showsSuggestions, mode == .letters else {
            if !suggestions.isEmpty { suggestions = [] }
            return
        }
        let next = suggester.suggestions(for: text)
        if next != suggestions { suggestions = next }
    }
}
