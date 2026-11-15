import Foundation

/// A two-dimensional little-endian float16 `.npy` table (`<f2`, C order), memory-mapped: only
/// the rows read are paged in, so the translator's 160 MB embedding costs a few pages per
/// balloon.
public struct NPYTable: Sendable {
    public let rows: Int
    public let columns: Int
    private let data: Data
    private let offset: Int

    /// Maps the file at `url`. Reads the header only.
    public init(url: URL) throws {
        try self.init(data: Data(contentsOf: url, options: .alwaysMapped))
    }

    public init(data: Data) throws {
        let magic: [UInt8] = [0x93, 0x4E, 0x55, 0x4D, 0x50, 0x59]
        guard data.count > 10, data.prefix(6).elementsEqual(magic) else { throw NPYTableError.notNPY }
        let bytes = { (index: Int) in Int(data[data.startIndex + index]) }
        let headerLength: Int, start: Int
        if bytes(6) == 1 {
            headerLength = bytes(8) | bytes(9) << 8
            start = 10
        } else {
            guard data.count > 12 else { throw NPYTableError.truncated }
            headerLength = bytes(8) | bytes(9) << 8 | bytes(10) << 16 | bytes(11) << 24
            start = 12
        }
        guard data.count >= start + headerLength else { throw NPYTableError.truncated }
        let headerRange = (data.startIndex + start)..<(data.startIndex + start + headerLength)
        let header = String(decoding: data[headerRange], as: UTF8.self)
        guard header.contains("'descr': '<f2'"), header.contains("'fortran_order': False"),
              let open = header.range(of: "'shape': ("),
              let close = header[open.upperBound...].firstIndex(of: ")")
        else { throw NPYTableError.unsupported(header) }
        let dimensions = header[open.upperBound..<close].split(separator: ",").compactMap {
            Int($0.trimmingCharacters(in: .whitespaces))
        }
        guard dimensions.count == 2, dimensions.allSatisfy({ $0 >= 0 }) else {
            throw NPYTableError.unsupported(header)
        }
        rows = dimensions[0]
        columns = dimensions[1]
        offset = start + headerLength
        guard data.count >= offset + rows * columns * 2 else { throw NPYTableError.truncated }
        self.data = data
    }

    /// Copies row `row` as raw half bits to `dst`, which holds `columns` halves.
    @inline(__always)
    public func copyRow(_ row: Int, to dst: UnsafeMutableRawPointer) {
        precondition(row >= 0 && row < rows, "row \(row) outside 0..<\(rows)")
        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            dst.copyMemory(from: base + offset + row * columns * 2, byteCount: columns * 2)
        }
    }

    /// Row `row` widened to floats into `dst`, which holds `columns` floats.
    public func floatRow(_ row: Int, into dst: UnsafeMutablePointer<Float>) {
        precondition(row >= 0 && row < rows, "row \(row) outside 0..<\(rows)")
        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            Half.widen(base + offset + row * columns * 2, dst, count: columns)
        }
    }
}

public enum NPYTableError: Error, Equatable {
    case notNPY
    /// Anything but a C-order float16 table of two dimensions; carries the header.
    case unsupported(String)
    case truncated
}
