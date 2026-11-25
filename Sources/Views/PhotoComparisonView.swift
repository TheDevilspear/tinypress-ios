import SwiftUI
import UIKit

struct PhotoComparisonView: View {
    @State var viewModel: InspectorViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isSnappedToCenter = true
    @State private var isAtEdge = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DesignTokens.Spacing.lg) {
                    comparisonViewport
                    metricsBanner
                    metadataChips
                    controlsCard
                    actionButtons
                }
                .padding(DesignTokens.Spacing.lg)
            }
            .background(DesignTokens.Colors.background.ignoresSafeArea())
            .navigationTitle("Compare & Compress")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        DesignTokens.Haptics.impact(.light)
                        dismiss()
                    } label: {
                        Text("Close")
                            .frame(minWidth: DesignTokens.TouchTarget.minimum, minHeight: DesignTokens.TouchTarget.minimum)
                    }
                }
            }
            .task {
                await viewModel.loadInitialPreview()
            }
            .onChange(of: viewModel.settings) { _, _ in
                viewModel.schedulePreviewRegeneration()
            }
            .onChange(of: viewModel.savedNewAssetID) { oldID, newID in
                if oldID == nil && newID != nil {
                    DesignTokens.Haptics.notify(.success)
                }
            }
            .onChange(of: viewModel.didDeleteOriginal) { _, deleted in
                if deleted {
                    DesignTokens.Haptics.notify(.success)
                }
            }
            .onChange(of: viewModel.errorMessage) { _, err in
                if err != nil {
                    DesignTokens.Haptics.notify(.error)
                }
            }
        }
    }

    private var comparisonViewport: some View {
        GeometryReader { geo in
            ZStack {
                DesignTokens.Colors.viewportSurface

                if let preview = viewModel.preview {
                    Image(uiImage: preview.compressedUIImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: geo.size.width, height: geo.size.height)

                    Image(uiImage: preview.originalUIImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .mask(alignment: .leading) {
                            Rectangle()
                                .frame(width: geo.size.width * viewModel.sliderSplit)
                        }

                    let dividerX = geo.size.width * viewModel.sliderSplit
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: 2, height: geo.size.height)
                        .shadow(color: .black.opacity(0.45), radius: 2)
                        .position(x: dividerX, y: geo.size.height / 2)

                    ZStack {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 34, height: 34)
                        Circle()
                            .fill(Color.white.opacity(0.92))
                            .frame(width: 32, height: 32)
                        Image(systemName: "arrow.left.and.right")
                            .font(.caption.bold())
                            .foregroundStyle(.black)
                    }
                    .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
                    .frame(width: DesignTokens.TouchTarget.minimum, height: DesignTokens.TouchTarget.minimum)
                    .contentShape(Rectangle())
                    .position(x: dividerX, y: geo.size.height / 2)

                    VStack {
                        HStack {
                            ViewportGlassLabel(text: "ORIGINAL")
                            Spacer()
                            ViewportGlassLabel(text: "COMPRESSED")
                        }
                        Spacer()
                    }
                    .padding(DesignTokens.Spacing.sm)
                } else if viewModel.isLoadingPreview {
                    VStack(spacing: DesignTokens.Spacing.sm) {
                        ProgressView()
                            .tint(.white)
                        Text("Preparing on-device preview...")
                            .font(DesignTokens.Typography.caption)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                } else if let error = viewModel.errorMessage {
                    Text(error)
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Colors.danger)
                        .padding()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous)
                    .stroke(DesignTokens.Colors.cardBorder, lineWidth: 1)
            )
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let raw = min(max(value.location.x / max(1, geo.size.width), 0.05), 0.95)
                        let snapThreshold: CGFloat = 0.025
                        let snapped: CGFloat
                        if abs(raw - 0.5) <= snapThreshold {
                            snapped = 0.5
                            if !isSnappedToCenter {
                                isSnappedToCenter = true
                                DesignTokens.Haptics.impact(.rigid)
                            }
                        } else {
                            snapped = raw
                            isSnappedToCenter = false
                        }

                        let hitEdge = (snapped <= 0.051 || snapped >= 0.949)
                        if hitEdge && !isAtEdge {
                            isAtEdge = true
                            DesignTokens.Haptics.impact(.light)
                        } else if !hitEdge {
                            isAtEdge = false
                        }

                        viewModel.sliderSplit = snapped
                    }
            )
            .onTapGesture(count: 2) {
                DesignTokens.Haptics.impact(.rigid)
                isSnappedToCenter = true
                if reduceMotion {
                    viewModel.sliderSplit = 0.5
                } else {
                    withAnimation(DesignTokens.Motion.snappySpring) {
                        viewModel.sliderSplit = 0.5
                    }
                }
            }
        }
        .frame(height: 340)
    }

    private var metricsBanner: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Original")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                Text(ByteFormatters.formatBytes(viewModel.effectiveOriginalBytes))
                    .font(DesignTokens.Typography.monoMetric)
                    .contentTransition(.numericText())
            }

            Spacer()

            if let preview = viewModel.preview {
                VStack(spacing: 3) {
                    HStack(spacing: 4) {
                        Image(systemName: preview.isSmaller ? "arrow.down.right.circle.fill" : "exclamationmark.triangle.fill")
                            .font(.caption.weight(.bold))
                        Text(preview.isSmaller ? "-\(ByteFormatters.formatPercent(preview.savedRatio))" : "No Savings")
                            .font(DesignTokens.Typography.headline.monospacedDigit())
                    }
                    .foregroundStyle(preview.isSmaller ? DesignTokens.Colors.success : DesignTokens.Colors.warning)
                    .contentTransition(.numericText())

                    Text("\(preview.outputWidth)×\(preview.outputHeight)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("Compressed")
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                    Text(ByteFormatters.formatBytes(preview.compressedBytes))
                        .font(DesignTokens.Typography.monoMetric)
                        .foregroundStyle(preview.isSmaller ? DesignTokens.Colors.success : DesignTokens.Colors.warning)
                        .contentTransition(.numericText())
                }
            }
        }
        .padding(DesignTokens.Spacing.md)
        .background(
            DesignTokens.Colors.secondarySurface,
            in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                .stroke(DesignTokens.Colors.cardBorder, lineWidth: 1)
        )
    }

    private var metadataChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DesignTokens.Spacing.sm) {
                if viewModel.settings.preserveMetadata {
                    ChipBadge(label: "EXIF & Date", systemImage: "calendar")
                    ChipBadge(label: "GPS & Albums", systemImage: "location.fill")
                }
                if viewModel.item.isFavorite {
                    ChipBadge(label: "Favorite", systemImage: "heart.fill")
                }
                if viewModel.preview?.preservedHDR == true {
                    ChipBadge(label: "HDR Gain Map", systemImage: "sun.max.fill")
                }
                if viewModel.preview?.preservedLivePhoto == true {
                    ChipBadge(label: "Live Motion", systemImage: "livephoto")
                }
            }
        }
    }

    private var controlsCard: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Quality")
                        .font(DesignTokens.Typography.headline)
                    Spacer()
                    Text("\(Int((viewModel.settings.quality * 100).rounded()))%")
                        .font(DesignTokens.Typography.monoMetric)
                        .contentTransition(.numericText())
                }
                Slider(value: $viewModel.settings.quality, in: 0.40...0.95, step: 0.05)
                    .onChange(of: viewModel.settings.quality) { _, _ in
                        DesignTokens.Haptics.impact(.soft)
                    }
            }

            Picker("Format", selection: $viewModel.settings.format) {
                ForEach(OutputFormat.allCases) { format in
                    Text(format.displayName).tag(format)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: viewModel.settings.format) { _, _ in
                DesignTokens.Haptics.impact(.light)
            }

            Picker("Resolution", selection: $viewModel.settings.dimensionPreset) {
                ForEach(DimensionPreset.allCases) { preset in
                    Text(preset.displayName).tag(preset)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: viewModel.settings.dimensionPreset) { _, _ in
                DesignTokens.Haptics.impact(.light)
            }
        }
        .padding(DesignTokens.Spacing.md)
        .background(
            DesignTokens.Colors.secondarySurface,
            in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                .stroke(DesignTokens.Colors.cardBorder, lineWidth: 1)
        )
    }

    private var actionButtons: some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            if let error = viewModel.errorMessage {
                Label(error, systemImage: "exclamationmark.circle.fill")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.danger)
            }

            if viewModel.savedNewAssetID == nil {
                Button {
                    DesignTokens.Haptics.impact(.medium)
                    Task { await viewModel.saveCompressedCopy() }
                } label: {
                    if viewModel.isSaving {
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: DesignTokens.TouchTarget.buttonHeight)
                    } else {
                        Text("Save Compressed Copy")
                            .font(DesignTokens.Typography.headline)
                            .frame(maxWidth: .infinity, minHeight: DesignTokens.TouchTarget.buttonHeight)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.preview == nil || viewModel.isSaving)
            } else if !viewModel.didDeleteOriginal {
                Label("Compressed copy saved to Apple Photos.", systemImage: "checkmark.circle.fill")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.success)

                Button(role: .destructive) {
                    DesignTokens.Haptics.impact(.medium)
                    Task { await viewModel.deleteOriginal() }
                } label: {
                    Text("Delete Original (\(ByteFormatters.formatBytes(viewModel.effectiveOriginalBytes)))")
                        .font(DesignTokens.Typography.headline.monospacedDigit())
                        .frame(maxWidth: .infinity, minHeight: DesignTokens.TouchTarget.buttonHeight)
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isDeletingOriginal)
            } else {
                Label("Original moved to Recently Deleted.", systemImage: "trash.fill")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                Button {
                    DesignTokens.Haptics.impact(.light)
                    dismiss()
                } label: {
                    Text("Done")
                        .font(DesignTokens.Typography.headline)
                        .frame(maxWidth: .infinity, minHeight: DesignTokens.TouchTarget.buttonHeight)
                }
                .buttonStyle(.bordered)
            }
        }
        .animation(reduceMotion ? nil : DesignTokens.Motion.snappySpring, value: viewModel.savedNewAssetID)
        .animation(reduceMotion ? nil : DesignTokens.Motion.snappySpring, value: viewModel.didDeleteOriginal)
    }
}

private struct ViewportGlassLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(DesignTokens.Typography.badge)
            .tracking(0.6)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
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
            .foregroundStyle(.white)
    }
}

private struct ChipBadge: View {
    let label: String
    let systemImage: String

    var body: some View {
        Label(label, systemImage: systemImage)
            .font(DesignTokens.Typography.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(DesignTokens.Colors.secondarySurface, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(DesignTokens.Colors.cardBorder, lineWidth: 1)
            )
    }
}
