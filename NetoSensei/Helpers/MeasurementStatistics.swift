import Foundation

/// Shared units and aggregates. Missing/invalid samples never become zeros.
enum MeasurementStatistics {
    static func mean(_ values: [Double?]) -> Double? {
        let valid = values.compactMap { $0 }.filter { $0.isFinite }
        guard !valid.isEmpty else { return nil }
        let average = valid.reduce(0) { $0 + $1 / Double(valid.count) }
        return average.isFinite ? average : nil
    }

    static func median(_ samples: [Double]) -> Double? {
        let sorted = samples.filter(\.isFinite).sorted()
        guard !sorted.isEmpty else { return nil }
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? sorted[middle-1]/2 + sorted[middle]/2 : sorted[middle]
    }

    static func throughputMbps(bytes: Int, duration: TimeInterval) -> Double? {
        guard bytes > 0, duration.isFinite, duration > 0 else { return nil }
        let value = Double(bytes) * 8 / 1_000_000 / duration
        return value.isFinite ? value : nil
    }

    static func standardDeviation(_ samples: [Double]) -> Double? {
        let values = samples.filter { $0.isFinite && $0 >= 0 }
        guard values.count >= 2, let average = mean(values.map(Optional.some)) else { return nil }
        let deviation = sqrt(values.map { pow($0 - average, 2) / Double(values.count) }.reduce(0, +))
        return deviation.isFinite ? deviation : nil
    }
}
