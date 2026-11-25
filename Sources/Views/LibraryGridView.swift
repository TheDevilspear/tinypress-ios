import Photos
import SwiftUI
import UIKit

struct LibraryGridView: View {
    @Bindable var viewModel: LibraryViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isSelectionMode = false

    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(spacing: DesignTokens.Spacing.md) {
                        summaryHeader
                        filterStrip
                        if viewModel.filteredAndSortedItems.isEmpty && !viewModel.isScanning {
                            emptyStateCard
                        } else {
                            photoGrid
                        }
                    }
                    .padding(.top, DesignTokens.Spacing.xs)
                    .padding(.bottom, viewModel.selectedIDs.isEmpty ? 28 : 104)
                }

                if !viewModel.selectedIDs.isEmpty {
                    floatingBatchBar
                        .transition(
                            reduceMotion
                                ? .opacity
                                : .move(edge: .bottom).combined(with: .opacity)
                        )
                }
            }
            .animation(reduceMotion ? nil : DesignTokens.Motion.snappySpring, value: viewModel.selectedIDs.isEmpty)
            .background(DesignTokens.Colors.background.ignoresSafeArea())
            .navigationTitle("TinyPress")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Sort Order", selection: $viewModel.sortOrder) {
                            ForEach(SortOrder.allCases) { order in
                                Text(order.displayName).tag(order)
                            }
                        }
                        Divider()
                        Button("Select Top 25 Largest") {
                            DesignTokens.Haptics.impact(.medium)
                            if reduceMotion {
                                isSelectionMode = true
                            } else {
                                withAnimation(DesignTokens.Motion.snappySpring) {
                                    isSelectionMode = true
                                }
                            }
                            viewModel.selectTopLargest(limit: 25)
                        }
                        Button("Rescan Library") {
                            DesignTokens.Haptics.impact(.light)
                            viewModel.startScan()
                        }
                    } label: {
                        Label("Sort", systemImage: "arrow.up.arrow.down.circle")
                            .frame(minWidth: DesignTokens.TouchTarget.minimum, minHeight: DesignTokens.TouchTarget.minimum)
                    }
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        DesignTokens.Haptics.impact(.light)
                        let toggle = {
                            isSelectionMode.toggle()
                            if !isSelectionMode {
                                viewModel.clearSelection()
                            }
                        }
                        if reduceMotion {
                            toggle()
                        } else {
                            withAnimation(DesignTokens.Motion.snappySpring) {
                                toggle()
                            }
                        }
                    } label: {
                        Text(isSelectionMode ? "Done" : "Select")
                            .fontWeight(isSelectionMode ? .semibold : .regular)
                            .frame(minWidth: DesignTokens.TouchTarget.minimum, minHeight: DesignTokens.TouchTarget.minimum)
                    }

                    Button {
                        DesignTokens.Haptics.impact(.light)
                        viewModel.isSettingsPresented = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .frame(minWidth: DesignTokens.TouchTarget.minimum, minHeight: DesignTokens.TouchTarget.minimum)
                    }
                    .accessibilityLabel("Compression Settings")
                }
            }
            .sheet(item: $viewModel.inspectorItem) { item in
                PhotoComparisonView(viewModel: viewModel.makeInspectorViewModel(for: item))
            }
            .sheet(isPresented: $viewModel.isSettingsPresented) {
                CompressionSettingsSheet(settings: $viewModel.settings)
            }
            .sheet(isPresented: $viewModel.isBatchSheetPresented) {
                BatchCompressionSheet(viewModel: viewModel)
            }
        }
    }

    private var summaryHeader: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Library Scanned")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                Text(ByteFormatters.formatBytes(viewModel.totalLibraryBytes))
                    .font(DesignTokens.Typography.largeMetric)
                    .contentTransition(.numericText())
                if viewModel.isScanning {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.mini)
                        Text("Scanning \(viewModel.scanProcessedCount)/\(viewModel.scanTotalCount)")
                            .font(DesignTokens.Typography.caption.monospacedDigit())
                            .foregroundStyle(DesignTokens.Colors.accent)
                            .contentTransition(.numericText())
                    }
                } else {
                    Text("\(viewModel.items.count) photos")
                        .font(DesignTokens.Typography.caption.monospacedDigit())
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("Lifetime Saved")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                Text(ByteFormatters.formatBytes(viewModel.statsStore.totalBytesSaved))
                    .font(DesignTokens.Typography.largeMetric)
                    .foregroundStyle(DesignTokens.Colors.success)
                    .contentTransition(.numericText())
                Text("\(viewModel.statsStore.totalPhotosCompressed) compressed")
                    .font(DesignTokens.Typography.caption.monospacedDigit())
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            }
        }
        .padding(DesignTokens.Spacing.lg)
        .background(
            DesignTokens.Colors.secondarySurface,
            in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous)
                .stroke(DesignTokens.Colors.cardBorder, lineWidth: 1)
        )
        .padding(.horizontal, DesignTokens.Spacing.lg)
    }

    private var filterStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DesignTokens.Spacing.sm) {
                ForEach(MediaFilter.allCases) { filter in
                    let isSelected = viewModel.activeFilter == filter
                    Button {
                        guard viewModel.activeFilter != filter else { return }
                        DesignTokens.Haptics.impact(.light)
                        if reduceMotion {
                            viewModel.activeFilter = filter
                        } else {
                            withAnimation(DesignTokens.Motion.snappySpring) {
                                viewModel.activeFilter = filter
                            }
                        }
                    } label: {
                        Text(filter.displayName)
                            .font(DesignTokens.Typography.caption.weight(isSelected ? .semibold : .medium))
                            .padding(.horizontal, DesignTokens.Spacing.md)
                            .padding(.vertical, DesignTokens.Spacing.sm)
                            .background(
                                isSelected ? DesignTokens.Colors.accent : DesignTokens.Colors.secondarySurface,
                                in: Capsule()
                            )
                            .overlay(
                                Capsule()
                                    .stroke(
                                        isSelected ? Color.clear : DesignTokens.Colors.cardBorder,
                                        lineWidth: 1
                                    )
                            )
                            .foregroundStyle(isSelected ? Color.white : DesignTokens.Colors.textPrimary)
                            .frame(minHeight: DesignTokens.TouchTarget.minimum)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)
        }
    }

    private var emptyStateCard: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 36))
                .foregroundStyle(DesignTokens.Colors.textSecondary)
            Text("No matching photos")
                .font(DesignTokens.Typography.headline)
            Text(viewModel.activeFilter == .allPhotos
                 ? "Your library has no compressible photos yet."
                 : "No photos match the \(viewModel.activeFilter.displayName) filter.")
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .multilineTextAlignment(.center)
            if viewModel.activeFilter != .allPhotos {
                Button("Show All Photos") {
                    DesignTokens.Haptics.impact(.light)
                    viewModel.activeFilter = .allPhotos
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .frame(minHeight: DesignTokens.TouchTarget.minimum)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(DesignTokens.Spacing.xl)
        .background(
            DesignTokens.Colors.secondarySurface,
            in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous)
                .stroke(DesignTokens.Colors.cardBorder, lineWidth: 1)
        )
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.top, DesignTokens.Spacing.sm)
    }

    private var photoGrid: some View {
        LazyVGrid(columns: columns, spacing: 2) {
            ForEach(viewModel.filteredAndSortedItems) { item in
                let isSelected = viewModel.selectedIDs.contains(item.id)
                Button {
                    if isSelectionMode {
                        DesignTokens.Haptics.impact(.light)
                        viewModel.toggleSelection(for: item)
                    } else {
                        DesignTokens.Haptics.impact(.light)
                        viewModel.inspectorItem = item
                    }
                } label: {
                    GeometryReader { geo in
                        ZStack(alignment: .topTrailing) {
                            AsyncAssetThumbnailView(
                                item: item,
                                targetSize: CGSize(width: geo.size.width * 2, height: geo.size.width * 2),
                                loadThumbnail: { asset, size, done in
                                    viewModel.loadThumbnail(for: asset, targetSize: size, completion: done)
                                },
                                cancelRequest: { reqID in
                                    viewModel.cancelThumbnailRequest(reqID)
                                }
                            )
                            .frame(width: geo.size.width, height: geo.size.width)

                            VStack {
                                HStack {
                                    if item.isHDR || item.isLivePhoto {
                                        GlassBadge(
                                            text: item.isHDR ? "HDR" : "LIVE",
                                            systemImage: item.isHDR ? "sun.max.fill" : "livephoto"
                                        )
                                    }
                                    Spacer()
                                    if isSelectionMode {
                                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                            .font(.title3.weight(.semibold))
                                            .foregroundStyle(isSelected ? DesignTokens.Colors.accent : .white)
                                            .background(
                                                Circle()
                                                    .fill(isSelected ? Color.white : Color.black.opacity(0.35))
                                                    .padding(2)
                                            )
                                            .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                                    }
                                }
                                Spacer()
                                HStack {
                                    GlassBadge(text: ByteFormatters.formatBytes(item.fileSize))
                                    Spacer()
                                }
                            }
                            .padding(6)
                        }
                    }
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        if isSelected {
                            Rectangle()
                                .strokeBorder(DesignTokens.Colors.accent, lineWidth: 3)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var floatingBatchBar: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(viewModel.selectedIDs.count) selected")
                    .font(DesignTokens.Typography.headline.monospacedDigit())
                    .contentTransition(.numericText())
                Text(ByteFormatters.formatBytes(viewModel.selectedBytes))
                    .font(DesignTokens.Typography.monoMetric)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .contentTransition(.numericText())
            }

            Spacer()

            Button {
                DesignTokens.Haptics.impact(.medium)
                viewModel.startBatchCompression()
            } label: {
                Text("Compress")
                    .font(DesignTokens.Typography.headline)
                    .padding(.horizontal, DesignTokens.Spacing.sm)
                    .frame(minHeight: DesignTokens.TouchTarget.minimum)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.vertical, DesignTokens.Spacing.sm)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous)
                .stroke(DesignTokens.Colors.glassStroke, lineWidth: 0.75)
        )
        .shadow(color: .black.opacity(0.22), radius: 14, y: 6)
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.bottom, DesignTokens.Spacing.sm)
    }
}

private struct GlassBadge: View {
    let text: String
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: 3) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 8, weight: .bold))
            }
            Text(text)
                .font(DesignTokens.Typography.badge)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background {
            ZStack {
                Capsule().fill(.ultraThinMaterial)
                Capsule().fill(DesignTokens.Colors.glassTint)
            }
        }
        .overlay(
            Capsule()
                .stroke(DesignTokens.Colors.glassStroke, lineWidth: 0.6)
        )
    }
}
