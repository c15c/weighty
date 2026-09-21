# Weight Streak

A weigh-in streak tracker for iOS with home screen and lock screen widgets, built to be
sideloaded with AltStore using a free Apple ID.

## What it does

- One weigh-in per calendar day, logged manually
- Streak counter for consecutive weigh-ins that came in lower, plus a personal best
- 7 day rolling average and week-over-week change, because a single day's reading is noise
- Progress bar from your first recorded weigh-in toward your goal
- Widgets: small (streak), medium (streak plus trend plus goal progress), lock screen circular and inline
- Tapping any widget deep links straight into the logging sheet
- Optional daily reminder notification
- CSV export

## Why there is no HealthKit

Reading or writing Apple Health requires the `com.apple.developer.healthkit` entitlement.
When AltStore re-signs an unsigned .ipa with a free Apple ID, that capability is stripped.
The framework would still link, the permission sheet would never appear, and the app would
never show up under Settings, Health, Data Access & Devices. Shipping a dead button is worse
than not shipping one.

The bridge into Health is a Shortcut instead. See below.

If you later move to a paid Apple Developer account, the change is contained:
enable HealthKit on the App ID, add the entitlement to `App/WeightStreak.entitlements`,
and add a `HealthKitBridge.swift` that calls `HKHealthStore.save` on
`HKQuantityType(.bodyMass)` inside `WeightStore.log`. Nothing else needs to move.

## Building the .ipa

You do not need a Mac. GitHub Actions provides macOS runners with Xcode preinstalled.

1. Push this folder to a GitHub repo with `main` as the default branch.
2. The workflow in `.github/workflows/build.yml` runs on push, or manually from the Actions tab.
3. Download the `WeightStreak-ipa` artifact. It contains `WeightStreak.ipa` plus both
   `.entitlements` files.

The build runs `xcodegen generate` to produce the Xcode project from `project.yml`, builds
unsigned with `CODE_SIGNING_ALLOWED=NO`, then wraps the `.app` in a `Payload/` folder and
zips it to `.ipa`. The free Actions tier covers this comfortably.

## Sideloading

1. Open AltStore, tap the + and pick `WeightStreak.ipa`.
2. Refresh within 7 days. A free Apple ID certificate expires on that cycle.
3. Long press the home screen, add the Weight Streak widget.

### If the widget shows no data

The app and the widget share storage through the App Group `group.com.cisco.weightstreak`.
If AltStore did not register that group during re-signing, the widget will read an empty
container while the app itself works fine.

Fixes, in order of preference:

- Re-sign with Sideloadly instead and tick its App Groups option
- Change the group identifier in `Shared/Models.swift`, both `.entitlements` files and
  `project.yml` to something unique to you, then rebuild
- Use a paid certificate, which registers the group cleanly

## Apple Health bridge

1. Settings, Export CSV, save it somewhere the Shortcuts app can read
2. In Shortcuts: Get File, Split Text by New Lines, Repeat with Each, Split Text by Commas,
   then Log Health Sample with type Weight using the second item
3. Or simpler for daily use: a one step Shortcut that prompts for a number and logs it to
   Health, run right after you log in the app

## Project layout

```
project.yml                     XcodeGen spec, two targets
App/                            SwiftUI app
  WeightStreakApp.swift         entry point, deep link handling
  ContentView.swift             main screen, streak card, stats, sparkline, history
  LogWeightView.swift           weigh-in sheet
  SettingsView.swift            goal, units, reminder, export
Shared/                         compiled into both targets
  Models.swift                  entry, units, App Group, storage keys
  WeightStore.swift             persistence and mutation
  Streak.swift                  streak calculation
  Trend.swift                   rolling average, week-over-week, goal progress
  Reminders.swift               daily local notification
Widget/
  WeightStreakWidget.swift      timeline provider and all widget families
.github/workflows/build.yml     unsigned .ipa build
```

## Streak rules

A streak is consecutive weigh-ins that came in lower than the one before. Gaining breaks
it. Missing a day does not: the streak sits where it is until the next weigh-in decides
it, so skipping the scale costs you nothing and only the number itself can end the run.
The first ever weigh-in has nothing to compare against, so it does not count. Logging
twice in one day replaces the entry rather than adding to it.

## Widgets

Small: a ring showing progress toward the goal, the streak in the middle, and how much is
left to lose underneath. Medium: the streak and the change at the last weigh-in, next to a
30 day sparkline with your goal drawn as a dashed line, plus a progress bar. Lock screen
circular and inline are also supported.
