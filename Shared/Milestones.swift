import Foundation

/// A distant goal weight is a poor motivator; the next two or three kilos are a
/// good one. Milestones are laid out every 2% of starting bodyweight so there is
/// always something close enough to chase.
struct Milestone: Identifiable, Equatable {
    let kilograms: Double
    let percentLost: Double
    var reached: Bool

    var id: Double { kilograms }
}

enum Milestones {

    static let stepPercent = 2.0

    static func all(start: Double?, goal: Double?, trend: Double?) -> [Milestone] {
        guard let start, start > 0 else { return [] }
        let floorWeight = goal.map { min($0, start) } ?? start * 0.8
        guard start - floorWeight > 0.2 else { return [] }

        var milestones: [Milestone] = []
        var percent = stepPercent
        while percent <= 60 {
            let weight = start * (1 - percent / 100)
            if weight < floorWeight - 0.05 { break }
            milestones.append(Milestone(kilograms: weight,
                                        percentLost: percent,
                                        reached: (trend ?? start) <= weight + 0.0001))
            percent += stepPercent
        }

        // Always finish on the goal itself.
        if let goal, milestones.last.map({ abs($0.kilograms - goal) > 0.05 }) ?? true {
            let percentToGoal = ((start - goal) / start) * 100
            if percentToGoal > 0 {
                milestones.append(Milestone(kilograms: goal,
                                            percentLost: percentToGoal,
                                            reached: (trend ?? start) <= goal + 0.0001))
            }
        }
        return milestones
    }

    static func next(start: Double?, goal: Double?, trend: Double?) -> Milestone? {
        all(start: start, goal: goal, trend: trend).first { !$0.reached }
    }

    static func lastReached(start: Double?, goal: Double?, trend: Double?) -> Milestone? {
        all(start: start, goal: goal, trend: trend).last { $0.reached }
    }

    /// Percent of starting bodyweight lost so far, on the trend.
    static func percentLost(start: Double?, trend: Double?) -> Double? {
        guard let start, start > 0, let trend else { return nil }
        return ((start - trend) / start) * 100
    }
}
