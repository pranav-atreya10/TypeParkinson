import SwiftUI

/// The first tab: the Aura with today's rings, quick actions, insights,
/// practice, the keyboard and medication.
struct TodayView: View {
    @Environment(AppModel.self) private var model
    @State private var showingCard = false
    @State private var scrolledPastHero = false

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            ZStack(alignment: .top) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.s8) {
                    TodayHero()
                    VStack(alignment: .leading, spacing: Theme.Space.s8) {
                        QuickActions(showCard: { showingCard = true })
                        InsightsSection()
                        PracticeCarousel()
                        KeyboardCard()
                        MedicationCard()
                        ProfileCard()
                        FootNote(model.account == nil
                                 ? "Your touch profile and history stay on this device. TypeParkinson never saves what you type."
                                 : "Your touch profile is kept on this device and in your iCloud. TypeParkinson never saves what you type.")
                            .padding(.horizontal, 4)
                    }
                    .padding(.horizontal, Theme.Space.s4)
                    .frame(maxWidth: 680)
                    .frame(maxWidth: .infinity)
                }
                .padding(.bottom, Theme.Space.s10)
            }
            .background(Theme.bg)
            .ignoresSafeArea(edges: .top)
            .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y > 260 } action: { _, past in
                withAnimation(.easeOut(duration: 0.2)) { scrolledPastHero = past }
            }
            // Once the hero has scrolled away, blur what passes under the clock.
            Color.clear
                .frame(height: 0)
                .background(.bar, ignoresSafeAreaEdges: .top)
                .opacity(scrolledPastHero ? 1 : 0)
                .allowsHitTesting(false)
            }
            .toolbarVisibility(.hidden, for: .navigationBar)
            .sheet(isPresented: $model.showingMedications) { MedicationSheet().environment(model) }
            .fullScreenCover(isPresented: $showingCard) { CommunicationCardView(text: nil).environment(model) }
        }
    }
}

// MARK: - Hero

extension AppModel {
    /// How today's check compares with the person's recent checks.
    var auraMood: AuraMood {
        guard let today = activity.latestCheckIn() else { return .neutral }
        let recent = activity.checkIns.filter { !$0.isSetup && !Calendar.current.isDateInToday($0.date) }.suffix(7).map(\.distance)
        let baseline = recent.isEmpty ? (profile?.taps.map { hypot($0.dx, $0.dy) }.mean ?? today.distance) : recent.mean
        if today.distance < baseline * 0.9 { return .calm }
        if today.distance > baseline * 1.15 { return .restless }
        return .neutral
    }

    /// Today's three goals: a check, two practice sessions, and a voice exercise.
    var todayRings: [DailyRings.Ring] {
        let calendar = Calendar.current
        let practiced = activity.log.practiceDates.filter { calendar.isDateInToday($0) }.count
        let voiced = activity.log.voice.filter { calendar.isDateInToday($0.date) }.count
        return [
            .init(id: "Check", progress: activity.latestCheckIn() == nil ? 0 : 1, color: Color(rgb: 0x5C8BFF)),
            .init(id: "Practice", progress: Double(practiced) / 2, color: Color(rgb: 0x2BE0C8)),
            .init(id: "Voice", progress: Double(voiced), color: Color(rgb: 0xFFC94D)),
        ]
    }
}

private struct TodayHero: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let check = model.activity.latestCheckIn()
        let streak = model.activity.streak()
        let rings = model.todayRings
        VStack(alignment: .leading, spacing: Theme.Space.s5) {
            HStack {
                Text("TypeParkinson")
                    .font(Theme.rounded(.subheadline, weight: .heavy))
                    .foregroundStyle(.white.opacity(0.85))
                Spacer()
                if streak > 0 {
                    GlassTag(text: "\(streak)", symbol: "flame.fill")
                        .accessibilityLabel("\(streak)-day streak")
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .font(Theme.font(.subheadline, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                Text(greeting)
                    .font(Theme.rounded(size: 36, weight: .heavy))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: Theme.Space.s5) {
                DailyRings(rings: rings, lineWidth: 15, gap: 5)
                    .frame(width: 138, height: 138)
                VStack(alignment: .leading, spacing: Theme.Space.s3) {
                    ForEach(rings) { ring in
                        HStack(spacing: 10) {
                            Circle().fill(ring.color).frame(width: 10, height: 10)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(ring.id).font(Theme.rounded(.subheadline, weight: .bold)).foregroundStyle(.white)
                                Text(ringText(ring)).font(Theme.font(.caption)).foregroundStyle(.white.opacity(0.7))
                            }
                        }
                    }
                }
            }
            if let check {
                VStack(alignment: .leading, spacing: Theme.Space.s3) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(check.distance.oneDecimal)
                            .font(Theme.rounded(size: 30, weight: .heavy))
                            .foregroundStyle(.white)
                            .contentTransition(.numericText())
                        Text("pt from target at \(check.date.timeText)")
                            .font(Theme.font(.subheadline, weight: .medium))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    Text(moodSentence(check))
                        .font(Theme.font(.subheadline))
                        .foregroundStyle(.white.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: Theme.Space.s2) {
                        Button("Check again") { model.startRecalibration() }
                            .buttonStyle(GlassPillButtonStyle())
                        if model.todayOffset != nil {
                            Button("Use usual settings") { model.clearToday() }
                                .buttonStyle(GlassPillButtonStyle())
                        }
                    }
                }
            } else {
                VStack(spacing: Theme.Space.s2) {
                    Button { model.startRecalibration() } label: {
                        Label("Start today’s check", systemImage: "hand.tap.fill")
                    }
                    .buttonStyle(AuraPrimaryButtonStyle())
                    Text("Six taps · about 30 seconds · the keys never move")
                        .font(Theme.font(.footnote))
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
        }
        .padding(.horizontal, Theme.Space.s5)
        .padding(.top, 70)
        .padding(.bottom, Theme.Space.s6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            AuraBackground(mood: model.auraMood)
        }
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: Theme.heroRadius, bottomTrailingRadius: Theme.heroRadius, style: .continuous))
        .shadow(color: model.auraMood.glow.opacity(0.35), radius: 24, y: 12)
        .environment(\.colorScheme, .dark)
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        let part = hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening"
        if let first = model.account?.name?.split(separator: " ").first {
            return "\(part),\n\(first)."
        }
        return "\(part)."
    }

    private func ringText(_ ring: DailyRings.Ring) -> String {
        switch ring.id {
        case "Check": ring.progress >= 1 ? "Done" : "Not yet"
        case "Practice": ring.progress >= 1 ? "Done" : "\(Int(ring.progress * 2)) of 2"
        default: ring.progress >= 1 ? "Done" : "Say “ahh”"
        }
    }

    private func moodSentence(_ check: CheckInRecord) -> String {
        switch model.auraMood {
        case .calm: "Steadier than your recent days. Nice."
        case .restless: model.todayOffset != nil
            ? "Touches are landing further off today, so the keyboard is reading them that way until midnight."
            : "Touches are landing further off than usual. You can adjust the keyboard for today."
        case .neutral: "About the same as your recent days."
        }
    }
}

// MARK: - Quick actions

private struct QuickActions: View {
    @Environment(AppModel.self) private var model
    let showCard: () -> Void

    var body: some View {
        HStack(spacing: Theme.Space.s3) {
            action("Speak", "speaker.wave.2.fill", Theme.speakColor) { model.open(.speak) }
            action("Show card", "rectangle.portrait.on.rectangle.portrait.fill", Theme.typingColor, showCard)
            action("Medication", "pills.fill", Theme.medsColor) { model.showingMedications = true }
            action("Tremor", "waveform.path.ecg", Theme.tremorColor) { model.startPractice(.tremor) }
        }
    }

    private func action(_ title: String, _ symbol: String, _ color: Color, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            VStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 50)
                    .background(LinearGradient(colors: [color.opacity(0.85), color], startPoint: .top, endPoint: .bottom),
                                in: Circle())
                    .shadow(color: color.opacity(0.35), radius: 8, y: 4)
                Text(title)
                    .font(Theme.font(.caption, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 96)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }
}

// MARK: - Insights

private struct InsightsSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let insights = Array(InsightEngine.insights(log: model.activity.log).prefix(3))
        if !insights.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.s3) {
                SectionHeader(title: "For you") {
                    Button("All") { model.open(.progress) }
                        .font(Theme.font(.subheadline, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
                ForEach(insights) { insight in
                    InsightRow(insight: insight)
                }
            }
        }
    }
}

struct InsightRow: View {
    let insight: Insight

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.s3) {
            Image(systemName: insight.symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(insight.color.gradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(insight.title).font(Theme.rounded(.headline, weight: .bold))
                Text(insight.detail)
                    .font(Theme.font(.subheadline))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Space.s4)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Practice carousel

private struct PracticeCarousel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s3) {
            SectionHeader(title: "Practice") {
                Button("See all") { model.open(.practice) }
                    .font(Theme.font(.subheadline, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Space.s3) {
                    ForEach(PracticeActivity.allCases) { activity in
                        Button { model.startPractice(activity) } label: {
                            PracticeTile(activity: activity, detail: model.activity.lastResultText(for: activity))
                        }
                        .buttonStyle(PressableStyle())
                        .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                            content
                                .scaleEffect(phase.isIdentity || reduceMotion ? 1 : 0.94)
                                .opacity(phase.isIdentity || reduceMotion ? 1 : 0.85)
                        }
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, Theme.Space.s4)
            }
            .scrollTargetBehavior(.viewAligned)
            .padding(.horizontal, -Theme.Space.s4)
        }
    }
}

/// A tall, colourful card for one activity.
struct PracticeTile: View {
    let activity: PracticeActivity
    var detail: String?
    var width: CGFloat = 220
    var height: CGFloat = 250

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ActivityArt(activity: activity, tint: .white)
                .frame(height: 120)
                .frame(maxWidth: .infinity)
            Spacer(minLength: 0)
            Text(activity.title)
                .font(Theme.rounded(.title3, weight: .heavy))
                .foregroundStyle(.white)
            Text(detail ?? activity.duration)
                .font(Theme.font(.footnote, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Space.s4)
        .frame(width: width, height: height, alignment: .topLeading)
        .background {
            LinearGradient(colors: activity.gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        .overlay(alignment: .topTrailing) {
            Image(systemName: "arrow.up.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .glassEffect(.regular, in: Circle())
                .padding(Theme.Space.s3)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .shadow(color: (activity.gradient.last ?? .black).opacity(0.3), radius: 12, y: 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(activity.title). \(detail ?? activity.duration)")
    }
}

/// Plain press feedback for custom-drawn buttons.
struct PressableStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(reduceMotion ? nil : .spring(duration: 0.25, bounce: 0.35), value: configuration.isPressed)
    }
}

// MARK: - Keyboard

private struct KeyboardCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let settings = model.settings
        let profile = model.profile ?? TouchProfile()
        VStack(alignment: .leading, spacing: Theme.Space.s3) {
            SectionHeader(title: "Your keyboard") {
                if model.todayOffset != nil {
                    Pill(text: "Tuned for today", color: Theme.tappingColor, symbol: "sun.max.fill")
                } else {
                    Pill(text: "Approved", color: Theme.positive, symbol: "checkmark")
                }
            }
            Card(spacing: Theme.Space.s4) {
                KeyboardView(size: settings.keySize, behavior: settings.behavior, theme: settings.theme,
                             largeLabels: settings.largeLabels)
                    .allowsHitTesting(false)
                    .padding(6)
                    .background(settings.theme.palette.background,
                                in: RoundedRectangle(cornerRadius: Theme.cornerRadius + 4, style: .continuous))
                    .accessibilityHidden(true)
                Text("\(settings.keySize.rawValue) keys for your \(profile.hand == .both ? "hands" : profile.hand.rawValue.lowercased())\(settings.pattern.map { ", tuned for \($0.name.lowercased())" } ?? "").")
                    .font(Theme.font(.subheadline))
                    .foregroundStyle(Theme.secondaryText)
                FlowChips(items: chips(settings))
                HStack(spacing: Theme.Space.s2) {
                    Button("Edit") { model.screen = .proposal }
                        .buttonStyle(.secondary(minHeight: 44, fullWidth: false))
                    Button("Try it in Speak") { model.open(.speak) }
                        .buttonStyle(.secondary(minHeight: 44, fullWidth: false))
                    Spacer(minLength: 0)
                }
                Button("Keyboard not showing up in other apps?") { model.screen = .enable }
                    .font(Theme.font(.footnote, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
        }
    }

    private func chips(_ s: KeyboardSettings) -> [String] {
        var items: [String] = []
        if s.smartCorrectionEnabled { items.append("Smart correction") }
        let offset = s.behavior.offset
        if offset != .zero { items.append("Aim \(abs(offset.dx).points) \(offset.dx >= 0 ? "left" : "right"), \(abs(offset.dy).points) \(offset.dy >= 0 ? "up" : "down")") }
        if s.repeatFilterEnabled { items.append("Repeat filter") }
        if s.brushFilterEnabled { items.append("Brush filter") }
        if s.toleranceEnabled { items.append("Tolerance \(s.tolerance.points)") }
        if s.suggestionsEnabled { items.append("Suggestions") }
        return items
    }
}

// MARK: - Medication

private struct MedicationCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s3) {
            SectionHeader(title: "Medication") {
                Button(model.medications.isEmpty ? "Add" : "Edit") { model.showingMedications = true }
                    .font(Theme.font(.subheadline, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
            if model.medications.isEmpty {
                Card {
                    HStack(alignment: .top, spacing: Theme.Space.s3) {
                        IconBadge(symbol: "pills.fill", color: Theme.medsColor, size: 42)
                        Text("Add your medication times for gentle reminders, and to see when in the day your hands are steadiest.")
                            .font(Theme.font(.subheadline))
                            .foregroundStyle(Theme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                VStack(spacing: Theme.Space.s2) {
                    ForEach(model.medications) { med in
                        let taken = model.dosesToday(med)
                        HStack(spacing: Theme.Space.s3) {
                            IconBadge(symbol: "pills.fill", color: Theme.medsColor, size: 42)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(med.name).font(Theme.rounded(.headline, weight: .bold))
                                HStack(spacing: 6) {
                                    ForEach(med.times.sorted(), id: \.self) { time in
                                        let done = taken.count > (med.times.sorted().firstIndex(of: time) ?? 0)
                                        Label(time.text, systemImage: done ? "checkmark.circle.fill" : "circle")
                                            .font(Theme.font(.caption, weight: .semibold))
                                            .foregroundStyle(done ? Theme.positive : Theme.secondaryText)
                                    }
                                }
                            }
                            Spacer(minLength: 0)
                            Button {
                                model.logDose(med)
                            } label: {
                                Text("Took it").font(Theme.font(.subheadline, weight: .bold))
                            }
                            .buttonStyle(TPButtonStyle(minHeight: 40, fullWidth: false, tint: Theme.medsColor))
                            .sensoryFeedback(.success, trigger: taken.count)
                        }
                        .padding(Theme.Space.s4)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
                }
            }
        }
    }
}

/// Chips that wrap onto as many lines as they need.
struct FlowChips: View {
    let items: [String]

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(Theme.font(.footnote, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Theme.surface, in: Capsule())
            }
        }
    }
}

/// Lays children out left to right, wrapping like text.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: min(maxX, width), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

extension ActivityStore {
    /// "Last time: 6.2 pt from the line", or nil before the first try.
    func lastResultText(for activity: PracticeActivity) -> String? {
        switch activity {
        case .spiral:
            spirals.last.map { "Last: \($0.result.deviation.oneDecimal) pt from the line · \(relative($0.date))" }
        case .tapping:
            tapping.last.map { "Last: \($0.result.taps) taps in 10 s · \(relative($0.date))" }
        case .typing:
            typing.last.map { "Last: \($0.wordsPerMinute.wholeNumber) words a minute · \(relative($0.date))" }
        case .tremor:
            log.tremor.last.map { "Last: \($0.result.strengthLabel.lowercased()), \($0.result.frequency.oneDecimal) Hz · \(relative($0.date))" }
        case .voice:
            log.voice.last.map { "Last: \(Int(($0.result.inTarget * 100).rounded()))% in the loud zone · \(relative($0.date))" }
        }
    }

    private func relative(_ date: Date) -> String {
        Calendar.current.isDateInToday(date) ? "today" : date.formatted(.relative(presentation: .named))
    }
}

// MARK: - Profile

private struct ProfileCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let profile = model.profile ?? TouchProfile()
        Card {
            HStack(spacing: Theme.Space.s4) {
                TouchPlot(taps: profile.taps, size: 112, scale: 1.5, dot: 7)
                VStack(alignment: .leading, spacing: Theme.Space.s1) {
                    Text("Touch profile").font(Theme.rounded(.title3, weight: .bold))
                    Text(directionText(profile.meanOffset).map { "Your touches usually land a little \($0)." }
                         ?? "Your touches land close to the centre.")
                        .font(Theme.font(.subheadline))
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: Theme.Space.s3) {
                        Button("View") { model.viewProfile() }
                        Button("Redo exercises") { model.startExercises() }
                    }
                    .font(Theme.font(.subheadline, weight: .semibold))
                    .padding(.top, Theme.Space.s1)
                }
            }
        }
    }
}

// MARK: - Daily check result

struct RecalResultView: View {
    @Environment(AppModel.self) private var model
    @State private var feeling: Feeling?

    var body: some View {
        let usual = model.profile?.taps ?? []
        let today = model.todayTaps
        let shiftVector = CGVector(dx: today.meanOffset.dx - usual.meanOffset.dx,
                                   dy: today.meanOffset.dy - usual.meanOffset.dy)
        let shift = hypot(shiftVector.dx, shiftVector.dy)
        let different = shift > 4
        Page {
            Heading(kicker: "Today vs. usual",
                    title: different ? "Today looks a little different." : "Today looks like usual.",
                    subtitle: different
                        ? "Touches are landing about \(shift.points) further \(directionText(shiftVector) ?? "off centre") than usual. TypeParkinson can read touches differently today. The keys stay exactly where they are."
                        : "Your usual settings should work well. You can still adjust for today if typing feels off.")
            Card {
                HStack(spacing: Theme.Space.s4) {
                    plot(usual, "Usual", Theme.neutral600)
                    plot(today, "Today", Theme.accent)
                }
                .frame(maxWidth: .infinity)
            }
            VStack(alignment: .leading, spacing: Theme.Space.s3) {
                Text("How does typing feel today?").font(Theme.rounded(.title3, weight: .bold))
                FeelingPicker(selection: $feeling)
                FootNote("Optional. Saved with today’s check, so Progress can show how your days compare.")
            }
        } footer: {
            if different {
                Button("Adjust for today") { model.applyToday(feeling: feeling) }.buttonStyle(.primary)
                Button("Keep my usual settings") { model.keepUsual(feeling: feeling) }.buttonStyle(.secondary())
            } else {
                Button("Keep my usual settings") { model.keepUsual(feeling: feeling) }.buttonStyle(.primary)
                Button("Adjust for today anyway") { model.applyToday(feeling: feeling) }.buttonStyle(.secondary())
            }
        }
    }

    private func plot(_ taps: [TapSample], _ label: String, _ color: Color) -> some View {
        VStack(spacing: Theme.Space.s2) {
            TouchPlot(taps: taps, size: 140, scale: 1.6, dot: 8, color: color)
            Text(label).font(Theme.font(.footnote, weight: .semibold)).foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity)
    }
}

struct FeelingPicker: View {
    @Binding var selection: Feeling?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: Theme.Space.s2) {
            ForEach(Feeling.allCases) { feeling in
                let selected = selection == feeling
                Button {
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) { selection = selected ? nil : feeling }
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: feeling.symbol)
                            .symbolRenderingMode(.hierarchical)
                            .font(.system(size: 24))
                            .symbolEffect(.bounce, value: selected)
                            .symbolEffectsRemoved(reduceMotion)
                        Text(feeling.label).font(Theme.font(.footnote, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 76)
                    .foregroundStyle(selected ? .white : Theme.text)
                    .background(selected ? Theme.accent : Theme.card,
                                in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }
}
