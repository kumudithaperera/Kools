/// Spots a quick side-to-side shake of the pointer: enough horizontal
/// direction changes, covering enough distance, within half a second.
public struct ShakeDetector: Sendable {
    public var window: Double = 0.5
    public var minReversals = 3
    public var minTravel: Double = 200
    /// Movements smaller than this don't count as a direction.
    public var jitter: Double = 6

    private var samples: [(time: Double, x: Double)] = []

    public init() {}

    /// Feeds one pointer position; returns true once when a shake completes.
    public mutating func add(time: Double, x: Double) -> Bool {
        samples.append((time, x))
        samples.removeAll { time - $0.time > window }
        guard samples.count >= 5 else { return false }

        var reversals = 0
        var travel = 0.0
        var lastDirection = 0
        for (previous, current) in zip(samples, samples.dropFirst()) {
            let dx = current.x - previous.x
            travel += abs(dx)
            let direction = dx > jitter ? 1 : (dx < -jitter ? -1 : 0)
            guard direction != 0 else { continue }
            if lastDirection != 0, direction != lastDirection { reversals += 1 }
            lastDirection = direction
        }
        guard reversals >= minReversals, travel >= minTravel else { return false }
        samples.removeAll()
        return true
    }

    public mutating func reset() {
        samples.removeAll()
    }
}
