import AppIntents

struct WeightShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: LogWeightIntent(),
                    phrases: ["Log my weight in \(.applicationName)",
                              "Add a weigh-in to \(.applicationName)"],
                    shortTitle: "Log weight",
                    systemImageName: "scalemass")

        AppShortcut(intent: WeightTrendIntent(),
                    phrases: ["What is my weight trend in \(.applicationName)",
                              "Check my \(.applicationName) trend"],
                    shortTitle: "Weight trend",
                    systemImageName: "chart.line.downtrend.xyaxis")
    }
}
