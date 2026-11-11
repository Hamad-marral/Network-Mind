import Foundation

/// A single recognized word with an absolute wall-clock timestamp.
struct TranscriptWord: Codable, Hashable, Sendable {
    var text: String
    var start: Date
    var duration: TimeInterval
    var confidence: Float

    var end: Date { start.addingTimeInterval(duration) }
}

/// A run of words (roughly an utterance) with absolute timestamps.
struct TranscriptSegment: Codable, Hashable, Identifiable, Sendable {
    var id: UUID = UUID()
    var start: Date
    var end: Date
    var text: String
    var words: [TranscriptWord] = []
}

extension Array where Element == TranscriptSegment {
    /// Plain transcript text, one segment per line.
    var plainText: String { map(\.text).joined(separator: "\n") }

    /// Segments overlapping `[start, end]`.
    func overlapping(start: Date, end: Date) -> [TranscriptSegment] {
        filter { $0.end > start && $0.start < end }
    }
}

/// Shared JSON coding for blobs persisted inside SwiftData models.
enum ModelCoding {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }()

    static func encode<T: Encodable>(_ value: T) -> Data? {
        try? encoder.encode(value)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data?) -> T? {
        guard let data else { return nil }
        return try? decoder.decode(type, from: data)
    }
}
