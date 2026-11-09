/// The lines waiting for the file, oldest first, never more than `cap`: past it the oldest line goes,
/// and `dropped` counts it. So a log that cannot be written (a full disk, a file the phone keeps locked)
/// costs a fixed amount of memory, never more. Appending is O(1) (a ring), whatever the length.
public struct LogQueue: Sendable {
    private let cap: Int
    private var storage: [LogLine] = []
    /// where the oldest line is once the ring is full (0 until then)
    private var head = 0
    /// every line dropped since the queue was made; a drain does not reset it
    public private(set) var dropped = 0

    /// `cap` below one is one: the newest line is always kept.
    public init(cap: Int = 2000) {
        self.cap = max(1, cap)
    }

    /// lines waiting
    public var count: Int {
        storage.count
    }

    /// Adds `line` as the newest; past `cap`, the oldest goes.
    public mutating func append(_ line: LogLine) {
        if storage.count < cap {
            storage.append(line)
        } else {
            storage[head] = line
            head = (head + 1) % cap
            dropped += 1
        }
    }

    /// Every line waiting, oldest first; the queue is empty after.
    public mutating func drain() -> [LogLine] {
        let lines = head == 0 ? storage : Array(storage[head...] + storage[..<head])
        storage.removeAll(keepingCapacity: true)
        head = 0
        return lines
    }
}
