import Foundation
import Observation

@MainActor
@Observable
final class LifetimeStatsStore {
    private enum Keys {
        static let totalBytesSaved = "tinypress.lifetime.bytesSaved"
        static let totalPhotosCompressed = "tinypress.lifetime.photosCompressed"
    }

    private let defaults: UserDefaults

    private(set) var totalBytesSaved: Int64
    private(set) var totalPhotosCompressed: Int

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.totalBytesSaved = Int64(defaults.integer(forKey: Keys.totalBytesSaved))
        if let stored64 = defaults.object(forKey: Keys.totalBytesSaved) as? Int64 {
            self.totalBytesSaved = stored64
        }
        self.totalPhotosCompressed = defaults.integer(forKey: Keys.totalPhotosCompressed)
    }

    func recordSaving(bytesSaved: Int64, count: Int = 1) {
        guard bytesSaved > 0, count > 0 else { return }
        totalBytesSaved += bytesSaved
        totalPhotosCompressed += count
        defaults.set(totalBytesSaved, forKey: Keys.totalBytesSaved)
        defaults.set(totalPhotosCompressed, forKey: Keys.totalPhotosCompressed)
    }
}
