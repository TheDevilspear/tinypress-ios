import Photos
import SwiftUI
import UIKit

struct AsyncAssetThumbnailView: View {
    let item: PhotoItem
    let targetSize: CGSize
    let loadThumbnail: (PHAsset, CGSize, @escaping (UIImage?, PHImageRequestID) -> Void) -> PHImageRequestID
    let cancelRequest: (PHImageRequestID) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var image: UIImage?
    @State private var requestID: PHImageRequestID = PHInvalidImageRequestID

    var body: some View {
        ZStack {
            DesignTokens.Colors.tertiarySurface
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            } else {
                ProgressView()
                    .controlSize(.small)
                    .tint(DesignTokens.Colors.textSecondary)
            }
        }
        .clipped()
        .onAppear {
            guard image == nil else { return }
            requestID = loadThumbnail(item.asset, targetSize) { fetched, _ in
                if let fetched {
                    if reduceMotion {
                        self.image = fetched
                    } else {
                        withAnimation(.easeOut(duration: 0.18)) {
                            self.image = fetched
                        }
                    }
                }
            }
        }
        .onDisappear {
            if requestID != PHInvalidImageRequestID {
                cancelRequest(requestID)
                requestID = PHInvalidImageRequestID
            }
        }
    }
}
