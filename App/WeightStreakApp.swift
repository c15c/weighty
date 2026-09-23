import SwiftUI

@main
struct WeightStreakApp: App {
    @StateObject private var store = WeightStore.shared
    @State private var showLogSheet = false

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
                .onChange(of: store.entries) { _, _ in
                    BackupManager.scheduleBackup(of: store)
                }
                .onChange(of: store.goalKilograms) { _, _ in
                    BackupManager.scheduleBackup(of: store)
                }
                .onChange(of: store.unit) { _, _ in
                    BackupManager.scheduleBackup(of: store)
                }
        }
    }
}
