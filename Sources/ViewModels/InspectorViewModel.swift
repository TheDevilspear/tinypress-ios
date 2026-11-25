import Foundation
import Observation
import Photos
import SwiftUI

@MainActor
@Observable
final class InspectorViewModel {
    let item: PhotoItem
    private let libraryService: PhotoLibraryService
    private let compressionEngine: CompressionEngine
    private let statsStore: LifetimeStatsStore
    private let onOriginalDeleted: (String) -> Void

    var settings: CompressionSettings
    var sliderSplit: CGFloat = 0.5

    var isLoadingPreview = true
    var isSaving = false
    var isDeletingOriginal = false
    var preview: CompressionPreviewResult?
    var savedNewAssetID: String?
    var didDeleteOriginal = false
    var errorMessage: String?

    private var cachedSourceData: Data?
    private var previewTask: Task<Void, Never>?

    init(
        item: PhotoItem,
        initialSettings: CompressionSettings,
        libraryService: PhotoLibraryService,
        compressionEngine: CompressionEngine,
        statsStore: LifetimeStatsStore,
        onOriginalDeleted: @escaping (String) -> Void
    ) {
        self.item = item
        self.settings = initialSettings
        self.libraryService = libraryService
        self.compressionEngine = compressionEngine
        self.statsStore = statsStore
        self.onOriginalDeleted = onOriginalDeleted
    }

    var effectiveOriginalBytes: Int64 {
        if item.fileSize > 0 { return item.fileSize }
        return Int64(cachedSourceData?.count ?? 0)
    }

    func loadInitialPreview() async {
        isLoadingPreview = true
        errorMessage = nil
        do {
            let sourceData = try await libraryService.fetchOriginalImageData(for: item.asset)
            cachedSourceData = sourceData
            await regeneratePreview(debounce: false)
        } catch {
            errorMessage = error.localizedDescription
            isLoadingPreview = false
        }
    }

    func schedulePreviewRegeneration() {
        previewTask?.cancel()
        previewTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 160_000_000)
            guard !Task.isCancelled else { return }
            await self?.regeneratePreview(debounce: true)
        }
    }

    private func regeneratePreview(debounce: Bool) async {
        guard let sourceData = cachedSourceData else { return }
        if !debounce {
            isLoadingPreview = true
        }
        do {
            let result = try await compressionEngine.generatePreview(
                sourceData: sourceData,
                originalBytes: effectiveOriginalBytes,
                isLivePhoto: item.isLivePhoto,
                settings: settings
            )
            if !Task.isCancelled {
                self.preview = result
                self.isLoadingPreview = false
                self.errorMessage = nil
            }
        } catch {
            if !Task.isCancelled {
                self.errorMessage = error.localizedDescription
                self.isLoadingPreview = false
            }
        }
    }

    func saveCompressedCopy() async {
        guard let preview = preview, !isSaving else { return }
        isSaving = true
        errorMessage = nil

        do {
            let newID = try await libraryService.saveCompressedCopy(
                compressedData: preview.compressedData,
                originalAsset: item.asset,
                settings: settings
            )
            savedNewAssetID = newID
            if preview.isSmaller {
                statsStore.recordSaving(bytesSaved: preview.savedBytes, count: 1)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }

    func deleteOriginal() async {
        guard !isDeletingOriginal else { return }
        isDeletingOriginal = true
        errorMessage = nil

        do {
            try await libraryService.promptDeleteOriginals(assetIDs: [item.id])
            didDeleteOriginal = true
            onOriginalDeleted(item.id)
        } catch {
            errorMessage = error.localizedDescription
        }
        isDeletingOriginal = false
    }
}
