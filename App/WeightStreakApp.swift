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
        }
    }
}
