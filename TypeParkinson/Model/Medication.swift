import Foundation
import UserNotifications

/// A medicine the person takes on a schedule. Only what they type in: a name
/// and times. TypeParkinson never suggests doses.
struct Medication: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var times: [MedTime]
}

struct MedTime: Codable, Hashable, Comparable {
    var hour: Int
    var minute: Int

    var text: String {
        var c = DateComponents()
        c.hour = hour
        c.minute = minute
        return (Calendar.current.date(from: c) ?? .now).formatted(date: .omitted, time: .shortened)
    }

    static func < (a: MedTime, b: MedTime) -> Bool { (a.hour, a.minute) < (b.hour, b.minute) }
}

/// "Took it": logged from the app or straight from the reminder.
struct DoseRecord: Codable, Identifiable, Equatable {
    var id = UUID()
    var date: Date
    var medicationID: UUID
    var name: String
}

enum MedicationReminders {
    enum ScheduleResult: Equatable {
        case scheduled
        case notificationsOff
        case failed
    }

    static let category = "MEDICATION"
    static let tookItAction = "TOOK_IT"
    static let prefix = "med-"

    /// The "Took it" button on medication reminders.
    static func registerCategory() {
        let tookIt = UNNotificationAction(identifier: tookItAction, title: "Took it", options: [])
        let category = UNNotificationCategory(identifier: category, actions: [tookIt], intentIdentifiers: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    /// Replaces medication reminders, reporting permission and scheduling failures separately.
    static func schedule(_ medications: [Medication]) async -> ScheduleResult {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        guard !medications.isEmpty else { return .scheduled }
        do {
            guard try await center.requestAuthorization(options: [.alert, .sound]) else { return .notificationsOff }
        } catch {
            return .failed
        }
        registerCategory()
        var failed = false
        for med in medications {
            for (i, time) in med.times.enumerated() {
                let content = UNMutableNotificationContent()
                content.title = "Time for \(med.name)"
                content.body = "Tap Took it to log it. Logging doses shows when your hands are steadiest."
                content.sound = .default
                content.categoryIdentifier = category
                content.userInfo = ["medicationID": med.id.uuidString, "name": med.name]
                var c = DateComponents()
                c.hour = time.hour
                c.minute = time.minute
                let request = UNNotificationRequest(identifier: "\(prefix)\(med.id.uuidString)-\(i)", content: content,
                                                    trigger: UNCalendarNotificationTrigger(dateMatching: c, repeats: true))
                do {
                    try await center.add(request)
                } catch {
                    failed = true
                }
            }
        }
        return failed ? .failed : .scheduled
    }
}
