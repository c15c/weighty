import Foundation
import UserNotifications

/// Daily weigh-in reminders, with an optional separate weekend time and a
/// choice of notification text.
enum Reminders {

    private static let legacyDailyIdentifier = "daily-weigh-in"
    private static let riskIdentifier = "streak-at-risk"
    private static func dailyIdentifier(_ weekday: Int) -> String { "daily-weigh-in-\(weekday)" }
    private static var allDailyIdentifiers: [String] {
        [legacyDailyIdentifier] + (1...7).map(dailyIdentifier)
    }

    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Weekday values follow `Calendar`: 1 is Sunday, 7 is Saturday.
    static func isWeekend(_ weekday: Int) -> Bool { weekday == 1 || weekday == 7 }

    static func isWeekend(_ date: Date, calendar: Calendar = .current) -> Bool {
        isWeekend(calendar.component(.weekday, from: date))
    }

    static func schedule(weekday: DateComponents,
                         weekend: DateComponents,
                         style: ReminderStyle,
                         streak: Int) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: allDailyIdentifiers)

        for day in 1...7 {
            let time = isWeekend(day) ? weekend : weekday
            let content = UNMutableNotificationContent()
            content.title = style.title(streak: streak)
            content.body = style.body(streak: streak)
            content.sound = .default

            var components = DateComponents()
            components.weekday = day
            components.hour = time.hour ?? 7
            components.minute = time.minute ?? 0

            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            center.add(UNNotificationRequest(identifier: dailyIdentifier(day),
                                             content: content,
                                             trigger: trigger))
        }
    }

    static func cancel() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: allDailyIdentifiers + [riskIdentifier])
    }

    static func weekdayTime(defaults: UserDefaults = AppGroup.defaults) -> DateComponents {
        DateComponents(hour: defaults.object(forKey: StorageKeys.reminderHour) as? Int ?? 7,
                       minute: defaults.object(forKey: StorageKeys.reminderMinute) as? Int ?? 0)
    }

    static func weekendTime(defaults: UserDefaults = AppGroup.defaults) -> DateComponents {
        DateComponents(hour: defaults.object(forKey: StorageKeys.reminderWeekendHour) as? Int ?? 8,
                       minute: defaults.object(forKey: StorageKeys.reminderWeekendMinute) as? Int ?? 0)
    }

    /// The times reminders will actually use, after the usual-time option.
    static func effectiveTimes(entries: [WeightEntry],
                               defaults: UserDefaults = AppGroup.defaults,
                               calendar: Calendar = .current) -> (weekday: DateComponents, weekend: DateComponents) {
        let split = defaults.bool(forKey: StorageKeys.reminderSplitWeekend)
        var weekday = weekdayTime(defaults: defaults)
        var weekend = split ? weekendTime(defaults: defaults) : weekday

        if defaults.bool(forKey: StorageKeys.adaptiveReminder) {
            if split {
                let weekdayEntries = entries.filter { !isWeekend($0.date, calendar: calendar) }
                let weekendEntries = entries.filter { isWeekend($0.date, calendar: calendar) }
                if let usual = Insights.usualWeighInTime(entries: weekdayEntries, calendar: calendar) { weekday = usual }
                if let usual = Insights.usualWeighInTime(entries: weekendEntries, calendar: calendar) { weekend = usual }
            } else if let usual = Insights.usualWeighInTime(entries: entries, calendar: calendar) {
                weekday = usual
                weekend = usual
            }
        }
        return (weekday, weekend)
    }

    static func refresh(entries: [WeightEntry],
                        streak: StreakSummary,
                        defaults: UserDefaults = AppGroup.defaults,
                        now: Date = Date(),
                        calendar: Calendar = .current) {
        guard defaults.bool(forKey: StorageKeys.reminderEnabled) else {
            cancel()
            return
        }

        let style = ReminderStyle(rawValue: defaults.string(forKey: StorageKeys.reminderStyle) ?? "") ?? .simple
        let times = effectiveTimes(entries: entries, defaults: defaults, calendar: calendar)
        schedule(weekday: times.weekday, weekend: times.weekend, style: style, streak: streak.current)

        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [riskIdentifier])

        guard defaults.bool(forKey: StorageKeys.eveningNudge), streak.atRisk else { return }

        var evening = calendar.dateComponents([.year, .month, .day], from: now)
        evening.hour = 20
        evening.minute = 0
        guard let fireDate = calendar.date(from: evening), fireDate > now else { return }

        let content = UNMutableNotificationContent()
        content.title = streak.criticalToday ? "Streak ends today" : "Streak open"
        content.body = "\(streak.current)-day streak."
        content.sound = .default

        let interval = max(fireDate.timeIntervalSince(now), 60)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        center.add(UNNotificationRequest(identifier: riskIdentifier,
                                         content: content,
                                         trigger: trigger))
    }
}
