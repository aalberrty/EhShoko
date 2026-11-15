@testable import EhPageTranslation
import Foundation
import Testing

@Suite struct HalfTests {
    @Test(arguments: [
        (UInt16(0x3C00), Float(1)), (0xC000, -2), (0x0000, 0), (0x3555, 0.333251953125),
        (0x7BFF, 65504), (0x0400, 6.103515625e-05), (0x0001, 5.9604644775390625e-08), (0x03FF, 6.097555160522461e-05)
    ])
    func knownValues(bits: UInt16, value: Float) {
        #expect(Half.toFloat(bits) == value)
        #expect(Half.fromFloat(value) == bits)
    }

    @Test func signedZeroInfinityAndNaN() {
        #expect(Half.toFloat(0x8000).sign == .minus)
        #expect(Half.fromFloat(-0.0) == 0x8000)
        #expect(Half.toFloat(0x7C00) == .infinity)
        #expect(Half.toFloat(0xFC00) == -.infinity)
        #expect(Half.toFloat(0x7E00).isNaN)
        #expect(Half.fromFloat(.nan) & 0x7C00 == 0x7C00 && Half.fromFloat(.nan) & 0x3FF != 0)
        #expect(Half.fromFloat(.infinity) == 0x7C00)
    }

    @Test func roundsToNearestEven() {
        let ulp = Float(1) / 1024
        // Halfway between 1 and the next half goes to the even one, 1.
        #expect(Half.fromFloat(1 + ulp / 2) == 0x3C00)
        // Halfway between the next two goes up to the even one.
        #expect(Half.fromFloat(1 + 3 * ulp / 2) == 0x3C02)
        #expect(Half.fromFloat(1 + ulp / 2 + ulp / 8) == 0x3C01)
        // Overflow: 65520 is halfway to the next binade, which is infinity.
        #expect(Half.fromFloat(65519) == 0x7BFF)
        #expect(Half.fromFloat(65520) == 0x7C00)
        // Below half the smallest subnormal underflows to zero; exactly half rounds to even (0).
        #expect(Half.fromFloat(2.9802322387695312e-08) == 0x0000)
        #expect(Half.fromFloat(2.99e-08) == 0x0001)
        #expect(Half.fromFloat(1e-10) == 0x0000)
    }

    @Test func everyHalfSurvivesARoundTrip() {
        let failures = (UInt16.min...UInt16.max).filter { bits in
            let value = Half.toFloat(bits)
            return !value.isNaN && Half.fromFloat(value) != bits
        }
        #expect(failures.isEmpty)
    }

    @Test func bulkWideningMatchesTheScalarConversion() {
        let halves = (UInt16.min...UInt16.max).filter { !Half.toFloat($0).isNaN }
        var floats = [Float](repeating: 0, count: halves.count)
        halves.withUnsafeBytes { source in
            floats.withUnsafeMutableBufferPointer { destination in
                if let src = source.baseAddress, let dst = destination.baseAddress {
                    Half.widen(src, dst, count: halves.count)
                }
            }
        }
        #expect(zip(halves, floats).allSatisfy { Half.toFloat($0).bitPattern == $1.bitPattern })
    }
}
