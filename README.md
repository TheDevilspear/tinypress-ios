# TinyPress

A 100% on-device, zero-limit iOS 17+ photo compressor built in Swift and SwiftUI. TinyPress shrinks large photos directly on your iPhone using Apple Silicon hardware encoding—never uploading a single byte, requiring no account, and keeping your Apple Photos library intact.

---

## How the Compression Engine Works

Unlike generic web compressors that strip metadata, flatten HDR highlights, and re-encode on remote servers, TinyPress runs a multi-stage native pipeline entirely inside your iPhone's memory via [`CompressionEngine.swift`](Sources/Services/CompressionEngine.swift) and [`PhotoLibraryService.swift`](Sources/Services/PhotoLibraryService.swift):

1. **Fast Library Indexing (`PhotoKit`):**
   TinyPress scans `PHAsset` entries and reads each photo's `PHAssetResource` `fileSize` property so it can sort your entire camera roll **largest-first** without decoding full-resolution images into RAM.
2. **Metadata & Orientation Extraction (`ImageIO`):**
   `CGImageSourceCopyPropertiesAtIndex` extracts the full original metadata dictionary (EXIF camera/lens settings, shutter speed, ISO, capture timestamp, GPS coordinates, and Apple MakerNote tags).
   `CIImage` decodes the pixels with `.applyOrientationProperty: true` and normalizes orientation tags (`kCGImagePropertyOrientation = 1` and `TIFF.Orientation = 1`) so Apple Photos never double-rotates portrait shots.
3. **HDR Gain Map Preservation (`CoreImage`):**
   Modern iPhones store an auxiliary luminance **HDR Gain Map** alongside the base SDR image (either legacy Apple `urn:com:apple:photo:2020:aux:hdrgainmap` or ISO 21496-1 Adaptive HDR). TinyPress extracts this gain map using `.auxiliaryHDRGainMap: true`, scales it proportionally if you downscale resolution, and re-attaches it via `CIImageRepresentationOption.hdrGainMapImage`.
4. **Hardware Media Engine Encoding (`CIContext`):**
   `CIContext` encodes the image in the wide-gamut **Display P3** color space directly on Apple Silicon hardware (`heifRepresentation` for HEIC or `jpegRepresentation` for JPEG) at your chosen quality (`40%–95%`) and resolution preset (`100%`, `80%`, `65%`, `50%`).
5. **Size-Regression Guardrail:**
   Before saving anything, TinyPress compares `compressedData.count` against the original file size. In Batch mode, any photo whose compressed output is not smaller than the original is automatically skipped so you never waste storage.
6. **Library-Safe Save & Native Deletion (`PHAssetCreationRequest`):**
   iOS sandboxing forbids third-party apps from overwriting photos in place. Instead, TinyPress writes a new asset carrying the original `creationDate`, `location`, `isFavorite` status, all user album memberships (`PHAssetCollectionChangeRequest`), and optional Live Photo `.pairedVideo` motion—then prompts iOS's native confirmation sheet to move the bulky original to **Recently Deleted**.

---

## HEIC vs. JPEG: Which Should You Choose?

| Feature | HEIC (Recommended) | JPEG |
|---|---|---|
| **Compression Tech** | Modern HEVC (H.265) intra-frame | Legacy 1992 8×8 DCT blocks |
| **File Size at Equal Quality** | **~40–50% smaller** than JPEG | Baseline (larger files) |
| **HDR Highlights (Gain Map)** | **Full support** (Apple & ISO HDR) | Supported, but less efficient |
| **Wide Color (Display P3)** | **Native 10-bit / P3 support** | Display P3 supported, 8-bit |
| **Live Photo Pairing** | **Native** | Supported |
| **Cross-Platform Sharing** | Best on Apple devices (iOS/macOS); Windows/Android may convert on share | **Universal** on every browser, app, and OS |

**Rule of thumb:** Keep **HEIC** selected for freeing up iPhone & iCloud storage while preserving HDR. Switch to **JPEG** only when preparing photos for older Windows PCs, legacy web forms, or apps that reject `.heic` files.

---

## Optimal Quality & Resolution Guide

| Quality Setting | Best Use Case | Visual Quality vs. Savings |
|---|---|---|
| **80% – 85%** *(Archival)* | Travel, portraits, prints, irreplaceable shots | Virtually indistinguishable from original on iPhone; typically **40–60% smaller** |
| **70% – 75%** *(Sweet Spot — Default `72%`)* | Everyday camera roll, food, pets, events | Crisp detail with no visible blocking; typically **60–80% smaller** |
| **55% – 65%** *(Max Space Saver)* | Screenshots, receipts, documents, quick snaps | Slight softening only when zoomed 200%+; typically **75–88% smaller** |
| **90% – 95%** *(Diminishing Returns)* | Rarely needed | Files can end up nearly as large as (or larger than) the original HEIC |

**Resolution Scale (`100%`, `80%`, `65%`, `50%`):**
- Keep **`100%`** (default) for photos you care about—HEIC quality at `70–75%` already shrinks 24 MP / 48 MP iPhone shots dramatically without throwing away pixels.
- Use **`80%`** or **`65%`** on 48 MP ProRAW/HEIC bursts or huge screenshots where you don't need poster-sized pixel dimensions.

---

## Frequently Asked Questions (FAQ)

### Does compressing reduce visual photo quality?
Yes—lossy compression (`HEIC` / `JPEG`) discards imperceptible high-frequency detail to shrink file size. At TinyPress's default **72% HEIC**, the difference is virtually invisible on an iPhone screen. Use the interactive **Before / After Split Slider** to inspect any photo side-by-side before saving.

### Why does TinyPress create a copy instead of shrinking the photo in place?
Apple's iOS security model does not allow third-party apps to overwrite an existing `PHAsset` file in place. Creating a compressed copy first is safer: you can verify the result and byte savings, and only then confirm deletion of the original.

### I deleted the original—why didn't my iPhone storage drop immediately?
When you confirm deletion, iOS moves the original photo into **Photos → Albums → Recently Deleted** (where Apple keeps it for 30 days as a safety net). Open **Apple Photos → Recently Deleted → Select → Delete All** to reclaim the gigabytes immediately.

### Why were some photos skipped during Batch Compression?
If a photo is already heavily compressed (for example, a small WhatsApp image or an already-optimized HEIC), re-encoding it at a higher quality can produce a larger file. TinyPress's size-regression guardrail skips those automatically.

### What happens to my Albums, Favorites, Dates, GPS, and Live Photos?
- **Dates, GPS & EXIF:** Copied to the new asset so it sits in the exact same chronological spot and map location in Apple Photos.
- **Favorites & User Albums:** Re-applied automatically inside the same `PHPhotoLibrary` transaction.
- **Live Photos:** Kept intact when **Keep Live Photo Video** is enabled in Settings (turn it off if you only want the still frame to save extra space).

---

## Project Architecture

```text
Sources/
├── App/          # @main SwiftUI app entry point (TinyPressApp.swift)
├── Models/       # Domain models, formatters, and UserDefaults lifetime stats
├── Services/     # CompressionEngine (CoreImage/ImageIO) & PhotoLibraryService (PhotoKit)
├── ViewModels/   # @Observable LibraryViewModel & InspectorViewModel
├── Theme/        # DesignTokens (adaptive surfaces, tabular numerals, springs, haptics)
└── Views/        # LibraryGridView, PhotoComparisonView, BatchCompressionSheet, Settings
```

---

## Building Unsigned `.ipa` via GitHub Actions

This repository includes [`.github/workflows/build-unsigned-ipa.yml`](.github/workflows/build-unsigned-ipa.yml), which uses **XcodeGen** ([`project.yml`](project.yml)) and `xcodebuild archive` on `macos-latest` (`CODE_SIGNING_ALLOWED=NO`) to package `TinyPress-unsigned.ipa` as a downloadable artifact.

To build locally on macOS:

```bash
brew install xcodegen
xcodegen generate
open TinyPress.xcodeproj
```

---

## Sideloading on iPhone (Free Apple ID via SideStore)

1. Download **`TinyPress-unsigned-ipa`** from the latest successful **Actions** run and unzip `TinyPress-unsigned.ipa` in the iOS **Files** app.
2. Install **LocalDevVPN** from the App Store and **SideStore** on your iPhone (via `iloader` over USB for initial setup).
3. Connect **LocalDevVPN** while on **Wi-Fi**, open **SideStore → My Apps → `+`**, and select `TinyPress-unsigned.ipa`.

### 7-Day Auto-Refresh Shortcut (No Computer Needed)

Free Apple ID certificates expire every 7 days. You can automate wireless refreshing in Apple's **Shortcuts** app:

1. Create a new Shortcut with these **5 actions** in order:
   - **Set VPN** → **Connect** → `LocalDevVPN`
   - **Wait** → `3 seconds`
   - **Refresh All Apps** *(from SideStore — tap the `>` arrow on the action and turn **Show When Run** **OFF** so it runs silently without waiting for you to tap Done)*
   - **Wait** → `35 seconds`
   - **Set VPN** → **Disconnect** → `LocalDevVPN`
2. Go to **Shortcuts → Automation → `+`** → choose **Time of Day** (e.g., daily at night) or **Charger → Is Connected** → set to **Run Immediately** → select your Shortcut.
