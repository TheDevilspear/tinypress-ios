import Foundation
import Observation
import Photos
import UIKit

@MainActor
@Observable
final class LibraryViewModel {
    private let libraryService: PhotoLibraryService
    private let compressionEngine: CompressionEngine
    let statsStore: LifetimeStatsStore

    var authorizationStatus: PHAuthorizationStatus
    var items: [PhotoItem] = []
    var selectedIDs: Set<String> = []
    var sortOrder: SortOrder = .largestFirst
    var activeFilter: MediaFilter = .allPhotos
    var settings = CompressionSettings()

    var isScanning = false
    var scanProcessedCount = 0
    var scanTotalCount = 0

    var inspectorItem: PhotoItem?
    var isSettingsPresented = false

    var isBatchSheetPresented = false
    var isBatchRunning = false
    var batchCurrentIndex = 0
    var batchTotalCount = 0
    var batchRunningSavedBytes: Int64 = 0
    var batchSummary: BatchSummary?
    var batchErrorMessage: String?

    private var scanTask: Task<Void, Never>?
    private var batchTask: Task<Void, Never>?

    init(
        libraryService: PhotoLibraryService = PhotoLibraryService(),
        compressionEngine: CompressionEngine = CompressionEngine(),
        statsStore: LifetimeStatsStore? = nil
    ) {
        self.libraryService = libraryService
        self.compressionEngine = compressionEngine
        self.statsStore = statsStore ?? LifetimeStatsStore()
        self.authorizationStatus = libraryService.currentAuthorizationStatus()
    }

    var filteredAndSortedItems: [PhotoItem] {
        let filtered: [PhotoItem]
        switch activeFilter {
        case .allPhotos:
            filtered = items
        case .largeOver5MB:
            filtered = items.filter { $0.fileSize >= 5 * 1_048_576 }
        case .hdrOnly:
            filtered = items.filter { $0.isHDR }
        case .livePhotos:
            filtered = items.filter { $0.isLivePhoto }
        case .screenshots:
            filtered = items.filter { $0.isScreenshot }
        }

        switch sortOrder {
        case .largestFirst:
            return filtered.sorted {
                if $0.fileSize != $1.fileSize {
                    return $0.fileSize > $1.fileSize
                }
                return ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast)
            }
        case .newestFirst:
            return filtered.sorted {
                ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast)
            }
        case .oldestFirst:
            return filtered.sorted {
                ($0.creationDate ?? .distantFuture) < ($1.creationDate ?? .distantFuture)
            }
        }
    }

    var totalLibraryBytes: Int64 {
        items.reduce(0) { $0 + $1.fileSize }
    }

    var selectedBytes: Int64 {
        items
            .filter { selectedIDs.contains($0.id) }
            .reduce(0) { $0 + $1.fileSize }
    }

    var hasLibraryAccess: Bool {
        authorizationStatus == .authorized || authorizationStatus == .limited
    }

    func refreshAuthorizationAndScanIfNeeded() {
        authorizationStatus = libraryService.currentAuthorizationStatus()
        if hasLibraryAccess && items.isEmpty && !isScanning {
            startScan()
        }
    }

    func requestPermissionAndScan() async {
        let status = await libraryService.requestReadWriteAuthorization()
        authorizationStatus = status
        if hasLibraryAccess {
            startScan()
        }
    }

    func startScan() {
        scanTask?.cancel()
        items = []
        selectedIDs = []
        isScanning = true
        scanProcessedCount = 0
        scanTotalCount = 0

        scanTask = Task { [weak self] in
            guard let self else { return }
            await libraryService.scanAllPhotos(batchSize: 80) { batch, processed, total in
                self.items.append(contentsOf: batch)
                self.scanProcessedCount = processed
                self.scanTotalCount = total
            }
            if !Task.isCancelled {
                self.isScanning = false
            }
        }
    }

    func toggleSelection(for item: PhotoItem) {
        if selectedIDs.contains(item.id) {
            selectedIDs.remove(item.id)
        } else {
            selectedIDs.insert(item.id)
        }
    }

    func selectTopLargest(limit: Int = 25) {
        let topIDs = filteredAndSortedItems.prefix(limit).map(\.id)
        selectedIDs = Set(topIDs)
    }

    func clearSelection() {
        selectedIDs.removeAll()
    }

    func makeInspectorViewModel(for item: PhotoItem) -> InspectorViewModel {
        InspectorViewModel(
            item: item,
            initialSettings: settings,
            libraryService: libraryService,
            compressionEngine: compressionEngine,
            statsStore: statsStore
        ) { [weak self] deletedAssetID in
            self?.removeAssetFromLocalState(id: deletedAssetID)
        }
    }

    func startBatchCompression() {
        let targets = filteredAndSortedItems.filter { selectedIDs.contains($0.id) }
        guard !targets.isEmpty else { return }

        batchTask?.cancel()
        isBatchSheetPresented = true
        isBatchRunning = true
        batchCurrentIndex = 0
        batchTotalCount = targets.count
        batchRunningSavedBytes = 0
        batchSummary = nil
        batchErrorMessage = nil

        let activeSettings = settings

        batchTask = Task { [weak self] in
            guard let self else { return }
            var processed = 0
            var skippedOptimal = 0
            var failed = 0
            var totalOriginal: Int64 = 0
            var totalCompressed: Int64 = 0
            var originalsToDelete: [String] = []
            var createdIDs: [String] = []

            for (idx, item) in targets.enumerated() {
                if Task.isCancelled { break }
                self.batchCurrentIndex = idx + 1

                do {
                    let originalData = try await libraryService.fetchOriginalImageData(for: item.asset)
                    let originalBytes = item.fileSize > 0 ? item.fileSize : Int64(originalData.count)
                    let compressedData = try await compressionEngine.compressForBatch(
                        sourceData: originalData,
                        isLivePhoto: item.isLivePhoto,
                        settings: activeSettings
                    )
                    let compressedBytes = Int64(compressedData.count)

                    if compressedBytes >= originalBytes {
                        skippedOptimal += 1
                        continue
                    }

                    let newID = try await libraryService.saveCompressedCopy(
                        compressedData: compressedData,
                        originalAsset: item.asset,
                        settings: activeSettings
                    )

                    processed += 1
                    totalOriginal += originalBytes
                    totalCompressed += compressedBytes
                    self.batchRunningSavedBytes += (originalBytes - compressedBytes)
                    originalsToDelete.append(item.id)
                    createdIDs.append(newID)
                } catch {
                    failed += 1
                }
            }

            let saved = max(0, totalOriginal - totalCompressed)
            if saved > 0 {
                self.statsStore.recordSaving(bytesSaved: saved, count: processed)
            }

            self.batchSummary = BatchSummary(
                processedCount: processed,
                skippedAlreadyOptimalCount: skippedOptimal,
                failedCount: failed,
                totalOriginalBytes: totalOriginal,
                totalCompressedBytes: totalCompressed,
                originalAssetIDsToDelete: originalsToDelete,
                newlyCreatedAssetIDs: createdIDs
            )
            self.isBatchRunning = false
        }
    }

    func cancelBatchCompression() {
        batchTask?.cancel()
        isBatchRunning = false
    }

    func deleteBatchOriginals() async {
        guard let summary = batchSummary, !summary.originalAssetIDsToDelete.isEmpty else { return }
        do {
            try await libraryService.promptDeleteOriginals(assetIDs: summary.originalAssetIDsToDelete)
            let deletedSet = Set(summary.originalAssetIDsToDelete)
            items.removeAll { deletedSet.contains($0.id) }
            selectedIDs.subtract(deletedSet)
            isBatchSheetPresented = false
            startScan()
        } catch {
            batchErrorMessage = error.localizedDescription
        }
    }

    func removeAssetFromLocalState(id: String) {
        items.removeAll { $0.id == id }
        selectedIDs.remove(id)
    }

    func loadThumbnail(for asset: PHAsset, targetSize: CGSize, completion: @escaping (UIImage?, PHImageRequestID) -> Void) -> PHImageRequestID {
        libraryService.loadThumbnail(for: asset, targetSize: targetSize, completion: completion)
    }

    func cancelThumbnailRequest(_ requestID: PHImageRequestID) {
        libraryService.cancelThumbnailRequest(requestID)
    }
}
