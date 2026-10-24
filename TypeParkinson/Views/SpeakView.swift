import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Type something and have it read aloud: for when speaking is harder than
/// typing, or a voice is too quiet to be heard. Uses the person's own keyboard,
/// smart correction and saved phrases, so it also works before the system
/// keyboard is turned on.
struct SpeakView: View {
    @Environment(AppModel.self) private var model
    @State private var composer: TextComposer?
    @State private var showingPhrases = false
    @State private var editingPhrases = false
    @State private var copied = false
    @State private var showingCard = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let composer {
                    content(composer)
                }
            }
.background {
                ZStack(alignment: .top) {
                    Theme.bg.ignoresSafeArea()
                    AuraWash(colors: AuraWash.speak)
                }
            }
            .navigationTitle("Speak")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Voice speed", selection: Binding(get: { model.speaker.rate }, set: { model.speaker.rate = $0 })) {
                            ForEach(Speaker.Rate.allCases) { Text($0.label).tag($0) }
                        }
                    } label: {
                        Label("Voice speed", systemImage: "speedometer")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingCard = true } label: {
                        Label("Show card", systemImage: "rectangle.portrait.on.rectangle.portrait.fill")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Phrases") { editingPhrases = true }
                }
            }
            .sheet(isPresented: $editingPhrases) {
                PhraseEditor().environment(model)
            }
            .fullScreenCover(isPresented: $showingCard) {
                CommunicationCardView(text: composer?.text).environment(model)
            }
        }
        .onAppear {
            if composer == nil {
                composer = TextComposer(settings: model.settings, smartCorrection: model.settings.smartCorrectionEnabled,
                                        suggestions: true, autoCapitalize: true)
            }
        }
    }

    @ViewBuilder
    private func content(_ composer: TextComposer) -> some View {
        let settings = model.settings
        let palette = settings.theme.palette
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.s3) {
                textCard(composer)
                actions(composer)
                if !model.recentlySpoken.isEmpty {
                    recent
                }
            }
            .padding(Theme.Space.s4)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)

        VStack(spacing: 6) {
            SuggestionBar(suggestions: composer.suggestions, correction: composer.correction,
                          showsPhrasesButton: true, isShowingPhrases: showingPhrases,
                          palette: palette, largeLabels: settings.largeLabels,
                          onPick: { composer.pick($0) },
                          onTogglePhrases: { withAnimation(.snappy(duration: 0.2)) { showingPhrases.toggle() } },
                          onRevert: { composer.revertCorrection(to: nil) },
                          onPickAlternative: { composer.revertCorrection(to: $0) })
            if showingPhrases {
                PhrasePanel(phrases: model.phrases, palette: palette,
                            height: settings.keySize.keyboardHeight(compact: false) + (settings.correctionBarEnabled ? KeyboardView.correctionBarHeight(compact: false) : 0),
                            largeLabels: settings.largeLabels) { phrase in
                    composer.insert(phrase: phrase.text)
                    model.speak(phrase.text)
                    showingPhrases = false
                }
            } else {
                KeyboardView(
                    size: settings.keySize,
                    behavior: settings.behavior,
                    options: KeyboardLayout.Options(systemKeys: true, mode: composer.mode, showsGlobe: false, returnLabel: "speak"),
                    showsCorrectionBar: settings.correctionBarEnabled,
                    shift: composer.shift,
                    theme: settings.theme,
                    largeLabels: settings.largeLabels,
                    showsKeyPreview: settings.keyPreviewEnabled,
                    simulation: model.simulator.keyboardSimulation,
                    onPress: { press in
                        if press.key.action == .returnKey {
                            model.speak(composer.text)
                        } else {
                            composer.press(press)
                        }
                    },
                    onCorrection: { composer.correct($0) },
                    onRepeatDeleteStart: { composer.beginRepeatDelete() },
                    onRepeatDelete: settings.holdToDeleteEnabled ? { composer.repeatDelete() } : nil
                )
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(palette.background)
    }

    private func textCard(_ composer: TextComposer) -> some View {
        ZStack(alignment: .topLeading) {
            if composer.text.isEmpty {
                Text("Type what you want to say, then tap Speak.")
                    .font(Theme.rounded(.title2, weight: .medium))
                    .foregroundStyle(Theme.neutral400)
            }
            (Text(composer.text) + Text("|").foregroundStyle(Theme.speakColor))
                .font(Theme.rounded(.title2, weight: .medium))
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .accessibilityLabel(composer.text.isEmpty ? "Nothing typed yet" : composer.text)
        }
        .padding(Theme.Space.s5)
        .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .stroke(Theme.speakColor.opacity(model.speaker.isSpeaking ? 0.9 : 0), lineWidth: 3)
        }
        .shadow(color: model.speaker.isSpeaking ? Theme.speakColor.opacity(0.35) : .black.opacity(0.06),
                radius: model.speaker.isSpeaking ? 20 : 12, y: 6)
        .animation(.easeInOut(duration: 0.3), value: model.speaker.isSpeaking)
        .overlay(alignment: .topTrailing) {
            if model.speaker.isSpeaking {
                Image(systemName: "waveform")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.speakColor)
                    .symbolEffect(.variableColor.iterative, isActive: true)
                    .padding(Theme.Space.s4)
                    .accessibilityLabel("Speaking")
            }
        }
    }

    private func actions(_ composer: TextComposer) -> some View {
        HStack(spacing: Theme.Space.s2) {
            Button {
                if model.speaker.isSpeaking { model.speaker.stop() } else { model.speak(composer.text) }
            } label: {
                Label(model.speaker.isSpeaking ? "Stop" : "Speak",
                      systemImage: model.speaker.isSpeaking ? "stop.fill" : "speaker.wave.2.fill")
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(TPButtonStyle(minHeight: 54, tint: Theme.speakColor))
            .disabled(composer.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !model.speaker.isSpeaking)

            iconButton(copied ? "checkmark" : "doc.on.doc", label: "Copy") {
                #if canImport(UIKit)
                UIPasteboard.general.string = composer.text
                #endif
                copied = true
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    copied = false
                }
            }
            .disabled(composer.text.isEmpty)

            ShareLink(item: composer.text) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 54, height: 54)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            }
            .disabled(composer.text.isEmpty)
            .accessibilityLabel("Share")

            iconButton("trash", label: "Clear") { composer.clear() }
                .disabled(composer.text.isEmpty)
        }
        .sensoryFeedback(.success, trigger: copied) { _, new in new }
    }

    private func iconButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 54, height: 54)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
    }

    private var recent: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s2) {
            HStack {
                Text("SAID RECENTLY")
                    .font(Theme.font(.caption, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(Theme.secondaryText)
                Spacer()
                Button("Clear") { model.clearRecentlySpoken() }
                    .font(Theme.font(.caption, weight: .semibold))
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Space.s2) {
                    ForEach(model.recentlySpoken, id: \.self) { line in
                        Button { model.speak(line) } label: {
                            Label(line, systemImage: "speaker.wave.2")
                                .font(Theme.font(.subheadline, weight: .medium))
                                .lineLimit(1)
                                .padding(.horizontal, 14)
                                .frame(minHeight: 44)
                                .background(Theme.card, in: Capsule())
                        }
                        .buttonStyle(PressableStyle())
                        .frame(maxWidth: 260)
                    }
                }
            }
        }
    }
}

/// Add, edit, reorder and delete saved phrases. They appear in Speak and in
/// the keyboard's Phrases panel in every app.
struct PhraseEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var phrases: [QuickPhrase] = []
    @State private var draft = ""
    @FocusState private var adding: Bool

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("Add a phrase you use often", text: $draft, axis: .vertical)
                            .focused($adding)
                            .submitLabel(.done)
                            .onSubmit(add)
                        Button("Add", action: add)
                            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                } footer: {
                    Text("Phrases appear in Speak and behind the Phrases button on your keyboard, in every app.")
                }
                Section("Your phrases") {
                    ForEach($phrases) { $phrase in
                        TextField("Phrase", text: $phrase.text, axis: .vertical)
                    }
                    .onDelete { phrases.remove(atOffsets: $0) }
                    .onMove { phrases.move(fromOffsets: $0, toOffset: $1) }
                    if phrases.isEmpty {
                        Text("No phrases yet.").foregroundStyle(Theme.secondaryText)
                    }
                }
                Section {
                    Button("Restore the starter phrases") { phrases = QuickPhrase.starters }
                }
            }
            .font(Theme.font(.body))
            .navigationTitle("Phrases")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        model.savePhrases(phrases.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear { phrases = model.phrases }
        }
    }

    private func add() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        withAnimation { phrases.insert(QuickPhrase(text: text), at: 0) }
        draft = ""
    }
}
