import Foundation
import CoreGraphics
import Photos
import UIKit
import UniformTypeIdentifiers

enum OutputFormat: String, CaseIterable, Identifiable, Codable {
    case heic
    case jpeg

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .heic: return "HEIC"
        case .jpeg: return "JPEG"
        }
    }

    var subtitle: String {
        switch self {
        case .heic: return "Best savings & HDR"
        case .jpeg: return "Universal compatibility"
        }
    }

    var utType: UTType {
        switch self {
        case .heic: return .heic
        case .jpeg: return .jpeg
        }
    }
}

enum DimensionPreset: String, CaseIterable, Identifiable, Codable {
    case original
    case large
    case medium
    case compact

    var id: String { rawValue }

    var scaleFactor: CGFloat {
        switch self {
        case .original: return 1.0
        case .large: return 0.80
        case .medium: return 0.65
        case .compact: return 0.50
        }
    }

    var displayName: String {
        switch self {
        case .original: return "100%"
        case .large: return "80%"
        case .medium: return "65%"
        case .compact: return "50%"
        }
    }
}

struct CompressionSettings: Equatable, Codable {
    var quality: Double = 0.72
    var format: OutputFormat = .heic
    var dimensionPreset: DimensionPreset = .original
    var preserveHDRGainMap: Bool = true
    var preserveMetadata: Bool = true
    var preserveLivePhotoMotion: Bool = true
}

enum SortOrder: String, CaseIterable, Identifiable {
    case largestFirst
    case newestFirst
    case oldestFirst

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .largestFirst: return "Largest First"
        case .newestFirst: return "Newest First"
        case .oldestFirst: return "Oldest First"
        }
    }
}

enum MediaFilter: String, CaseIterable, Identifiable {
    case allPhotos
    case largeOver5MB
    case hdrOnly
    case livePhotos
    case screenshots

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .allPhotos: return "All"
        case .largeOver5MB: return "> 5 MB"
        case .hdrOnly: return "HDR"
        case .livePhotos: return "Live"
        case .screenshots: return "Screenshots"
        }
    }
}

struct PhotoItem: Identifiable, Hashable {
    let id: String
    let asset: PHAsset
    let fileSize: Int64
    let pixelWidth: Int
    let pixelHeight: Int
    let creationDate: Date?
    let isFavorite: Bool
    let isHDR: Bool
    let isLivePhoto: Bool
    let isScreenshot: Bool
    let uniformTypeIdentifier: String

    var megabytes: Double {
        Double(fileSize) / 1_048_576.0
    }

    var resolutionLabel: String {
        "\(pixelWidth) × \(pixelHeight)"
    }

    static func == (lhs: PhotoItem, rhs: PhotoItem) -> Bool {
        lhs.id == rhs.id &&
        lhs.fileSize == rhs.fileSize &&
        lhs.isFavorite == rhs.isFavorite
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct CompressionPreviewResult {
    let originalBytes: Int64
    let compressedData: Data
    let compressedBytes: Int64
    let originalUIImage: UIImage
    let compressedUIImage: UIImage
    let preservedHDR: Bool
    let preservedLivePhoto: Bool
    let outputWidth: Int
    let outputHeight: Int

    var savedBytes: Int64 {
        max(0, originalBytes - compressedBytes)
    }

    var savedRatio: Double {
        guard originalBytes > 0, compressedBytes < originalBytes else { return 0 }
        return Double(originalBytes - compressedBytes) / Double(originalBytes)
    }

    var isSmaller: Bool {
        compressedBytes > 0 && compressedBytes < originalBytes
    }
}

struct BatchSummary: Identifiable {
    let id = UUID()
    let processedCount: Int
    let skippedAlreadyOptimalCount: Int
    let failedCount: Int
    let totalOriginalBytes: Int64
    let totalCompressedBytes: Int64
    let originalAssetIDsToDelete: [String]
    let newlyCreatedAssetIDs: [String]

    var savedBytes: Int64 {
        max(0, totalOriginalBytes - totalCompressedBytes)
    }

    var savedRatio: Double {
        guard totalOriginalBytes > 0 else { return 0 }
        return Double(savedBytes) / Double(totalOriginalBytes)
    }
}

enum ByteFormatters {
    private static let formatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useKB, .useMB, .useGB]
        f.includesUnit = true
        f.isAdaptive = true
        return f
    }()

    static func formatBytes(_ bytes: Int64) -> String {
        formatter.string(fromByteCount: bytes)
    }

    static func formatPercent(_ ratio: Double) -> String {
        let pct = Int((ratio * 100).rounded())
        return "\(pct)%"
    }
}
