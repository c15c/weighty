import Foundation
import UserNotifications

/// A nudge is what actually keeps a logging streak alive, so it is scheduled for
/// the time the habit already happens rather than an arbitrary hour, and it
/// stays gentle: no shame, no daily guilt when a day is missed.
enum Reminders {

    private static let dailyIdentifier = "daily-weigh-in"
    private static let riskIdentifier = "streak-at-risk"

    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func schedule(hour: Int, minute: Int) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [dailyIdentifier])

        let content = UNMutableNotificationContent()
        content.title = "Weigh-in"
        content.body = "Same time, same conditions — that is what makes the trend readable."
        content.sound = .default

        var components = DateComponents()
        components.hour = hour
        components.minute = minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        center.add(UNNotificationRequest(identifier: dailyIdentifier,
                                         content: content,
                                         trigger: trigger))
    }

    static func cancel() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [dailyIdentifier, riskIdentifier])
    }

    /// Re-point the daily reminder at the user's usual weigh-in time and, when a
    /// live streak has not been logged yet, set a single evening reminder.
    static func refresh(entries: [WeightEntry],
                        streak: StreakSummary,
                        defaults: UserDefaults = AppGroup.defaults,
                        now: Date = Date(),
                        calendar: Calendar = .current) {
        guard defaults.bool(forKey: StorageKeys.reminderEnabled) else {
            cancel()
            return
        }

        var hour = defaults.object(forKey: StorageKeys.reminderHour) as? Int ?? 7
        var minute = defaults.object(forKey: StorageKeys.reminderMinute) as? Int ?? 0

        if defaults.bool(forKey: StorageKeys.adaptiveReminder),
           let usual = Insights.usualWeighInTime(entries: entries, calendar: calendar) {
            hour = usual.hour ?? hour
            minute = usual.minute ?? minute
        }
        schedule(hour: hour, minute: minute)

        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [riskIdentifier])

        guard defaults.bool(forKey: StorageKeys.eveningNudge), streak.atRisk else { return }

        var evening = calendar.dateComponents([.year, .month, .day], from: now)
        evening.hour = 20
        evening.minute = 0
        guard let fireDate = calendar.date(from: evening), fireDate > now else { return }

        let content = UNMutableNotificationContent()
        content.title = streak.criticalToday ? "Last day to keep your streak" : "Streak still open"
        content.body = streak.criticalToday
            ? "Your \(streak.current)-day streak ends if today goes unlogged."
            : "A quick weigh-in keeps your \(streak.current)-day streak going."
        content.sound = .default

        let interval = max(fireDate.timeIntervalSince(now), 60)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        center.add(UNNotificationRequest(identifier: riskIdentifier,
                                         content: content,
                                         trigger: trigger))
    }
}
