import Foundation

// Helpers that let the workspace file survive missing keys, unknown enum values
// and individual broken records instead of failing the whole decode.

extension KeyedDecodingContainer {
    /// Decodes a value, falling back to `fallback` when the key is missing or the value is invalid.
    func decode<T: Decodable>(_ key: Key, or fallback: @autoclosure () -> T) -> T {
        ((try? decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback()
    }

    /// Decodes an optional value; an invalid value becomes nil.
    func decodeOptional<T: Decodable>(_ key: Key) -> T? {
        (try? decodeIfPresent(T.self, forKey: key)) ?? nil
    }

    /// Decodes an array, dropping elements that fail to decode.
    func decodeLossyArray<T: Decodable>(_ key: Key) -> [T] {
        guard let lossy = try? decodeIfPresent(LossyArray<T>.self, forKey: key) else { return [] }
        return lossy.elements
    }
}

private struct LossyArray<T: Decodable>: Decodable {
    var elements: [T] = []

    private struct Skip: Decodable {}

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        while !container.isAtEnd {
            if let element = try? container.decode(T.self) {
                elements.append(element)
            } else {
                _ = try? container.decode(Skip.self)
            }
        }
    }
}

/// Enums stored as strings decode unknown raw values to a default case.
protocol TolerantStringEnum: RawRepresentable, Codable where RawValue == String {
    static var fallback: Self { get }
}

extension TolerantStringEnum {
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: raw) ?? Self.fallback
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
