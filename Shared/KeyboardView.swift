import SwiftUI

enum CorrectionAction {
    case undo, deleteWord, backspace
}

enum ShiftState {
    case off
    /// Capitalises the next letter only.
    case once
    case capsLock
}

/// Simulated imprecision for demos on the simulator, where a mouse is too precise.
struct TouchSimulation {
    /// A fixed displacement applied to the whole of one touch.
    var displacement: () -> CGVector
    /// Chance that a press is followed by an accidental second contact.
    var extraContactChance: Double
}

/// The TypeParkinson keyboard. Used for the in-app typing tasks, Speak, and
/// inside the keyboard extension. Handles each finger separately, so accidental
/// extra contacts reach the interpreter instead of being merged into one gesture.
struct KeyboardView: View {
    var size: KeySize
    var behavior: KeyboardBehavior = .standard
    var options = KeyboardLayout.Options()
    var showsCorrectionBar = false
    var shift: ShiftState = .off
    var theme: KeyboardTheme = .classic
    var largeLabels = false
    /// A larger copy of the key above the finger while it's down.
    var showsKeyPreview = false
    var simulation: TouchSimulation?
    var onPress: (KeyPress) -> Void = { _ in }
    var onBlockedRepeat: () -> Void = {}
    var onIgnoredBrush: () -> Void = {}
    var onCorrection: (CorrectionAction) -> Void = { _ in }
    /// Starts one Undo group when a hold reaches the repeat threshold.
    var onRepeatDeleteStart: () -> Void = {}
    /// Called repeatedly while delete is held down; nil turns hold-to-repeat off.
    var onRepeatDelete: (() -> Void)?

    @State private var interpreter = KeyTouchInterpreter()
    @State private var pressed: [AnyHashable: String] = [:]
    @State private var displacements: [AnyHashable: CGVector] = [:]
    @State private var repeatTasks: [AnyHashable: Task<Void, Never>] = [:]
    /// Touches that already deleted by repeating, so lifting them types nothing more.
    @State private var repeated: Set<AnyHashable> = []

    /// Hold this long before delete starts repeating, then repeat at this interval.
    /// The delay is longer than usual so a slow release doesn't erase text.
    static let repeatDelay: Duration = .milliseconds(800)
    static let repeatInterval: Duration = .milliseconds(110)

    /// Height of the correction bar plus its spacing, when shown.
    static func correctionBarHeight(compact: Bool) -> CGFloat {
        compact ? 34 + 4 : 48 + 8
    }

    var body: some View {
        let palette = theme.palette
        VStack(spacing: options.compact ? 4 : 8) {
            if showsCorrectionBar {
                CorrectionBar(compact: options.compact, palette: palette, largeLabels: largeLabels,
                              onCorrection: onCorrection)
            }
            GeometryReader { geo in
                let layout = KeyboardLayout(size: size, width: geo.size.width, options: options)
                ZStack {
                    ForEach(layout.keys) { key in
                        let isPressed = pressed.values.contains(key.id)
                        KeyCap(key: key, isPressed: isPressed, shift: shift, palette: palette,
                               largeLabels: largeLabels, showsPreview: showsKeyPreview)
                            .frame(width: key.frame.width, height: key.frame.height)
                            .position(x: key.frame.midX, y: key.frame.midY)
                            .zIndex(isPressed ? 1 : 0)
                            .accessibilityAction {
                                onPress(KeyPress(key: key, uncorrectedKey: key))
                            }
                    }
                }
                .frame(width: geo.size.width, height: layout.height)
                .overlay {
                    MultiTouchSurface { handle($0, layout: layout) }
                        .accessibilityHidden(true)
                }
                .accessibilityElement(children: .contain)
            }
            .frame(height: size.keyboardHeight(compact: options.compact))
        }
        .onDisappear {
            repeatTasks.values.forEach { $0.cancel() }
            repeatTasks = [:]
        }
    }

    private func handle(_ event: FingerEvent, layout: KeyboardLayout) {
        let id = AnyHashable(event.id)
        switch event.phase {
        case .began:
            if let simulation { displacements[id] = simulation.displacement() }
            interpreter.began(id, at: simulated(event.location, id), time: event.time)
            track(id, layout: layout)
        case .moved:
            guard interpreter.isTracking(id) else { return }
            interpreter.moved(id, to: simulated(event.location, id))
            track(id, layout: layout)
        case .ended:
            guard interpreter.isTracking(id) else { return }
            let point = simulated(event.location, id)
            finish(id)
            if repeated.remove(id) != nil {
                interpreter.cancel(id)
                return
            }
            deliver(interpreter.ended(id, at: point, time: event.time, layout: layout, behavior: behavior))
            if let simulation, Double.random(in: 0..<1) < simulation.extraContactChance {
                let ghost = AnyHashable(UUID())
                interpreter.began(ghost, at: point, time: event.time + 0.035)
                deliver(interpreter.ended(ghost, at: point, time: event.time + 0.07, layout: layout, behavior: behavior))
            }
        case .cancelled:
            interpreter.cancel(id)
            finish(id)
            repeated.remove(id)
        }
    }

    /// Highlights the key under the finger and starts or stops hold-to-delete.
    private func track(_ id: AnyHashable, layout: KeyboardLayout) {
        let key = interpreter.currentKey(id, layout: layout, behavior: behavior)
        pressed[id] = key?.id
        updateRepeat(id, onDelete: key?.action == .backspace)
    }

    private func finish(_ id: AnyHashable) {
        pressed[id] = nil
        displacements[id] = nil
        repeatTasks.removeValue(forKey: id)?.cancel()
    }

    /// Starts repeating once a touch has rested on delete long enough; stops if it slides off.
    private func updateRepeat(_ id: AnyHashable, onDelete: Bool) {
        guard let onRepeatDelete, onDelete else {
            repeatTasks.removeValue(forKey: id)?.cancel()
            return
        }
        guard repeatTasks[id] == nil else { return }
        let onStart = onRepeatDeleteStart
        repeatTasks[id] = Task {
            do { try await Task.sleep(for: Self.repeatDelay) } catch { return }
            guard !Task.isCancelled else { return }
            onStart()
            while !Task.isCancelled {
                repeated.insert(id)
                onRepeatDelete()
                try? await Task.sleep(for: Self.repeatInterval)
            }
        }
    }

    private func simulated(_ point: CGPoint, _ id: AnyHashable) -> CGPoint {
        guard let d = displacements[id] else { return point }
        return CGPoint(x: point.x + d.dx, y: point.y + d.dy)
    }

    private func deliver(_ outcome: KeyTouchInterpreter.Outcome) {
        switch outcome {
        case .press(let press): onPress(press)
        case .blockedRepeat: onBlockedRepeat()
        case .ignoredBrush: onIgnoredBrush()
        case .none: break
        }
    }
}

private struct KeyCap: View {
    let key: Key
    let isPressed: Bool
    let shift: ShiftState
    let palette: KeyboardTheme.Palette
    let largeLabels: Bool
    let showsPreview: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: Theme.keyRadius, style: .continuous)
            .fill(isPressed ? palette.pressed : (key.isInput ? palette.inputKey : palette.functionKey))
            .shadow(color: palette.keyShadow, radius: 0, x: 0, y: 1)
            .overlay { label }
            .foregroundStyle(isPressed ? palette.pressedLabel : palette.label)
            .overlay(alignment: .bottom) {
                if showsPreview, isPressed, key.isInput { preview }
            }
            .accessibilityElement()
            .accessibilityLabel(accessibilityName)
            .accessibilityValue(key.action == .shift ? shiftDescription : "")
            .accessibilityAddTraits(.isKeyboardKey)
    }

    private var isUppercase: Bool { shift != .off && key.isLetter }
    private var displayLabel: String { isUppercase ? key.label.uppercased() : key.label }
    private var iconSize: CGFloat { largeLabels ? 22 : 18 }

    @ViewBuilder private var label: some View {
        switch key.action {
        case .backspace: Image(systemName: "delete.left").font(.system(size: iconSize, weight: largeLabels ? .semibold : .regular))
        case .shift:
            Image(systemName: shift == .capsLock ? "capslock.fill" : shift == .once ? "shift.fill" : "shift")
                .font(.system(size: iconSize, weight: largeLabels ? .semibold : .regular))
        case .nextKeyboard: Image(systemName: "globe").font(.system(size: iconSize))
        case .space, .returnKey, .mode:
            Text(key.label)
                .font(Theme.font(size: largeLabels ? 17 : 14, weight: largeLabels ? .semibold : .regular))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 2)
        case .character:
            Text(displayLabel)
                .font(Theme.font(size: largeLabels ? 27 : 20, weight: largeLabels ? .semibold : .regular))
        }
    }

    /// The key drawn bigger above the finger, so it's clear which key is about to type.
    private var preview: some View {
        Text(displayLabel)
            .font(Theme.font(size: largeLabels ? 40 : 34, weight: .medium))
            .foregroundStyle(palette.label)
            .frame(width: max(key.frame.width * 1.6, 50), height: key.frame.height * 1.25)
            .background(palette.inputKey, in: RoundedRectangle(cornerRadius: Theme.keyRadius + 4, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.keyRadius + 4, style: .continuous)
                .stroke(palette.pressed, lineWidth: 3))
            .shadow(color: .black.opacity(0.22), radius: 6, x: 0, y: 3)
            .offset(y: -(key.frame.height + 6))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var shiftDescription: String {
        switch shift {
        case .off: "Off"
        case .once: "On"
        case .capsLock: "Caps lock"
        }
    }

    private var accessibilityName: String {
        switch key.action {
        case .backspace: "Delete"
        case .shift: "Shift"
        case .nextKeyboard: "Next keyboard"
        case .returnKey: key.label.capitalized
        case .space: "Space"
        case .mode(.letters): "Letters"
        case .mode(.numbers): "Numbers"
        case .mode(.symbols): "More symbols"
        case .mode(.numberPad): "Number pad"
        case .character(let c):
            switch c {
            case ",": "Comma"
            case ".": "Period"
            case "'": "Apostrophe"
            case "\"": "Quote"
            case "-": "Hyphen"
            case "/": "Slash"
            case "@": "At"
            default: isUppercase ? c.uppercased() : c
            }
        }
    }
}

private struct CorrectionBar: View {
    var compact = false
    let palette: KeyboardTheme.Palette
    var largeLabels = false
    let onCorrection: (CorrectionAction) -> Void

    var body: some View {
        HStack(spacing: 8) {
            button("Undo", icon: "arrow.uturn.backward", .undo)
            button("Delete word", icon: nil, .deleteWord)
            button("Backspace", icon: "delete.left", .backspace)
        }
    }

    private func button(_ title: String, icon: String?, _ action: CorrectionAction) -> some View {
        Button { onCorrection(action) } label: {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon).font(.system(size: 14, weight: .semibold)) }
                Text(title)
            }
            .font(Theme.font(size: largeLabels ? 17 : 15, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, minHeight: compact ? 34 : 48)
            .background(palette.inputKey, in: RoundedRectangle(cornerRadius: Theme.keyRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.keyRadius, style: .continuous).stroke(palette.functionKey))
        }
        .buttonStyle(.plain)
        .foregroundStyle(palette.label)
        .accessibilityLabel(title)
    }
}
