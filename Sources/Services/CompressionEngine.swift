import Foundation
import CoreGraphics
import CoreImage
import ImageIO
import UIKit
import UniformTypeIdentifiers

enum CompressionEngineError: LocalizedError {
    case invalidSourceImage
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidSourceImage:
            return "Could not decode the original photo data."
        case .encodingFailed:
            return "Hardware encoder failed to create the compressed image."
        }
    }
}

actor CompressionEngine {
    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    private let displayP3 = CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()

    func generatePreview(
        sourceData: Data,
        originalBytes: Int64,
        isLivePhoto: Bool,
        settings: CompressionSettings
    ) throws -> CompressionPreviewResult {
        let compressed = try compressData(
            sourceData: sourceData,
            isLivePhoto: isLivePhoto,
            settings: settings
        )

        let originalUI = Self.makePreviewUIImage(from: sourceData, maxPixelSize: 1600)
        let compressedUI = Self.makePreviewUIImage(from: compressed.data, maxPixelSize: 1600)

        guard let originalUIImage = originalUI, let compressedUIImage = compressedUI else {
            throw CompressionEngineError.invalidSourceImage
        }

        return CompressionPreviewResult(
            originalBytes: originalBytes,
            compressedData: compressed.data,
            compressedBytes: Int64(compressed.data.count),
            originalUIImage: originalUIImage,
            compressedUIImage: compressedUIImage,
            preservedHDR: compressed.preservedHDR,
            preservedLivePhoto: isLivePhoto && settings.preserveLivePhotoMotion,
            outputWidth: compressed.outputWidth,
            outputHeight: compressed.outputHeight
        )
    }

    func compressForBatch(
        sourceData: Data,
        isLivePhoto: Bool,
        settings: CompressionSettings
    ) throws -> Data {
        try compressData(
            sourceData: sourceData,
            isLivePhoto: isLivePhoto,
            settings: settings
        ).data
    }

    private struct EncodedOutput {
        let data: Data
        let preservedHDR: Bool
        let outputWidth: Int
        let outputHeight: Int
    }

    private func compressData(
        sourceData: Data,
        isLivePhoto: Bool,
        settings: CompressionSettings
    ) throws -> EncodedOutput {
        guard let imageSource = CGImageSourceCreateWithData(
            sourceData as CFData,
            [kCGImageSourceShouldCache: false] as CFDictionary
        ) else {
            throw CompressionEngineError.invalidSourceImage
        }

        let originalProperties = (CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [String: Any]) ?? [:]

        guard let rawPrimary = CIImage(
            data: sourceData,
            options: [.applyOrientationProperty: true]
        ) else {
            throw CompressionEngineError.invalidSourceImage
        }

        let scale = settings.dimensionPreset.scaleFactor
        let scaledPrimary: CIImage
        if scale < 0.999 {
            scaledPrimary = rawPrimary
                .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                .cropped(to: CGRect(
                    x: rawPrimary.extent.origin.x * scale,
                    y: rawPrimary.extent.origin.y * scale,
                    width: max(1, (rawPrimary.extent.width * scale).rounded()),
                    height: max(1, (rawPrimary.extent.height * scale).rounded())
                ))
        } else {
            scaledPrimary = rawPrimary
        }

        let outputWidth = max(1, Int(scaledPrimary.extent.width.rounded()))
        let outputHeight = max(1, Int(scaledPrimary.extent.height.rounded()))

        var preservedGainMap: CIImage?
        if settings.preserveHDRGainMap {
            if let rawGainMap = CIImage(
                data: sourceData,
                options: [.auxiliaryHDRGainMap: true, .applyOrientationProperty: true]
            ) {
                if scale < 0.999 {
                    preservedGainMap = rawGainMap
                        .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                        .cropped(to: CGRect(
                            x: rawGainMap.extent.origin.x * scale,
                            y: rawGainMap.extent.origin.y * scale,
                            width: max(1, (rawGainMap.extent.width * scale).rounded()),
                            height: max(1, (rawGainMap.extent.height * scale).rounded())
                        ))
                } else {
                    preservedGainMap = rawGainMap
                }
            }
        }

        let sanitizedProperties = Self.buildOutputProperties(
            from: originalProperties,
            preserveMetadata: settings.preserveMetadata,
            isLivePhoto: isLivePhoto,
            preserveLivePhotoMotion: settings.preserveLivePhotoMotion,
            outputWidth: outputWidth,
            outputHeight: outputHeight
        )

        let preparedPrimary = scaledPrimary.settingProperties(sanitizedProperties)

        var repOptions: [CIImageRepresentationOption: Any] = [
            CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): settings.quality
        ]
        if let gainMap = preservedGainMap {
            repOptions[.hdrGainMapImage] = gainMap
        }

        let encodedData: Data?
        switch settings.format {
        case .heic:
            encodedData = ciContext.heifRepresentation(
                of: preparedPrimary,
                format: .RGBA8,
                colorSpace: displayP3,
                options: repOptions
            )
        case .jpeg:
            encodedData = ciContext.jpegRepresentation(
                of: preparedPrimary,
                colorSpace: displayP3,
                options: repOptions
            )
        }

        guard let data = encodedData, !data.isEmpty else {
            throw CompressionEngineError.encodingFailed
        }

        return EncodedOutput(
            data: data,
            preservedHDR: preservedGainMap != nil,
            outputWidth: outputWidth,
            outputHeight: outputHeight
        )
    }

    private static func buildOutputProperties(
        from original: [String: Any],
        preserveMetadata: Bool,
        isLivePhoto: Bool,
        preserveLivePhotoMotion: Bool,
        outputWidth: Int,
        outputHeight: Int
    ) -> [String: Any] {
        // Orientation is already baked into pixels via .applyOrientationProperty: true.
        // Force orientation = 1 so Apple Photos never double-rotates portrait shots.
        guard preserveMetadata else {
            return [
                kCGImagePropertyOrientation as String: 1
            ]
        }

        var merged = original
        merged[kCGImagePropertyOrientation as String] = 1

        if var tiff = merged[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
            tiff[kCGImagePropertyTIFFOrientation as String] = 1
            merged[kCGImagePropertyTIFFDictionary as String] = tiff
        }

        if var exif = merged[kCGImagePropertyExifDictionary as String] as? [String: Any] {
            exif[kCGImagePropertyExifPixelXDimension as String] = outputWidth
            exif[kCGImagePropertyExifPixelYDimension as String] = outputHeight
            merged[kCGImagePropertyExifDictionary as String] = exif
        }

        if isLivePhoto && !preserveLivePhotoMotion {
            if var makerApple = merged[kCGImagePropertyMakerAppleDictionary as String] as? [String: Any] {
                makerApple.removeValue(forKey: "17")
                merged[kCGImagePropertyMakerAppleDictionary as String] = makerApple
            }
        }

        return merged
    }

    private static func makePreviewUIImage(from data: Data, maxPixelSize: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return UIImage(data: data)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        if let cgThumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
            return UIImage(cgImage: cgThumb)
        }
        return UIImage(data: data)
    }
}
