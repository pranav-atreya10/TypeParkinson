import SwiftUI

/// Scrolling page for the setup flow, with an optional pinned footer.
struct Page<Content: View, Footer: View>: View {
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.s6) { content }
                .padding(Theme.Space.s5)
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background {
            ZStack(alignment: .top) {
                Theme.bg.ignoresSafeArea()
                AuraWash()
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: Theme.Space.s2) { footer }
                .padding(.horizontal, Theme.Space.s5)
                .padding(.top, Theme.Space.s3)
                .padding(.bottom, Theme.Space.s2)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
                .background(.bar)
        }
    }
}

extension Page where Footer == EmptyView {
    init(@ViewBuilder content: () -> Content) {
        self.init(content: content, footer: { EmptyView() })
    }
}

struct Kicker: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(Theme.font(.caption, weight: .heavy))
            .tracking(0.8)
            .foregroundStyle(Theme.accent600)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.white.opacity(0.7), in: Capsule())
            .overlay(Capsule().stroke(Theme.accent.opacity(0.18)))
    }
}

struct Heading: View {
    let kicker: String?
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s2) {
            if let kicker { Kicker(kicker) }
            Text(title)
                .font(Theme.rounded(size: 34, weight: .heavy))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle)
                    .font(Theme.font(.body))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct FootNote: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(Theme.font(.footnote))
            .foregroundStyle(Theme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: Buttons

enum TPButtonKind { case primary, secondary, destructive, ghost }

struct TPButtonStyle: ButtonStyle {
    var kind: TPButtonKind = .primary
    var minHeight: CGFloat = 54
    var fullWidth = true
    /// Fill for primary buttons; the accent unless an activity has its own colour.
    var tint: Color = Theme.accent

    func makeBody(configuration: Configuration) -> some View {
        StyledButton(configuration: configuration, kind: kind, minHeight: minHeight, fullWidth: fullWidth, tint: tint)
    }

    private struct StyledButton: View {
        let configuration: Configuration
        let kind: TPButtonKind
        let minHeight: CGFloat
        let fullWidth: Bool
        let tint: Color
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(AppModel.self) private var model

        var body: some View {
            let label = configuration.label
                .font(Theme.font(.body, weight: .semibold))
                .multilineTextAlignment(.center)
                .padding(.horizontal, kind == .ghost ? 4 : 18)
                .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: minHeight)
                .foregroundStyle(foreground)
            Group {
                // Ghost buttons are plain links; Liquid Glass is reserved for buttons with a shape.
                if model.liquidGlassEnabled, kind != .ghost {
                    label.glassEffect(glass, in: shape)
                } else {
                    label
                        .background(background, in: shape)
                        .overlay {
                            if kind == .secondary || kind == .destructive {
                                shape.stroke(kind == .destructive ? Theme.warning.opacity(0.4) : Theme.divider, lineWidth: 1)
                            }
                        }
                        .shadow(color: kind == .primary && isEnabled ? tint.opacity(0.35) : .clear, radius: 12, y: 6)
                }
            }
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed && kind != .ghost && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : .spring(duration: 0.2), value: configuration.isPressed)
            .opacity(isEnabled ? 1 : 0.45)
        }

        /// Full-width primary actions are pills; smaller ones keep a rounded rectangle.
        private var shape: AnyShape {
            kind == .primary && fullWidth && minHeight >= 50
                ? AnyShape(Capsule())
                : AnyShape(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
        }

        private var foreground: Color {
            switch kind {
            case .primary: .white
            case .secondary: Theme.text
            case .destructive: Theme.warning
            case .ghost: tint
            }
        }

        private var background: Color {
            let pressed = configuration.isPressed
            switch kind {
            case .primary: return pressed ? tint.opacity(0.85) : tint
            case .secondary: return pressed ? Theme.neutral300 : Theme.card
            case .destructive: return pressed ? Theme.warning.opacity(0.14) : Theme.card
            case .ghost: return pressed ? tint.opacity(0.12) : .clear
            }
        }

        private var glass: Glass {
            switch kind {
            case .primary: .regular.tint(tint).interactive()
            case .destructive: .regular.tint(Theme.warning).interactive()
            case .secondary, .ghost: .regular.interactive()
            }
        }
    }
}

extension ButtonStyle where Self == TPButtonStyle {
    static var primary: TPButtonStyle { TPButtonStyle() }
    static func primary(tint: Color, minHeight: CGFloat = 54) -> TPButtonStyle {
        TPButtonStyle(minHeight: minHeight, tint: tint)
    }
    static func secondary(minHeight: CGFloat = 48, fullWidth: Bool = true) -> TPButtonStyle {
        TPButtonStyle(kind: .secondary, minHeight: minHeight, fullWidth: fullWidth)
    }
    static func destructive(minHeight: CGFloat = 44, fullWidth: Bool = false) -> TPButtonStyle {
        TPButtonStyle(kind: .destructive, minHeight: minHeight, fullWidth: fullWidth)
    }
    static func ghost(minHeight: CGFloat = 44, tint: Color = Theme.accent) -> TPButtonStyle {
        TPButtonStyle(kind: .ghost, minHeight: minHeight, fullWidth: false, tint: tint)
    }
}

// MARK: Segmented choice

/// Large-target segmented control: every segment is at least 44 pt tall.
struct SegmentedChoice<Value: Hashable>: View {
    let options: [(label: String, value: Value)]
    @Binding var selection: Value
    var tint: Color = Theme.accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let selected = option.value == selection
                Button {
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) { selection = option.value }
                } label: {
                    Text(option.label)
                        .font(Theme.font(.subheadline, weight: selected ? .semibold : .regular))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(selected ? .white : Theme.text)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: Theme.cornerRadius - 2, style: .continuous).fill(tint)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerRadius + 2, style: .continuous))
        .fixedSize(horizontal: false, vertical: true)
    }
}

extension SegmentedChoice where Value == Bool {
    init(onOff selection: Binding<Bool>) {
        self.init(options: [("On", true), ("Off", false)], selection: selection)
    }
}

// MARK: Touch plot

/// Where taps landed around the target centre: dots, plus a ring for the average.
struct TouchPlot: View {
    let taps: [TapSample]
    var size: CGFloat = 260
    var scale: CGFloat = 3
    var dot: CGFloat = 10
    /// Colours every dot the same instead of by hit / miss.
    var color: Color?
    var background: Color = Theme.surface

    var body: some View {
        let centre = size / 2
        let mean = taps.meanOffset
        ZStack {
            ForEach([0.85, 0.6, 0.35], id: \.self) { fraction in
                Circle()
                    .stroke(Theme.neutral400.opacity(0.5), lineWidth: 1)
                    .frame(width: size * fraction, height: size * fraction)
            }
            Theme.neutral400.opacity(0.4).frame(width: 1, height: size)
            Theme.neutral400.opacity(0.4).frame(width: size, height: 1)
            Circle().fill(Theme.neutral400.opacity(0.25)).frame(width: size * 0.12, height: size * 0.12)
            ForEach(Array(taps.enumerated()), id: \.offset) { _, tap in
                Circle()
                    .fill(color ?? (tap.hit ? Theme.accent : Theme.neutral600))
                    .frame(width: dot, height: dot)
                    .overlay(Circle().stroke(background, lineWidth: 1.5))
                    .position(clamped(centre + tap.dx * scale, centre + tap.dy * scale))
            }
            if !taps.isEmpty {
                Circle()
                    .stroke(Theme.text, lineWidth: 2.5)
                    .frame(width: dot + 10, height: dot + 10)
                    .position(clamped(centre + mean.dx * scale, centre + mean.dy * scale))
            }
        }
        .frame(width: size, height: size)
        .background(background, in: RoundedRectangle(cornerRadius: Theme.cornerRadius + 4, style: .continuous))
        .accessibilityElement()
        .accessibilityLabel("Plot of \(taps.count) touches around the target centre")
    }

    private func clamped(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        let inset = dot / 2 + 2
        return CGPoint(x: min(max(x, inset), size - inset), y: min(max(y, inset), size - inset))
    }
}

struct PlotLegend: View {
    var body: some View {
        HStack(spacing: 16) {
            item(Circle().fill(Theme.accent), "On target")
            item(Circle().fill(Theme.neutral600), "Missed")
            item(Circle().stroke(Theme.text, lineWidth: 2), "Average")
        }
        .font(Theme.font(.caption))
        .foregroundStyle(Theme.secondaryText)
    }

    private func item(_ swatch: some View, _ label: String) -> some View {
        HStack(spacing: 6) {
            swatch.frame(width: 10, height: 10)
            Text(label)
        }
    }
}

// MARK: Touch capture

extension View {
    /// Reports each finger's down / move / up separately, so extra contacts are visible.
    func onTouches(
        began: @escaping (AnyHashable, CGPoint) -> Void,
        moved: @escaping (AnyHashable, CGPoint) -> Void = { _, _ in },
        ended: @escaping (AnyHashable, CGPoint) -> Void = { _, _ in }
    ) -> some View {
        modifier(TouchCapture(began: began, moved: moved, ended: ended))
    }
}

private struct TouchCapture: ViewModifier {
    let began: (AnyHashable, CGPoint) -> Void
    let moved: (AnyHashable, CGPoint) -> Void
    let ended: (AnyHashable, CGPoint) -> Void

    func body(content: Content) -> some View {
        content
            .overlay {
                MultiTouchSurface { event in
                    let id = AnyHashable(event.id)
                    switch event.phase {
                    case .began: began(id, event.location)
                    case .moved: moved(id, event.location)
                    case .ended, .cancelled: ended(id, event.location)
                    }
                }
            }
    }
}
