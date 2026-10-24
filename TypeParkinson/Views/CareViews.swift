import SwiftUI
import UIKit

// MARK: - Medication

/// Medication names and times, reminders with a "Took it" button, and today's log.
struct MedicationSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var medications: [Medication] = []
    @State private var reminderResult = MedicationReminders.ScheduleResult.scheduled
    @State private var showReminderIssue = false
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach($medications) { $med in
                        VStack(alignment: .leading, spacing: Theme.Space.s3) {
                            TextField("Medicine name", text: $med.name)
                                .font(Theme.rounded(.headline, weight: .bold))
                            ForEach(med.times.indices, id: \.self) { i in
                                HStack {
                                    DatePicker("Dose \(i + 1)", selection: Binding(
                                        get: { date(med.times[i]) },
                                        set: { med.times[i] = time($0) }), displayedComponents: .hourAndMinute)
                                    Button {
                                        med.times.remove(at: i)
                                    } label: {
                                        Image(systemName: "minus.circle.fill").foregroundStyle(Theme.warning)
                                            .frame(minWidth: 44, minHeight: 44)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Remove dose \(i + 1)")
                                }
                            }
                            Button {
                                med.times.append(MedTime(hour: 12, minute: 0))
                            } label: {
                                Label("Add a time", systemImage: "plus.circle.fill")
                                    .frame(minHeight: 44, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .foregroundStyle(Theme.medsColor)
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete { medications.remove(atOffsets: $0) }
                    Button {
                        withAnimation { medications.append(Medication(name: "", times: [MedTime(hour: 8, minute: 0)])) }
                    } label: {
                        Label("Add a medicine", systemImage: "pills.fill")
                    }
                    .foregroundStyle(Theme.medsColor)
                } header: {
                    Text("Schedule")
                } footer: {
                    Text("You’ll get a reminder at each time with a Took it button. TypeParkinson only uses the times you log to show when your hands are steadiest; it never suggests doses.")
                }
                let recent = model.activity.log.doses.suffix(8).reversed()
                if !recent.isEmpty {
                    Section("Recently logged") {
                        ForEach(Array(recent)) { dose in
                            LabeledContent(dose.name, value: dose.date.formatted(.dateTime.weekday(.abbreviated).hour().minute()))
                        }
                    }
                }
            }
            .disabled(isSaving)
            .navigationTitle("Medication")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") {
                        guard !isSaving else { return }
                        isSaving = true
                        let cleaned = medications
                            .map { Medication(id: $0.id, name: $0.name.trimmingCharacters(in: .whitespaces), times: Array(Set($0.times)).sorted()) }
                            .filter { !$0.name.isEmpty && !$0.times.isEmpty }
                        Task {
                            defer { isSaving = false }
                            reminderResult = await model.saveMedications(cleaned)
                            if reminderResult == .scheduled { dismiss() } else { showReminderIssue = true }
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(isSaving)
                }
            }
            .alert(reminderResult == .notificationsOff ? "Reminders are off" : "Reminders couldn’t be set", isPresented: $showReminderIssue) {
                if reminderResult == .notificationsOff {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) }
                    }
                    Button("OK", role: .cancel) { dismiss() }
                } else {
                    Button("OK", role: .cancel) { }
                }
            } message: {
                Text(reminderResult == .notificationsOff
                     ? "Your schedule is saved, but reminders need notifications allowed for TypeParkinson in Settings."
                     : "Your schedule is saved, but some reminders couldn’t be set. Please try saving again.")
            }
            .onAppear { medications = model.medications }
        }
    }

    private func date(_ time: MedTime) -> Date {
        var c = DateComponents()
        c.hour = time.hour
        c.minute = time.minute
        return Calendar.current.date(from: c) ?? .now
    }

    private func time(_ date: Date) -> MedTime {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return MedTime(hour: c.hour ?? 8, minute: c.minute ?? 0)
    }
}

// MARK: - Communication card

/// A message in huge type to show someone: for a shop counter, a phone call
/// that's hard to manage, or a moment that needs patience.
struct CommunicationCardView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let text: String?
    @State private var selected = 0

    static let presets = [
        "I have Parkinson’s. Please give me a little extra time.",
        "My voice is quiet. I may type what I want to say.",
        "Could you write that down for me, please?",
        "I need help. Please stay with me.",
        "Thank you for your patience.",
    ]

    private var messages: [String] {
        let typed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (typed.isEmpty ? [] : [typed]) + Self.presets
    }

    var body: some View {
        let message = messages[min(selected, messages.count - 1)]
        ZStack {
            LinearGradient(colors: [Color(rgb: 0x2F5BFF), Color(rgb: 0x1A2A8A)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
            VStack(spacing: Theme.Space.s5) {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 17, weight: .bold))
                            .frame(width: 48, height: 48)
                    }
                    .buttonStyle(GlassPillButtonStyle(minHeight: 48))
                    .accessibilityLabel("Close")
                    Spacer()
                    Button { model.speak(message) } label: {
                        Label("Say it", systemImage: "speaker.wave.2.fill")
                    }
                    .buttonStyle(GlassPillButtonStyle(minHeight: 48))
                }
                Spacer(minLength: 0)
                Text(message)
                    .font(Theme.rounded(size: 64, weight: .heavy))
                    .minimumScaleFactor(0.3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentTransition(.opacity)
                    .id(message)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Space.s2) {
                        ForEach(Array(messages.enumerated()), id: \.offset) { index, item in
                            Button {
                                withAnimation(.smooth(duration: 0.25)) { selected = index }
                            } label: {
                                Text(item)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                    .frame(width: 180, alignment: .leading)
                            }
                            .buttonStyle(GlassPillButtonStyle(minHeight: 60))
                            .opacity(index == selected ? 1 : 0.7)
                        }
                    }
                }
            }
            .padding(Theme.Space.s5)
        }
        .persistentSystemOverlays(.hidden)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }
}
