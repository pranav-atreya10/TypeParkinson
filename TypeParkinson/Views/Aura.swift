import SwiftUI

/// How the person's hands are doing today, as the Aura shows it.
enum AuraMood: Equatable {
    /// Touches landing closer than usual.
    case calm
    /// No check yet, or about usual.
    case neutral
    /// Touches landing further off than usual.
    case restless

    var colors: [Color] {
        let ink = Color(rgb: 0x0A0F1F)
        switch self {
        case .calm:
            return [ink, Color(rgb: 0x1E46FF), Color(rgb: 0x0C1A44),
                    Color(rgb: 0x14C2BC), Color(rgb: 0x3D6BFF), Color(rgb: 0x3FE0B5),
                    ink, Color(rgb: 0x1F3FB8), ink]
        case .neutral:
            return [ink, Color(rgb: 0x2F5BFF), Color(rgb: 0x16123F),
                    Color(rgb: 0x6E4DFF), Color(rgb: 0x3D7BFF), Color(rgb: 0x16B8C8),
                    ink, Color(rgb: 0x3424A0), ink]
        case .restless:
            return [ink, Color(rgb: 0xFF5F33), Color(rgb: 0x2A0F2E),
                    Color(rgb: 0xDB2F78), Color(rgb: 0xFF8A3D), Color(rgb: 0xFFC94D),
                    ink, Color(rgb: 0x7A1F4A), ink]
        }
    }

    /// Restless days move a little faster; calm days drift.
    var speed: Double {
        switch self {
        case .calm: 0.12
        case .neutral: 0.18
        case .restless: 0.3
        }
    }

    var glow: Color {
        switch self {
        case .calm: Color(rgb: 0x2F5BFF)
        case .neutral: Color(rgb: 0x5A48FF)
        case .restless: Color(rgb: 0xFF5F33)
        }
    }
}

/// The signature: a slowly moving colour field whose colours come from how
/// today's touches compare with usual. Stands still with Reduce Motion.
struct AuraBackground: View {
    var mood: AuraMood = .neutral
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate * mood.speed
            MeshGradient(width: 3, height: 3, points: points(t), colors: mood.colors, smoothsColors: true)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 1.2), value: mood)
        .accessibilityHidden(true)
    }

    private func points(_ t: Double) -> [SIMD2<Float>] {
        func f(_ v: Double) -> Float { Float(v) }
        return [
            [0, 0], [f(0.5 + 0.18 * sin(t)), 0], [1, 0],
            [0, f(0.5 + 0.16 * cos(t * 0.8))],
            [f(0.5 + 0.22 * sin(t * 0.7 + 1)), f(0.5 + 0.2 * cos(t * 0.9))],
            [1, f(0.5 + 0.16 * sin(t * 1.1 + 2))],
            [0, 1], [f(0.5 + 0.18 * cos(t * 0.6)), 1], [1, 1],
        ]
    }
}

/// Concentric progress rings for today's goals, drawn from the outside in.
struct DailyRings: View {
    struct Ring: Identifiable {
        var id: String
        var progress: Double
        var color: Color
    }

    let rings: [Ring]
    var lineWidth: CGFloat = 14
    var gap: CGFloat = 4
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        ZStack {
            ForEach(Array(rings.enumerated()), id: \.element.id) { index, ring in
                let inset = CGFloat(index) * (lineWidth + gap) + lineWidth / 2
                Circle()
                    .stroke(ring.color.opacity(0.28), lineWidth: lineWidth)
                    .padding(inset)
                Circle()
                    .trim(from: 0, to: shown ? max(0.001, min(1, ring.progress)) : 0.001)
                    .stroke(AngularGradient(colors: [ring.color.opacity(0.75), ring.color], center: .center),
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(inset)
                    .shadow(color: ring.color.opacity(ring.progress >= 1 ? 0.6 : 0), radius: 6)
            }
        }
        .onAppear {
            guard !shown else { return }
            if reduceMotion { shown = true } else {
                withAnimation(.spring(duration: 1.1, bounce: 0.2).delay(0.15)) { shown = true }
            }
        }
        .accessibilityElement()
        .accessibilityLabel(rings.map { "\($0.id) \(Int(min(1, $0.progress) * 100)) percent" }.joined(separator: ", "))
    }
}

/// A white pill: the one solid action on a dark Aura.
struct AuraPrimaryButtonStyle: ButtonStyle {
    var tint: Color = Theme.ink
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.rounded(.headline, weight: .bold))
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(.white, in: Capsule())
            .shadow(color: .black.opacity(0.25), radius: 14, y: 6)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .opacity(reduceMotion && configuration.isPressed ? 0.9 : 1)
            .animation(reduceMotion ? nil : .spring(duration: 0.25, bounce: 0.4), value: configuration.isPressed)
    }
}

/// Liquid Glass over the Aura, for secondary actions.
struct GlassPillButtonStyle: ButtonStyle {
    var minHeight: CGFloat = 46
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.rounded(.subheadline, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(minHeight: minHeight)
            .glassEffect(.regular.interactive(), in: Capsule())
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .opacity(reduceMotion && configuration.isPressed ? 0.9 : 1)
            .animation(reduceMotion ? nil : .spring(duration: 0.25, bounce: 0.4), value: configuration.isPressed)
    }
}

/// A small glass label on the Aura, such as the streak.
struct GlassTag: View {
    let text: String
    var symbol: String?

    var body: some View {
        HStack(spacing: 5) {
            if let symbol { Image(systemName: symbol).symbolRenderingMode(.multicolor) }
            Text(text)
        }
        .font(Theme.rounded(.subheadline, weight: .bold))
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .glassEffect(.regular, in: Capsule())
    }
}

/// A full-bleed coloured header for the other tabs: the activity's colour as a soft field.
struct TintField: View {
    var colors: [Color]

    var body: some View {
        MeshGradient(width: 2, height: 2, points: [[0, 0], [1, 0], [0, 1], [1, 1]],
                     colors: colors.count >= 4 ? Array(colors.prefix(4)) : colors + Array(repeating: colors.last ?? .clear, count: 4 - colors.count))
            .accessibilityHidden(true)
    }
}

/// A pale wash of the Aura's colours behind the top of a light page, fading
/// into the background. Gives setup screens the same identity as Today.
struct AuraWash: View {
    var colors: [Color] = [Color(rgb: 0x9DB4FF), Color(rgb: 0xC9B8FF), Color(rgb: 0x9EE8E1), Color(rgb: 0xB8CCFF)]
    var height: CGFloat = 360
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        MeshGradient(width: 2, height: 2, points: [[0, 0], [1, 0], [0, 1], [1, 1]], colors: colors)
            .opacity(colorScheme == .dark ? 0.35 : 0.55)
            .frame(height: height)
            .mask(LinearGradient(colors: [.black, .black.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom))
            .frame(maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    static let speak: [Color] = [Color(rgb: 0x8FE3B8), Color(rgb: 0xA8E6F0), Color(rgb: 0xC5F2C9), Color(rgb: 0x9EDDD0)]
    static let progress: [Color] = [Color(rgb: 0xA9BCFF), Color(rgb: 0xFFC9A8), Color(rgb: 0xB8F0E4), Color(rgb: 0xD5C2FF)]
}
