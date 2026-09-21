import Foundation
import HealthKit

enum HealthKitImporter {
    private static let store = HKHealthStore()

    static var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    /// Requests read-only access and returns every body-mass sample visible to the app.
    static func bodyWeightSamples() async throws -> [(date: Date, kilograms: Double)] {
        guard isAvailable else {
            throw ImportError.healthDataUnavailable
        }
        guard let bodyMass = HKObjectType.quantityType(forIdentifier: .bodyMass) else {
            throw ImportError.bodyMassUnavailable
        }

        try await withCheckedThrowingContinuation { continuation in
            store.requestAuthorization(toShare: [], read: [bodyMass]) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: ImportError.authorizationFailed)
                }
            }
        }

        return try await withCheckedThrowingContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let query = HKSampleQuery(sampleType: bodyMass,
                                      predicate: nil,
                                      limit: HKObjectQueryNoLimit,
                                      sortDescriptors: [sort]) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let unit = HKUnit.gramUnit(with: .kilo)
                let values = (samples as? [HKQuantitySample] ?? []).map {
                    (date: $0.startDate, kilograms: $0.quantity.doubleValue(for: unit))
                }
                continuation.resume(returning: values)
            }
            store.execute(query)
        }
    }

    enum ImportError: LocalizedError {
        case healthDataUnavailable
        case bodyMassUnavailable
        case authorizationFailed

        var errorDescription: String? {
            switch self {
            case .healthDataUnavailable:
                return "Apple Health data is not available on this device."
            case .bodyMassUnavailable:
                return "The body weight data type is not available."
            case .authorizationFailed:
                return "Weight Streak could not request Apple Health access."
            }
        }
    }
}
