@testable import EhPageTranslation
import Foundation
import Testing

@Suite struct NPYTableTests {
    /// An `.npy` file as numpy writes it: magic, version, header length, a Python dict padded
    /// with spaces to a multiple of 64 bytes and ending in a newline, then the data.
    static func npy(
        rows: Int, columns: Int, descr: String = "<f2", fortran: Bool = false, shape: String? = nil,
        version: UInt8 = 1, values: [Float]? = nil
    ) -> Data {
        var header = "{'descr': '\(descr)', 'fortran_order': \(fortran ? "True" : "False"), "
            + "'shape': \(shape ?? "(\(rows), \(columns))"), }"
        let prefix = version == 1 ? 10 : 12
        while (prefix + header.utf8.count + 1) % 64 != 0 { header += " " }
        header += "\n"
        var data = Data([0x93, 0x4E, 0x55, 0x4D, 0x50, 0x59, version, 0])
        let length = header.utf8.count
        data += version == 1
            ? [UInt8(length & 0xFF), UInt8(length >> 8)]
            : [UInt8(length & 0xFF), UInt8((length >> 8) & 0xFF), UInt8((length >> 16) & 0xFF), UInt8(length >> 24)]
        data += Data(header.utf8)
        for value in values ?? (0..<(rows * columns)).map({ Float($0) / 4 }) {
            let bits = Half.fromFloat(value)
            data += [UInt8(bits & 0xFF), UInt8(bits >> 8)]
        }
        return data
    }

    @Test(arguments: [UInt8(1), 2])
    func readsRowsOfAHalfTable(version: UInt8) throws {
        let table = try NPYTable(data: Self.npy(rows: 3, columns: 4, version: version))
        #expect(table.rows == 3 && table.columns == 4)
        var floats = [Float](repeating: 0, count: 4)
        floats.withUnsafeMutableBufferPointer { if let base = $0.baseAddress { table.floatRow(2, into: base) } }
        #expect(floats == [2, 2.25, 2.5, 2.75])
        var halves = [UInt16](repeating: 0, count: 4)
        halves.withUnsafeMutableBytes { if let base = $0.baseAddress { table.copyRow(1, to: base) } }
        #expect(halves == [1, 1.25, 1.5, 1.75].map(Half.fromFloat))
    }

    @Test func mapsAFile() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "npy-\(UUID().uuidString).npy")
        try Self.npy(rows: 2, columns: 2, values: [1, -1, 0.5, 65504]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let table = try NPYTable(url: url)
        var floats = [Float](repeating: 0, count: 2)
        floats.withUnsafeMutableBufferPointer { if let base = $0.baseAddress { table.floatRow(1, into: base) } }
        #expect(floats == [0.5, 65504])
    }

    @Test func rejectsWhatIsNotAHalfTable() throws {
        #expect(throws: NPYTableError.notNPY) { try NPYTable(data: Data("not numpy at all".utf8)) }
        #expect(throws: NPYTableError.notNPY) { try NPYTable(data: Data()) }
        for data in [
            Self.npy(rows: 2, columns: 2, descr: "<f4"),
            Self.npy(rows: 2, columns: 2, fortran: true),
            Self.npy(rows: 2, columns: 2, shape: "(2, 2, 1)", values: [0, 0, 0, 0]),
            Self.npy(rows: 2, columns: 2, shape: "(4,)", values: [0, 0, 0, 0])
        ] {
            #expect {
                try NPYTable(data: data)
            } throws: { error in
                if case NPYTableError.unsupported = error { true } else { false }
            }
        }
    }

    @Test func rejectsATruncatedTable() {
        let data = Self.npy(rows: 3, columns: 4)
        #expect(throws: NPYTableError.truncated) { try NPYTable(data: data.dropLast(2)) }
        #expect(throws: NPYTableError.truncated) { try NPYTable(data: data.prefix(40)) }
    }

    @Test func readsASliceOfLargerData() throws {
        // Data whose indices do not start at 0, as a slice of a larger buffer has.
        let data = Data([0xAA, 0xBB]) + Self.npy(rows: 1, columns: 2, values: [3, 4])
        let table = try NPYTable(data: data.dropFirst(2))
        var floats = [Float](repeating: 0, count: 2)
        floats.withUnsafeMutableBufferPointer { if let base = $0.baseAddress { table.floatRow(0, into: base) } }
        #expect(floats == [3, 4])
    }
}
