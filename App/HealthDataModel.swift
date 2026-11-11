import Foundation
import Combine
import HealthKit
import WHOOPCore

@MainActor
final class HealthDataModel: ObservableObject {
    @Published private(set) var isLoading = false
    @Published private(set) var status = "Choose a date range to bring your measurements into this app."
    @Published private(set) var error: String?

    private let healthStore = HKHealthStore()
    private let heartRateLimit = 90_000
    private let sleepLimit = 50_000
    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Called only by the import button. An authorization callback never proves read access.
    func fetch(days: Int) async throws -> [DailySnapshot] {
        guard !isLoading else { throw HealthImportProblem.busy }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            guard isAvailable else { throw HealthImportProblem.unavailable }
            guard days == 14 || days == 30 else { throw HealthImportProblem.invalidRange }
            let steps = try quantityType(.stepCount)
            let energy = try quantityType(.activeEnergyBurned)
            let resting = try quantityType(.restingHeartRate)
            let breathing = try quantityType(.respiratoryRate)
            let heartRate = try quantityType(.heartRate)
            guard let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
                throw HealthImportProblem.unavailable
            }
            status = "Choose which measurements Apple Health can share."
            try await requestReadAccess(to: Set<HKObjectType>([steps, energy, resting, breathing, heartRate, sleep]))
            try Task.checkCancellation()
            status = "Reading your measurements…"
            // Include today so far and the previous N-1 UTC dates, never future samples.
            let now = Date()
            let today = DayCalendar.start(of: now)
            guard let start = DayCalendar.utc.date(byAdding: .day, value: 1 - days, to: today) else {
                throw HealthImportProblem.invalidRange
            }
            let rangePredicate = HKQuery.predicateForSamples(withStart: start, end: now, options: .strictStartDate)
            let rates: [HeartRateSample] = try await samples(type: heartRate, predicate: rangePredicate,
                                                            limit: heartRateLimit + 1) { samples in
                // DailySnapshot identifies rates by timestamp. Resolve simultaneous source
                // records deterministically, rather than introducing duplicate identities.
                var records: [Date: (String, Double)] = [:]
                for case let sample as HKQuantitySample in samples {
                    let value = sample.quantity.doubleValue(for: .count().unitDivided(by: .minute()))
                    guard value.isFinite, (1...300).contains(value) else { continue }
                    let identifier = sample.uuid.uuidString
                    if let previous = records[sample.startDate], previous.0 <= identifier { continue }
                    records[sample.startDate] = (identifier, value)
                }
                return records.map { HeartRateSample(timestamp: $0.key, bpm: $0.value.1) }
                    .sorted { $0.timestamp < $1.timestamp }
            }
            // Use the raw count for the limit notice, including duplicate/invalid records.
            // samples() records whether its finite limit was reached before transformation.
            let heartRateCapped = lastQueryReachedLimit
            let asleepIntervals: [DateInterval] = try await samples(type: sleep,
                predicate: HKQuery.predicateForSamples(withStart: start, end: now, options: []),
                limit: sleepLimit + 1) { samples in
                    samples.compactMap { sample -> DateInterval? in
                        guard let sample = sample as? HKCategorySample,
                              [HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                               HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                               HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                               HKCategoryValueSleepAnalysis.asleepREM.rawValue].contains(sample.value),
                              sample.endDate > sample.startDate else { return nil }
                        return DateInterval(start: sample.startDate, end: sample.endDate)
                    }
                }
            let sleepCapped = lastQueryReachedLimit
            // Do not save a partial sleep total that could look like a complete night.
            guard !sleepCapped else { throw HealthImportProblem.tooManySleepRecords }
            let ratesByDay = Dictionary(grouping: rates.prefix(heartRateLimit)) { DayCalendar.start(of: $0.timestamp) }
            var result: [DailySnapshot] = []
            for offset in 0..<days {
                try Task.checkCancellation()
                guard let dayStart = DayCalendar.utc.date(byAdding: .day, value: offset, to: start),
                      let next = DayCalendar.utc.date(byAdding: .day, value: 1, to: dayStart) else { continue }
                let dayEnd = min(next, now)
                let predicate = HKQuery.predicateForSamples(withStart: dayStart, end: dayEnd, options: .strictStartDate)
                let stepCount = try await statistic(type: steps, predicate: predicate, options: .cumulativeSum, unit: .count())
                let energyKcal = try await statistic(type: energy, predicate: predicate, options: .cumulativeSum, unit: .kilocalorie())
                let restingRate = try await statistic(type: resting, predicate: predicate, options: .discreteAverage,
                                                      unit: .count().unitDivided(by: .minute()))
                let respiratoryRate = try await statistic(type: breathing, predicate: predicate, options: .discreteAverage,
                                                          unit: .count().unitDivided(by: .minute()))
                guard valid(stepCount, in: 0...1_000_000), valid(energyKcal, in: 0...100_000),
                      valid(restingRate, in: 1...300), valid(respiratoryRate, in: 0...100) else {
                    throw HealthImportProblem.invalidMeasurements
                }
                let asleepSeconds = SleepIntervals.seconds(asleepIntervals, within: DateInterval(start: dayStart, end: dayEnd))
                let dayRates = (ratesByDay[dayStart] ?? []).filter { $0.timestamp >= dayStart && $0.timestamp < dayEnd }
                guard stepCount != nil || energyKcal != nil || restingRate != nil || respiratoryRate != nil ||
                        asleepSeconds > 0 || !dayRates.isEmpty else { continue }
                result.append(DailySnapshot(date: dayStart, recovery: nil, strain: nil, sleepPerformance: nil,
                    sleepMinutes: Int((asleepSeconds / 60).rounded(.down)), sleepNeededMinutes: 0,
                    restingHeartRate: restingRate, hrv: nil, respiratoryRate: respiratoryRate,
                    steps: Int((stepCount ?? 0).rounded()), energyKcal: energyKcal ?? 0,
                    heartRates: dayRates, source: .imported))
                status = "Read \(offset + 1) of \(days) days…"
            }
            guard !result.isEmpty else { throw HealthImportProblem.noData }
            status = "Read measurements for \(result.count) \(result.count == 1 ? "day" : "days")." +
                (heartRateCapped ? " Heart rate reached the 90,000-record limit; later records are omitted. Other daily measurements cover the full range." : "")
            return result
        } catch {
            if error is CancellationError {
                status = "Import cancelled. Your saved measurements have not changed."
            } else {
                self.error = error.localizedDescription
                status = "Measurements have not been saved."
            }
            throw error
        }
    }

    private func valid(_ value: Double?, in range: ClosedRange<Double>) -> Bool {
        value.map { $0.isFinite && range.contains($0) } ?? true
    }

    private func quantityType(_ identifier: HKQuantityTypeIdentifier) throws -> HKQuantityType {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else { throw HealthImportProblem.unavailable }
        return type
    }

    private func requestReadAccess(to types: Set<HKObjectType>) async throws {
        let pending = HealthQueryOperation<Void>()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                guard pending.begin(continuation) else { return }
                healthStore.requestAuthorization(toShare: [], read: types) { success, error in
                    if let error { pending.finish(.failure(error)) }
                    else if success { pending.finish(.success(())) }
                    else { pending.finish(.failure(HealthImportProblem.authorizationIncomplete)) }
                }
            }
        } onCancel: { pending.cancel() }
    }

    private var lastQueryReachedLimit = false

    private func samples<Value>(type: HKSampleType, predicate: NSPredicate, limit: Int,
                                transform: @escaping ([HKSample]) -> Value) async throws -> Value {
        let pending = HealthQueryOperation<(Value, Bool)>()
        let result: (Value, Bool) = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard pending.begin(continuation) else { return }
                let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: limit,
                    sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, records, error in
                    if let error, !healthKitHasNoData(error) { pending.finish(.failure(error)); return }
                    let records = records ?? []
                    pending.finish(.success((transform(Array(records.prefix(limit - 1))), records.count >= limit)))
                }
                pending.execute(query, in: healthStore)
            }
        } onCancel: { pending.cancel() }
        lastQueryReachedLimit = result.1
        return result.0
    }

    private func statistic(type: HKQuantityType, predicate: NSPredicate, options: HKStatisticsOptions,
                           unit: HKUnit) async throws -> Double? {
        let pending = HealthQueryOperation<Double?>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard pending.begin(continuation) else { return }
                let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: options) { _, statistics, error in
                    if let error, !healthKitHasNoData(error) { pending.finish(.failure(error)); return }
                    let quantity = options.contains(.cumulativeSum) ? statistics?.sumQuantity() : statistics?.averageQuantity()
                    pending.finish(.success(quantity?.doubleValue(for: unit)))
                }
                pending.execute(query, in: healthStore)
            }
        } onCancel: { pending.cancel() }
    }
}

private func healthKitHasNoData(_ error: Error) -> Bool {
    let error = error as NSError
    return error.domain == HKErrorDomain && error.code == HKError.Code.errorNoData.rawValue
}

private enum HealthImportProblem: LocalizedError {
    case unavailable, busy, invalidRange, authorizationIncomplete, noData, tooManySleepRecords, invalidMeasurements
    var errorDescription: String? {
        switch self {
        case .unavailable: return "Apple Health is not available on this device. Try importing on an iPhone with Apple Health."
        case .busy: return "An import is already in progress."
        case .invalidRange: return "Choose the last 14 or 30 days."
        case .authorizationIncomplete: return "The Apple Health request did not finish. Tap Import to try again."
        case .noData: return "No readable measurements were found in this date range. Health may have no records, or access may be off. Review this app’s access in Apple Health, then try again."
        case .tooManySleepRecords: return "This range contains more than 50,000 sleep records. Choose a shorter range to import complete sleep totals."
        case .invalidMeasurements: return "Apple Health returned a daily measurement outside this app’s supported range. No measurements were saved."
        }
    }
}

/// One continuation owns one query. HealthKit callbacks and task cancellation can
/// race; both paths resolve it once, and cancellation stops an installed query.
private final class HealthQueryOperation<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    private var query: HKQuery?
    private var store: HKHealthStore?
    private var cancelled = false

    func begin(_ continuation: CheckedContinuation<Value, Error>) -> Bool {
        lock.lock()
        if cancelled {
            lock.unlock()
            continuation.resume(throwing: CancellationError())
            return false
        }
        self.continuation = continuation
        lock.unlock()
        return true
    }

    func execute(_ query: HKQuery, in store: HKHealthStore) {
        lock.lock()
        guard !cancelled, continuation != nil else { lock.unlock(); return }
        self.query = query
        self.store = store
        lock.unlock()
        store.execute(query)
        lock.lock()
        let shouldStop = cancelled
        lock.unlock()
        if shouldStop { store.stop(query) }
    }

    func finish(_ result: Result<Value, Error>) {
        lock.lock()
        let completion = continuation
        continuation = nil
        query = nil
        store = nil
        lock.unlock()
        completion?.resume(with: result)
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let query = query
        let store = store
        let completion = continuation
        continuation = nil
        self.query = nil
        self.store = nil
        lock.unlock()
        if let query { store?.stop(query) }
        completion?.resume(throwing: CancellationError())
    }
}
