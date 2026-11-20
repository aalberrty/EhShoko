@testable import EhCore
import EhTestSupport

extension CountingDefaults {
    /// The writes to each setting since the last `reset()`, by its key.
    nonisolated var counts: [SettingKey: Int] {
        let writes = writesByKey
        var counts: [SettingKey: Int] = [:]
        for key in SettingKey.allCases {
            if let count = writes[key.name] { counts[key] = count }
        }
        return counts
    }
}
