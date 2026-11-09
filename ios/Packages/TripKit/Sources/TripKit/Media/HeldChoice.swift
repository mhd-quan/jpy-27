/// A value chosen once for a key and then held: an album page's colour (the app's `PageTone`), by its first
/// photograph. Decided when it is made if the value is known already; else by one decision later, for that key
/// only. A decision of nothing closes it too: no value, for good. Nothing learned afterwards changes it: a value
/// found later waits for the next choice (the page's next opening).
///
/// Another first key (`follow`) starts it again by the same rule: the old value is let go, never carried over, and
/// a decision still under way for the old key comes too late to count.
public struct HeldChoice<Key: Hashable & Sendable, Value: Sendable & Equatable>: Sendable, Equatable {
    /// what it is chosen for; nil: nothing to choose, no value
    public private(set) var key: Key?
    public private(set) var value: Value?
    /// chosen for `key`, with a value or without: nothing changes it any more
    public private(set) var decided: Bool

    /// For `key`, decided at once with `known`, the value known for it, if any. With no key there is nothing to
    /// hold or decide, and `known` is let go.
    public init(key: Key?, known: Value?) {
        self.key = key
        value = key == nil ? nil : known
        decided = value != nil
    }

    /// Whether the choice for `key` is still to be made.
    public func wants(_ key: Key) -> Bool {
        key == self.key && !decided
    }

    /// The value found for `key`, or nothing found: taken if the choice for that key is still to be made, and
    /// held from then on. For another key, or once decided, it changes nothing.
    public mutating func decide(_ found: Value?, for key: Key) {
        guard wants(key) else { return }
        value = found
        decided = true
    }

    /// `key` is now the one to choose for. The same key changes nothing, decided or not, whatever is known of it
    /// by now. Another starts again: decided at once with `known` (looked up only then), else to be decided.
    public mutating func follow(_ key: Key, known: @autoclosure () -> Value?) {
        guard key != self.key else { return }
        self = HeldChoice(key: key, known: known())
    }
}
