# TinyPress

A 100% on-device, zero-limit iOS 17+ photo compressor built in Swift and SwiftUI. TinyPress shrinks large photos directly on your iPhone using Apple Silicon hardware encoding—never uploading a single byte, requiring no account, and keeping your Apple Photos library intact.

## Key Features

- **100% On-Device & Private:** Zero servers, zero analytics, zero accounts. All compression runs locally using `CoreImage` and `ImageIO`.
- **Hardware HEIC & JPEG Compression:** Uses `CIContext` (`heifRepresentation` / `jpegRepresentation`) to compress photos quickly with Apple's hardware Media Engine.
- **Preserves HDR Highlights:** Keeps both legacy Apple HDR Gain Maps and ISO 21496-1 Adaptive HDR Gain Maps (`auxiliaryHDRGainMap` / `hdrGainMapImage`), scaling them proportionally when resizing.
- **Preserves Metadata, Albums & Favorites:** Retains EXIF/TIFF/GPS tags, capture dates, Favorite status, and user album memberships, while normalizing orientation to prevent double-rotation.
- **Live Photo Support:** Optionally keeps the paired `.mov` motion resource when saving compressed copies.
- **Size-Sorted Library & Batch Mode:** Scans your library via `PHAssetResource` file sizes so you can target the biggest space-hogging photos first, with automatic size-regression guardrails that skip photos that won't shrink.
- **Interactive Before & After Slider:** Compare original vs. compressed quality and exact byte savings side-by-side before saving, then delete originals cleanly via iOS's native confirmation prompt.

## Architecture

```text
Sources/
├── App/          # @main SwiftUI app entry point (TinyPressApp.swift)
├── Models/       # Domain models, formatters, and UserDefaults lifetime stats
├── Services/     # CompressionEngine (CoreImage/ImageIO) & PhotoLibraryService (PhotoKit)
├── ViewModels/   # @Observable LibraryViewModel & InspectorViewModel
├── Theme/        # DesignTokens (adaptive surfaces, tabular numerals, springs, haptics)
└── Views/        # LibraryGridView, PhotoComparisonView, BatchCompressionSheet, Settings
```

## Building Unsigned `.ipa` via GitHub Actions

This repository includes [`.github/workflows/build-unsigned-ipa.yml`](.github/workflows/build-unsigned-ipa.yml), which uses **XcodeGen** (`project.yml`) and `xcodebuild archive` on `macos-latest` (`CODE_SIGNING_ALLOWED=NO`) to package `TinyPress-unsigned.ipa` as a downloadable artifact.

To build locally on macOS:

```bash
brew install xcodegen
xcodegen generate
open TinyPress.xcodeproj
```

## Sideloading on iPhone (Free Apple ID via SideStore)

1. Download **`TinyPress-unsigned-ipa`** from the latest successful **Actions** run and unzip `TinyPress-unsigned.ipa` in the iOS **Files** app.
2. Install **LocalDevVPN** from the App Store and **SideStore** on your iPhone (via `iloader` over USB for initial setup).
3. Connect **LocalDevVPN** while on **Wi-Fi**, open **SideStore → My Apps → `+`**, and select `TinyPress-unsigned.ipa`.

### 7-Day Auto-Refresh Shortcut (No Computer Needed)

Free Apple ID certificates expire every 7 days. You can automate wireless refreshing in Apple's **Shortcuts** app:

1. Create a new Shortcut with these actions in order:
   - **Set VPN** → **Connect** → `LocalDevVPN`
   - **Wait** → `3 seconds`
   - **Refresh All Apps** (from SideStore; expand the arrow and turn **Show When Run** OFF)
   - **Wait** → `35 seconds`
   - **Set VPN** → **Disconnect** → `LocalDevVPN`
2. Go to **Shortcuts → Automation → `+`** → choose **Time of Day** (e.g., daily at night) or **Charger (Is Connected)** → set to **Run Immediately** → select your Shortcut.
