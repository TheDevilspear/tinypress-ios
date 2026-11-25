import Photos
import PhotosUI
import SwiftUI
import UIKit

struct RootContentView: View {
    @Bindable var viewModel: LibraryViewModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if viewModel.hasLibraryAccess {
                LibraryGridView(viewModel: viewModel)
            } else {
                PermissionOnboardingView(
                    status: viewModel.authorizationStatus,
                    onRequestPermission: {
                        DesignTokens.Haptics.impact(.medium)
                        Task { await viewModel.requestPermissionAndScan() }
                    },
                    onOpenSettings: {
                        DesignTokens.Haptics.impact(.light)
                        openAppSettings()
                    }
                )
            }
        }
        .onAppear {
            viewModel.refreshAuthorizationAndScanIfNeeded()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                viewModel.refreshAuthorizationAndScanIfNeeded()
            }
        }
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

private struct PermissionOnboardingView: View {
    let status: PHAuthorizationStatus
    let onRequestPermission: () -> Void
    let onOpenSettings: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.xl) {
            Spacer()

            VStack(spacing: DesignTokens.Spacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(DesignTokens.Colors.secondarySurface)
                        .frame(width: 84, height: 84)
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(DesignTokens.Colors.cardBorder, lineWidth: 1)
                        )

                    Image(systemName: "photo.stack.fill")
                        .font(.system(size: 38, weight: .semibold))
                        .foregroundStyle(DesignTokens.Colors.accent)
                }

                VStack(spacing: DesignTokens.Spacing.xs) {
                    Text("TinyPress")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                    Text("100% On-Device Photo Compressor")
                        .font(DesignTokens.Typography.headline)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
            }
            .scaleEffect(appeared || reduceMotion ? 1.0 : 0.95)
            .opacity(appeared || reduceMotion ? 1.0 : 0)

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                FeatureRow(icon: "lock.shield.fill", title: "Zero Uploads", detail: "Compresses locally on Apple Silicon. No servers, no account.")
                Divider().overlay(DesignTokens.Colors.cardBorder)
                FeatureRow(icon: "sparkles", title: "Keeps HDR & EXIF", detail: "Retains dates, GPS, Favorites, Albums, and HDR Gain Maps.")
                Divider().overlay(DesignTokens.Colors.cardBorder)
                FeatureRow(icon: "arrow.up.arrow.down", title: "Sort by File Size", detail: "Find and shrink the biggest photos taking up iPhone storage.")
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
            .opacity(appeared || reduceMotion ? 1.0 : 0)

            Spacer()

            if status == .denied || status == .restricted {
                VStack(spacing: DesignTokens.Spacing.sm) {
                    Label("Photo Library access is currently disabled.", systemImage: "exclamationmark.triangle.fill")
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Colors.warning)
                    Button(action: onOpenSettings) {
                        Text("Open iOS Settings")
                            .font(DesignTokens.Typography.headline)
                            .frame(maxWidth: .infinity, minHeight: DesignTokens.TouchTarget.buttonHeight)
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                Button(action: onRequestPermission) {
                    Text("Allow Photo Library Access")
                        .font(DesignTokens.Typography.headline)
                        .frame(maxWidth: .infinity, minHeight: DesignTokens.TouchTarget.buttonHeight)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(DesignTokens.Spacing.xl)
        .background(DesignTokens.Colors.background.ignoresSafeArea())
        .onAppear {
            guard !appeared else { return }
            if reduceMotion {
                appeared = true
            } else {
                withAnimation(DesignTokens.Motion.gentleSpring) {
                    appeared = true
                }
            }
        }
    }
}

private struct FeatureRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.md) {
            Image(systemName: icon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(DesignTokens.Colors.accent)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(DesignTokens.Typography.headline)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Text(detail)
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
