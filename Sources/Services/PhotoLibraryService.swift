import Foundation
import CoreLocation
import Photos
import UIKit
import UniformTypeIdentifiers

enum PhotoLibraryError: LocalizedError {
    case permissionDenied
    case assetDataUnavailable
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Photo library access is required to scan and save compressed photos."
        case .assetDataUnavailable:
            return "Original photo data could not be loaded from this device or iCloud."
        case .saveFailed(let reason):
            return "Failed to save compressed photo: \(reason)"
        }
    }
}

final class PhotoLibraryService {
    private let cachingManager = PHCachingImageManager()

    func currentAuthorizationStatus() -> PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    func requestReadWriteAuthorization() async -> PHAuthorizationStatus {
        await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }

    func scanAllPhotos(
        batchSize: Int = 80,
        onBatch: @MainActor @Sendable ([PhotoItem], Int, Int) -> Void
    ) async {
        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        let fetchResult = PHAsset.fetchAssets(with: fetchOptions)
        let totalCount = fetchResult.count
        if totalCount == 0 {
            await onBatch([], 0, 0)
            return
        }

        var buffer: [PhotoItem] = []
        buffer.reserveCapacity(batchSize)

        for index in 0..<totalCount {
            if Task.isCancelled { return }
            let asset = fetchResult.object(at: index)
            let item = Self.buildPhotoItem(from: asset)
            buffer.append(item)

            if buffer.count >= batchSize || index == totalCount - 1 {
                let batch = buffer
                buffer.removeAll(keepingCapacity: true)
                await onBatch(batch, index + 1, totalCount)
            }
        }
    }

    func loadThumbnail(
        for asset: PHAsset,
        targetSize: CGSize,
        completion: @escaping (UIImage?, PHImageRequestID) -> Void
    ) -> PHImageRequestID {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false

        var requestID: PHImageRequestID = PHInvalidImageRequestID
        requestID = cachingManager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        ) { image, _ in
            completion(image, requestID)
        }
        return requestID
    }

    func cancelThumbnailRequest(_ requestID: PHImageRequestID) {
        guard requestID != PHInvalidImageRequestID else { return }
        cachingManager.cancelImageRequest(requestID)
    }

    func fetchOriginalImageData(for asset: PHAsset) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let options = PHImageRequestOptions()
            options.version = .current
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false

            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, info in
                if let error = info?[PHImageErrorKey] as? Error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let data = data, !data.isEmpty else {
                    continuation.resume(throwing: PhotoLibraryError.assetDataUnavailable)
                    return
                }
                continuation.resume(returning: data)
            }
        }
    }

    func saveCompressedCopy(
        compressedData: Data,
        originalAsset: PHAsset,
        settings: CompressionSettings
    ) async throws -> String {
        let userAlbums = Self.fetchWritableAlbums(containing: originalAsset)

        var tempPairedVideoURL: URL?
        if originalAsset.mediaSubtypes.contains(.photoLive), settings.preserveLivePhotoMotion {
            tempPairedVideoURL = try? await exportPairedVideoToTempURL(for: originalAsset)
        }

        defer {
            if let tempURL = tempPairedVideoURL, FileManager.default.fileExists(atPath: tempURL.path) {
                try? FileManager.default.removeItem(at: tempURL)
            }
        }

        var createdLocalID: String?

        try await PHPhotoLibrary.shared().performChanges {
            let creationRequest = PHAssetCreationRequest.forAsset()

            let photoOptions = PHAssetResourceCreationOptions()
            photoOptions.uniformTypeIdentifier = settings.format.utType.identifier
            creationRequest.addResource(with: .photo, data: compressedData, options: photoOptions)

            if let videoURL = tempPairedVideoURL {
                let videoOptions = PHAssetResourceCreationOptions()
                videoOptions.shouldMoveFile = true
                creationRequest.addResource(with: .pairedVideo, fileURL: videoURL, options: videoOptions)
            }

            if settings.preserveMetadata {
                creationRequest.creationDate = originalAsset.creationDate
                creationRequest.location = originalAsset.location
            }
            creationRequest.isFavorite = originalAsset.isFavorite

            if let placeholder = creationRequest.placeholderForCreatedAsset {
                createdLocalID = placeholder.localIdentifier
                for album in userAlbums {
                    if let albumChange = PHAssetCollectionChangeRequest(for: album) {
                        albumChange.addAssets([placeholder] as NSArray)
                    }
                }
            }
        }

        guard let localID = createdLocalID else {
            throw PhotoLibraryError.saveFailed("Photos library did not return a new asset identifier.")
        }
        return localID
    }

    func promptDeleteOriginals(assetIDs: [String]) async throws {
        guard !assetIDs.isEmpty else { return }
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: assetIDs, options: nil)
        guard fetchResult.count > 0 else { return }

        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets(fetchResult)
        }
    }

    private func exportPairedVideoToTempURL(for asset: PHAsset) async throws -> URL? {
        let resources = PHAssetResource.assetResources(for: asset)
        guard let videoResource = resources.first(where: { $0.type == .fullSizePairedVideo })
            ?? resources.first(where: { $0.type == .pairedVideo }) else {
            return nil
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tinypress-live-\(UUID().uuidString)")
            .appendingPathExtension("mov")

        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHAssetResourceManager.default().writeData(for: videoResource, toFile: tempURL, options: options) { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
        return tempURL
    }

    private static func fetchWritableAlbums(containing asset: PHAsset) -> [PHAssetCollection] {
        let collections = PHAssetCollection.fetchAssetCollectionsContaining(asset, with: .album, options: nil)
        var writable: [PHAssetCollection] = []
        collections.enumerateObjects { collection, _, _ in
            if collection.canPerform(.addContent) {
                writable.append(collection)
            }
        }
        return writable
    }

    private static func buildPhotoItem(from asset: PHAsset) -> PhotoItem {
        let resources = PHAssetResource.assetResources(for: asset)
        let primaryResource = resources.first(where: { $0.type == .fullSizePhoto })
            ?? resources.first(where: { $0.type == .photo })
            ?? resources.first

        var sizeBytes: Int64 = 0
        if let resource = primaryResource, resource.responds(to: NSSelectorFromString("fileSize")) {
            if let num = resource.value(forKey: "fileSize") as? NSNumber {
                sizeBytes = num.int64Value
            }
        }

        return PhotoItem(
            id: asset.localIdentifier,
            asset: asset,
            fileSize: sizeBytes,
            pixelWidth: asset.pixelWidth,
            pixelHeight: asset.pixelHeight,
            creationDate: asset.creationDate,
            isFavorite: asset.isFavorite,
            isHDR: asset.mediaSubtypes.contains(.photoHDR),
            isLivePhoto: asset.mediaSubtypes.contains(.photoLive),
            isScreenshot: asset.mediaSubtypes.contains(.photoScreenshot),
            uniformTypeIdentifier: primaryResource?.uniformTypeIdentifier ?? UTType.heic.identifier
        )
    }
}
