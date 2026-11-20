import Foundation

/// Just enough of the protobuf wire format to read sentencepiece's `ModelProto`.
struct ProtobufReader {
    private let data: [UInt8]
    private var index = 0

    init(_ data: Data) { self.data = [UInt8](data) }
    init(_ bytes: [UInt8]) { data = bytes }

    /// The next field number and wire type, or `nil` at the end.
    mutating func key() throws(JMTError) -> (field: Int, wire: Int)? {
        guard index < data.count else { return nil }
        let key = try varint()
        return (Int(key >> 3), Int(key & 7))
    }

    mutating func varint() throws(JMTError) -> UInt64 {
        var value: UInt64 = 0, shift: UInt64 = 0
        while true {
            guard index < data.count, shift < 64 else { throw Self.malformed("a varint runs past its end") }
            let byte = data[index]
            index += 1
            value |= UInt64(byte & 0x7F) << shift
            if byte < 0x80 { return value }
            shift += 7
        }
    }

    /// A length-delimited field's bytes.
    mutating func bytes() throws(JMTError) -> [UInt8] {
        let length = try varint()
        guard length <= UInt64(data.count - index) else { throw Self.malformed("a field runs past the end") }
        let end = index + Int(length)
        defer { index = end }
        return Array(data[index..<end])
    }

    mutating func skip(_ wire: Int) throws(JMTError) {
        switch wire {
        case 0: _ = try varint()
        case 1: try advance(8)
        case 2: _ = try bytes()
        case 5: try advance(4)
        default: throw Self.malformed("wire type \(wire)")
        }
    }

    private mutating func advance(_ count: Int) throws(JMTError) {
        guard index + count <= data.count else { throw Self.malformed("a field runs past the end") }
        index += count
    }

    private static func malformed(_ reason: String) -> JMTError { .badFile("joint.model", reason) }
}
