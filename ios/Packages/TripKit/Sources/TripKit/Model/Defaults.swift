import Foundation

/// An array that decodes as empty when its key is missing. The exporter drops nulls, so research
/// lists that were never filled in arrive as absent keys rather than `[]`.
@propertyWrapper
public struct Many<Element: Codable & Sendable>: Codable, Sendable {
    public var wrappedValue: [Element]

    public init(wrappedValue: [Element] = []) {
        self.wrappedValue = wrappedValue
    }

    public init(from decoder: any Decoder) throws {
        wrappedValue = try decoder.singleValueContainer().decode([Element].self)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(wrappedValue)
    }
}

/// A table by string key that decodes as empty when its key is missing: what a later export added, read
/// from a file exported without it (the slim schedule has no `idRenames`).
@propertyWrapper
public struct ManyByKey<Value: Codable & Sendable>: Codable, Sendable {
    public var wrappedValue: [String: Value]

    public init(wrappedValue: [String: Value] = [:]) {
        self.wrappedValue = wrappedValue
    }

    public init(from decoder: any Decoder) throws {
        wrappedValue = try decoder.singleValueContainer().decode([String: Value].self)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(wrappedValue)
    }
}

extension KeyedDecodingContainer {
    public func decode<E>(_ type: Many<E>.Type, forKey key: Key) throws -> Many<E> {
        try decodeIfPresent(type, forKey: key) ?? Many()
    }

    public func decode<V>(_ type: ManyByKey<V>.Type, forKey key: Key) throws -> ManyByKey<V> {
        try decodeIfPresent(type, forKey: key) ?? ManyByKey()
    }
}

/// A value research wrote loosely (Fuji climate tables, ryokan notes). The app reads the few
/// fields it shows by path instead of fixing a schema that changes with each research pass.
public enum JSONValue: Codable, Sendable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    public init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let b = try? c.decode(Bool.self) {
            self = .bool(b)
        } else if let n = try? c.decode(Double.self) {
            self = .number(n)
        } else if let s = try? c.decode(String.self) {
            self = .string(s)
        } else if let a = try? c.decode([JSONValue].self) {
            self = .array(a)
        } else {
            self = .object(try c.decode([String: JSONValue].self))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .number(let n): try c.encode(n)
        case .bool(let b): try c.encode(b)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        case .null: try c.encodeNil()
        }
    }

    public subscript(key: String) -> JSONValue? {
        if case .object(let o) = self { return o[key] }
        return nil
    }

    public subscript(index: Int) -> JSONValue? {
        if case .array(let a) = self, a.indices.contains(index) { return a[index] }
        return nil
    }

    public var string: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    public var number: Double? {
        if case .number(let n) = self { return n }
        return nil
    }

    public var bool: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }

    public var array: [JSONValue] {
        if case .array(let a) = self { return a }
        return []
    }

    public var object: [String: JSONValue] {
        if case .object(let o) = self { return o }
        return [:]
    }
}
