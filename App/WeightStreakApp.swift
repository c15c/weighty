import SwiftUI

@main
struct WeightStreakApp: App {
    @StateObject private var store = WeightStore.shared
    @State private var showLogSheet = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView(showLogSheet: $showLogSheet)
                .environmentObject(store)
                .onOpenURL { url in
                    // Tapping the widget deep links straight into logging.
                    if url.scheme == "weightstreak", url.host == "log" {
                        showLogSheet = true
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    // Reminder timing follows the habit, and the evening nudge
                    // depends on today's state, so both are re-evaluated here.
                    Reminders.refresh(entries: store.entries, streak: store.streak)
                    WeightStore.reloadWidgets()
                }
        }
    }
}
