import Foundation

/// Transfer rate over a rolling window, so the readout tracks what the card is
/// doing now rather than an average of everything since the import began.
///
/// Averaging from the start meant a slow file after a run of fast ones barely
/// moved the number, and the time remaining stayed visibly wrong for minutes.
/// Sampling the cumulative byte count over a few seconds and differencing across
/// the window makes the figure follow reality.
nonisolated struct TransferRateEstimator {
    /// How far back the window reaches.
    let window: TimeInterval

    /// The shortest span that yields a rate. Below this the divisor is small
    /// enough that ordinary scheduling jitter dominates the answer.
    private let minimumSpan: TimeInterval = 0.5

    private var samples: [(time: Date, bytes: Double)] = []

    init(window: TimeInterval = 5.0) {
        self.window = window
    }

    /// Records the running total and returns bytes per second across the window,
    /// or `nil` while the window is still too short to divide by.
    mutating func record(cumulativeBytes: Double, at now: Date = Date()) -> Double? {
        samples.append((now, cumulativeBytes))

        // Always keep one sample, so the window has something to measure against
        // after a long stall.
        let cutoff = now.addingTimeInterval(-window)
        while samples.count > 1, samples[0].time < cutoff {
            samples.removeFirst()
        }

        guard let oldest = samples.first else { return nil }
        let span = now.timeIntervalSince(oldest.time)
        guard span > minimumSpan else { return nil }
        return (cumulativeBytes - oldest.bytes) / span
    }

    /// Drops the window, so nothing from a finished import feeds into the next.
    mutating func reset() {
        samples = []
    }
}
