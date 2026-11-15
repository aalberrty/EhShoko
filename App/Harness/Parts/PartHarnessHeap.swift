#if DEBUG || HARNESS
import Darwin
import Foundation
import ObjectiveC

/// The memory check of `Design/designs/README.md` section 9.2, from inside the app: which
/// objects of a per-design type are alive, by class, with their counts. It is what
/// `heap <pid> | grep -E '(Shelf|Wall|Ledger|TabsBar|CommandBar)[A-Z]'` lists, for where
/// `heap` cannot be used: it needs the developer tools' access to another process, which a
/// Mac may not grant for a simulator's processes and a device never does.
///
/// It walks the malloc zones as `heap` does and takes a block for an object when its first
/// word is one of the classes looked for. A class is looked for when its name mentions a type
/// with a design's prefix: the type itself, or a generic class around it, such as the box
/// SwiftUI keeps a view's `@State` in. Structs that are not boxed do not show, as with `heap`.
enum PartHarnessHeap {
    /// The prefixes per-design types carry (`CLAUDE.md`, "Names").
    private static let prefixes = ["Shelf", "Wall", "Ledger", "TabsBar", "CommandBar"]

    /// One line per class with live instances, most first; a line saying so when none.
    static func report() -> String {
        let classes = candidates()
        guard !classes.isEmpty else { return "No class of a per-design type is loaded." }
        let counts = scan(for: classes.map(\.pointer))
        let lines = zip(classes, counts)
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .map { "\($0.1)\t\($0.0.name)" }
        return lines.isEmpty
            ? "No object of a per-design type is alive (\(classes.count) such classes are loaded)."
            : lines.joined(separator: "\n")
    }

    /// Writes the report beside the app's documents, for a script to read, and returns it.
    @discardableResult
    static func writeReport(named name: String = "part-harness-heap.txt") -> String {
        let report = report()
        if let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            try? report.write(to: folder.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        return report
    }

    // MARK: Classes

    private struct Candidate {
        let pointer: UInt
        let name: String
    }

    /// Every realized class whose name mentions a prefixed type, sorted by address.
    private static func candidates() -> [Candidate] {
        var count: UInt32 = 0
        guard let list = objc_copyClassList(&count) else { return [] }
        defer { free(UnsafeMutableRawPointer(list)) }
        // Read as addresses: taking a class out of the list as an object retains it, and some
        // of the system's root classes cannot be sent a message.
        let addresses = UnsafeRawPointer(list)
        var found: [Candidate] = []
        for index in 0..<Int(count) {
            let pointer = addresses.load(fromByteOffset: index * MemoryLayout<UInt>.stride, as: UInt.self)
            let type: AnyClass = unsafeBitCast(pointer, to: AnyClass.self)
            // The mangled name holds each identifier whole, so this cheap test comes first, and
            // only the app's own Swift classes go on to be demangled.
            let mangled = String(cString: class_getName(type))
            guard prefixes.contains(where: mangled.contains) else { continue }
            let name = _typeName(type)
            guard mentionsDesignType(name) else { continue }
            found.append(Candidate(pointer: pointer, name: name))
        }
        return found.sorted { $0.pointer < $1.pointer }
    }

    /// Whether a prefix starts an identifier in `name` and a capital follows it.
    private static func mentionsDesignType(_ name: String) -> Bool {
        let identifiers = name.split { !($0.isLetter || $0.isNumber || $0 == "_") }
        return identifiers.contains { identifier in
            prefixes.contains { prefix in
                identifier.hasPrefix(prefix) && identifier.dropFirst(prefix.count).first?.isUppercase == true
            }
        }
    }

    // MARK: The heap

    /// How many blocks in use start with each of `classes`, which must be sorted.
    private static func scan(for classes: [UInt]) -> [Int] {
        let pointers = UnsafeMutablePointer<UInt>.allocate(capacity: classes.count)
        let counts = UnsafeMutablePointer<Int>.allocate(capacity: classes.count)
        defer {
            pointers.deallocate()
            counts.deallocate()
        }
        pointers.initialize(from: classes, count: classes.count)
        counts.initialize(repeating: 0, count: classes.count)
        var scan = HeapScan(pointers: pointers, counts: counts, count: classes.count)

        var zones: UnsafeMutablePointer<vm_address_t>?
        var zoneCount: UInt32 = 0
        guard malloc_get_all_zones(mach_task_self_, nil, &zones, &zoneCount) == KERN_SUCCESS, let zones else {
            return Array(repeating: 0, count: classes.count)
        }
        withUnsafeMutablePointer(to: &scan) { context in
            for index in 0..<Int(zoneCount) {
                guard let zone = UnsafeMutablePointer<malloc_zone_t>(bitPattern: zones[index]),
                      let introspect = zone.pointee.introspect,
                      let enumerate = introspect.pointee.enumerator
                else { continue }
                // Nothing allocates between the lock and the unlock: the recorder only reads
                // and counts into memory set aside above.
                introspect.pointee.force_lock?(zone)
                _ = enumerate(
                    mach_task_self_, context, UInt32(MALLOC_PTR_IN_USE_RANGE_TYPE), zones[index], nil, recordHeapRanges
                )
                introspect.pointee.force_unlock?(zone)
            }
        }
        return (0..<classes.count).map { counts[$0] }
    }
}

nonisolated private struct HeapScan {
    let pointers: UnsafeMutablePointer<UInt>
    let counts: UnsafeMutablePointer<Int>
    let count: Int
}

/// The bits of an object's first word that are its class. The simulator on an Intel Mac is
/// the one this was run on.
#if arch(x86_64)
nonisolated private let heapClassMask: UInt = 0x0000_7FFF_FFFF_FFF8
#elseif targetEnvironment(simulator)
nonisolated private let heapClassMask: UInt = 0x007F_FFFF_FFFF_FFF8
#else
nonisolated private let heapClassMask: UInt = 0x0000_000F_FFFF_FFF8
#endif

/// Called by a zone with a batch of its blocks in use. It must not allocate.
nonisolated private func recordHeapRanges(
    _ task: task_t, _ context: UnsafeMutableRawPointer?, _ type: UInt32,
    _ ranges: UnsafeMutablePointer<vm_range_t>?, _ rangeCount: UInt32
) {
    guard let context, let ranges else { return }
    let scan = context.assumingMemoryBound(to: HeapScan.self).pointee
    for index in 0..<Int(rangeCount) {
        let range = ranges[index]
        guard range.size >= 16, let block = UnsafeRawPointer(bitPattern: range.address) else { continue }
        let type = block.load(as: UInt.self) & heapClassMask
        var low = 0
        var high = scan.count - 1
        while low <= high {
            let middle = (low + high) / 2
            let candidate = scan.pointers[middle]
            if candidate == type {
                scan.counts[middle] += 1
                break
            } else if candidate < type {
                low = middle + 1
            } else {
                high = middle - 1
            }
        }
    }
}
#endif
