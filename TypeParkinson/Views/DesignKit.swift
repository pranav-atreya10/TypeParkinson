import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Cards

/// A white block on the grey page.
struct Card<Content: View>: View {
    var padding: CGFloat = Theme.Space.s4
    var spacing: CGFloat = Theme.Space.s3
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }
}

/// A card that is itself the button. Shrinks a touch when pressed.
struct CardButtonStyle: ButtonStyle {
    var padding: CGFloat = Theme.Space.s4
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .foregroundStyle(Theme.text)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(reduceMotion ? nil : .spring(duration: 0.2), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == CardButtonStyle {
    static var card: CardButtonStyle { CardButtonStyle() }
}

struct SectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(Theme.rounded(.title2, weight: .bold))
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Theme.Space.s2)
            trailing
        }
        .padding(.horizontal, 4)
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(_ title: String) {
        self.init(title: title, trailing: { EmptyView() })
    }
}

// MARK: - Numbers

/// A display figure that counts up the first time it appears.
struct BigNumber: View {
    let value: Double
    var decimals = 0
    var size: CGFloat = 44
    var color: Color = Theme.text

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Double?

    var body: some View {
        Text((shown ?? value).formatted(.number.precision(.fractionLength(decimals))))
            .font(Theme.rounded(size: size, weight: .bold))
            .foregroundStyle(color)
            .monospacedDigit()
            .contentTransition(reduceMotion ? .identity : .numericText(value: shown ?? value))
            .accessibilityLabel(value.formatted(.number.precision(.fractionLength(decimals))))
            .onAppear {
                guard shown == nil else { return }
                guard !reduceMotion else { shown = value; return }
                shown = 0
                withAnimation(.smooth(duration: 0.9).delay(0.1)) { shown = value }
            }
            .onChange(of: value) { _, new in
                guard !reduceMotion else { shown = new; return }
                withAnimation(.smooth(duration: 0.4)) { shown = new }
            }
            .onChange(of: reduceMotion) { _, enabled in
                if enabled { shown = value }
            }
    }
}

/// A number, its unit and what it means.
struct StatTile: View {
    let value: Double
    var decimals = 0
    var unit: String?
    let label: String
    var color: Color = Theme.text

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                BigNumber(value: value, decimals: decimals, size: 30, color: color)
                if let unit {
                    Text(unit)
                        .font(Theme.rounded(.subheadline, weight: .semibold))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            Text(label)
                .font(Theme.font(.footnote))
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// "Better than last time" with an arrow, never colour alone.
struct TrendLabel: View {
    enum Direction { case better, worse, same }

    let direction: Direction
    let text: String

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: icon).font(.system(size: 12, weight: .bold))
        }
        .font(Theme.font(.footnote, weight: .semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(color.opacity(0.12), in: Capsule())
        .accessibilityLabel(text)
    }

    private var icon: String {
        switch direction {
        case .better: "arrow.up.right"
        case .worse: "arrow.down.right"
        case .same: "equal"
        }
    }

    private var color: Color {
        switch direction {
        case .better: Theme.positive
        case .worse: Theme.warning
        case .same: Theme.secondaryText
        }
    }

    /// Compares two values where lower or higher is better, with a dead band so noise reads as "same".
    static func compare(_ current: Double, to previous: Double, lowerIsBetter: Bool, tolerance: Double,
                        better: String, worse: String, same: String = "About the same as last time") -> TrendLabel {
        let delta = current - previous
        if abs(delta) <= tolerance { return TrendLabel(direction: .same, text: same) }
        let improved = lowerIsBetter ? delta < 0 : delta > 0
        return TrendLabel(direction: improved ? .better : .worse, text: improved ? better : worse)
    }
}

/// An SF Symbol on a tinted rounded square, in an activity's colour.
struct IconBadge: View {
    let symbol: String
    var color: Color = Theme.accent
    var size: CGFloat = 44

    var body: some View {
        Image(systemName: symbol)
            .symbolRenderingMode(.hierarchical)
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// A small coloured label.
struct Pill: View {
    let text: String
    var color: Color = Theme.accent
    var symbol: String?

    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).font(.system(size: 11, weight: .bold)) }
            Text(text)
        }
        .font(Theme.font(.caption, weight: .semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(color.opacity(0.13), in: Capsule())
    }
}

// MARK: - Week strip

/// The last seven days, one mark per day with any activity.
struct WeekStrip: View {
    let activeDays: Set<Date>
    var color: Color = Theme.accent
    var now: Date = .now
    var calendar: Calendar = .current

    var body: some View {
        let today = calendar.startOfDay(for: now)
        let days = (0..<7).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
        HStack(spacing: 6) {
            ForEach(days, id: \.self) { day in
                let active = activeDays.contains(day)
                let isToday = day == today
                VStack(spacing: 6) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(active ? color : Theme.surface)
                        if isToday && !active {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(color, style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                        }
                        if active {
                            Image(systemName: "checkmark")
                                .font(.system(size: 13, weight: .heavy))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(height: 40)
                    Text(day.formatted(.dateTime.weekday(.narrow)))
                        .font(Theme.font(.caption, weight: isToday ? .bold : .medium))
                        .foregroundStyle(isToday ? Theme.text : Theme.secondaryText)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(day.formatted(.dateTime.weekday(.wide))): \(active ? "done" : isToday ? "not yet" : "nothing")")
            }
        }
    }
}

// MARK: - Share sheet

#if canImport(UIKit)
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// A file to share, so `.sheet(item:)` can present it.
struct SharedFile: Identifiable {
    let url: URL
    var id: URL { url }
}
#endif

// MARK: - Formatting

extension Double {
    var oneDecimal: String { formatted(.number.precision(.fractionLength(1))) }
    var wholeNumber: String { formatted(.number.precision(.fractionLength(0))) }
}

extension Date {
    /// "9:14 AM"
    var timeText: String { formatted(date: .omitted, time: .shortened) }
    /// "Oct 20"
    var shortDay: String { formatted(.dateTime.month(.abbreviated).day()) }
}

extension PracticeActivity {
    var color: Color {
        switch self {
        case .spiral: Theme.spiralColor
        case .tapping: Theme.tappingColor
        case .typing: Theme.typingColor
        case .tremor: Theme.tremorColor
        case .voice: Theme.voiceColor
        }
    }

    /// Two stops for the activity's card: its colour and a deeper shade.
    var gradient: [Color] {
        switch self {
        case .spiral: [Color(rgb: 0x0FB5AE), Color(rgb: 0x0A6E8A)]
        case .tapping: [Color(rgb: 0xFF7A45), Color(rgb: 0xD9364F)]
        case .typing: [Color(rgb: 0xF0468E), Color(rgb: 0x8E2BB8)]
        case .tremor: [Color(rgb: 0x7D5CFF), Color(rgb: 0x3B2BB8)]
        case .voice: [Color(rgb: 0xFFB020), Color(rgb: 0xF06A1F)]
        }
    }
}
