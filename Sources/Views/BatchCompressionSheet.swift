import SwiftUI
import UIKit

struct BatchCompressionSheet: View {
    @Bindable var viewModel: LibraryViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            VStack(spacing: DesignTokens.Spacing.xl) {
                if viewModel.isBatchRunning {
                    Spacer()

                    VStack(spacing: DesignTokens.Spacing.lg) {
                        ProgressView(
                            value: Double(viewModel.batchCurrentIndex),
                            total: Double(max(1, viewModel.batchTotalCount))
                        )
                        .progressViewStyle(.linear)
                        .tint(DesignTokens.Colors.accent)

                        VStack(spacing: DesignTokens.Spacing.xs) {
                            Text("Compressing \(viewModel.batchCurrentIndex) of \(viewModel.batchTotalCount)")
                                .font(DesignTokens.Typography.headline.monospacedDigit())
                                .contentTransition(.numericText())

                            Text("Saved so far: \(ByteFormatters.formatBytes(viewModel.batchRunningSavedBytes))")
                                .font(DesignTokens.Typography.monoMetric)
                                .foregroundStyle(DesignTokens.Colors.success)
                                .contentTransition(.numericText())
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

                    Spacer()

                    Button(role: .cancel) {
                        DesignTokens.Haptics.impact(.light)
                        viewModel.cancelBatchCompression()
                    } label: {
                        Text("Cancel")
                            .font(DesignTokens.Typography.headline)
                            .frame(maxWidth: .infinity, minHeight: DesignTokens.TouchTarget.buttonHeight)
                    }
                    .buttonStyle(.bordered)
                } else if let summary = viewModel.batchSummary {
                    Spacer()

                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(DesignTokens.Colors.success)

                    VStack(spacing: DesignTokens.Spacing.xs) {
                        Text("Batch Complete")
                            .font(DesignTokens.Typography.title)
                        Text("Saved \(ByteFormatters.formatBytes(summary.savedBytes)) across \(summary.processedCount) photos")
                            .font(DesignTokens.Typography.headline.monospacedDigit())
                            .foregroundStyle(DesignTokens.Colors.success)
                        if summary.skippedAlreadyOptimalCount > 0 {
                            Text("\(summary.skippedAlreadyOptimalCount) photos skipped (already smaller than compressed output)")
                                .font(DesignTokens.Typography.caption.monospacedDigit())
                                .foregroundStyle(DesignTokens.Colors.textSecondary)
                        }
                    }
                    .multilineTextAlignment(.center)

                    if let err = viewModel.batchErrorMessage {
                        Label(err, systemImage: "exclamationmark.triangle.fill")
                            .font(DesignTokens.Typography.caption)
                            .foregroundStyle(DesignTokens.Colors.danger)
                    }

                    Spacer()

                    VStack(spacing: DesignTokens.Spacing.sm) {
                        if !summary.originalAssetIDsToDelete.isEmpty {
                            Button(role: .destructive) {
                                DesignTokens.Haptics.impact(.medium)
                                Task { await viewModel.deleteBatchOriginals() }
                            } label: {
                                Text("Delete \(summary.originalAssetIDsToDelete.count) Originals (Free \(ByteFormatters.formatBytes(summary.savedBytes)))")
                                    .font(DesignTokens.Typography.headline.monospacedDigit())
                                    .frame(maxWidth: .infinity, minHeight: DesignTokens.TouchTarget.buttonHeight)
                            }
                            .buttonStyle(.borderedProminent)
                        }

                        Button {
                            DesignTokens.Haptics.impact(.light)
                            dismiss()
                        } label: {
                            Text("Keep Both & Close")
                                .font(DesignTokens.Typography.headline)
                                .frame(maxWidth: .infinity, minHeight: DesignTokens.TouchTarget.buttonHeight)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding(DesignTokens.Spacing.xl)
            .background(DesignTokens.Colors.background.ignoresSafeArea())
            .navigationTitle("Batch Compression")
            .navigationBarTitleDisplayMode(.inline)
            .animation(reduceMotion ? nil : DesignTokens.Motion.gentleSpring, value: viewModel.isBatchRunning)
            .onChange(of: viewModel.isBatchRunning) { wasRunning, isRunning in
                if wasRunning && !isRunning && viewModel.batchSummary != nil {
                    DesignTokens.Haptics.notify(.success)
                }
            }
            .onChange(of: viewModel.batchErrorMessage) { _, err in
                if err != nil {
                    DesignTokens.Haptics.notify(.error)
                }
            }
        }
    }
}
