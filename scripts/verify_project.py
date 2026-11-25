#!/usr/bin/env python3
"""Static verification for TinyPress iOS project on Linux."""

import json
import plistlib
import re
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

REQUIRED_FILES = [
    ".gitignore",
    "project.yml",
    ".github/workflows/build-unsigned-ipa.yml",
    "Resources/PrivacyInfo.xcprivacy",
    "Resources/Assets.xcassets/Contents.json",
    "Resources/Assets.xcassets/AccentColor.colorset/Contents.json",
    "Resources/Assets.xcassets/AppIcon.appiconset/Contents.json",
    "Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png",
    "Sources/App/TinyPressApp.swift",
    "Sources/Models/CompressionModels.swift",
    "Sources/Models/LifetimeStatsStore.swift",
    "Sources/Services/CompressionEngine.swift",
    "Sources/Services/PhotoLibraryService.swift",
    "Sources/ViewModels/LibraryViewModel.swift",
    "Sources/ViewModels/InspectorViewModel.swift",
    "Sources/Theme/DesignTokens.swift",
    "Sources/Views/AsyncAssetThumbnailView.swift",
    "Sources/Views/RootContentView.swift",
    "Sources/Views/LibraryGridView.swift",
    "Sources/Views/PhotoComparisonView.swift",
    "Sources/Views/BatchCompressionSheet.swift",
    "Sources/Views/CompressionSettingsSheet.swift",
]

FRAMEWORK_RULES = [
    (r"\b(PHAsset|PHPhotoLibrary|PHImageManager|PHCachingImageManager|PHAssetResource)\b", "Photos"),
    (r"\b(CLLocation)\b", "CoreLocation"),
    (r"\b(CGImageSource|CGImageDestination|kCGImageProperty)\b", "ImageIO"),
    (r"\b(CIContext|CIImage|CIImageOption|CIImageRepresentationOption)\b", "CoreImage"),
    (r"\b(UTType)\b", "UniformTypeIdentifiers"),
    (r"\b(UIImage|UIApplication|UIColor|UIImpactFeedbackGenerator|UINotificationFeedbackGenerator)\b", "UIKit"),
    (r"\b(@Observable|Observable)\b", "Observation"),
]

REQUIRED_TYPES = [
    "LibraryViewModel",
    "InspectorViewModel",
    "CompressionEngine",
    "PhotoLibraryService",
    "LifetimeStatsStore",
    "CompressionSettings",
    "PhotoItem",
    "CompressionPreviewResult",
    "BatchSummary",
    "DesignTokens",
]


def strip_comments_and_strings(src: str) -> str:
    out = []
    i = 0
    n = len(src)
    while i < n:
        ch = src[i]
        if ch == "/" and i + 1 < n and src[i + 1] == "/":
            i = src.find("\n", i)
            if i == -1:
                break
            out.append("\n")
            i += 1
        elif ch == "/" and i + 1 < n and src[i + 1] == "*":
            end = src.find("*/", i + 2)
            i = n if end == -1 else end + 2
        elif ch == '"':
            i += 1
            while i < n:
                if src[i] == "\\":
                    i += 2
                elif src[i] == '"':
                    i += 1
                    break
                else:
                    i += 1
            out.append('""')
        else:
            out.append(ch)
            i += 1
    return "".join(out)


def check_balanced(cleaned: str, path: Path) -> list[str]:
    errs = []
    pairs = {"{": "}", "(": ")", "[": "]"}
    closing = {v: k for k, v in pairs.items()}
    stack = []
    for ch in cleaned:
        if ch in pairs:
            stack.append(ch)
        elif ch in closing:
            if not stack or stack[-1] != closing[ch]:
                errs.append(f"{path}: unmatched closing '{ch}'")
                return errs
            stack.pop()
    if stack:
        errs.append(f"{path}: unclosed '{stack[-1]}'")
    return errs


def main() -> int:
    errors: list[str] = []

    # 1. Zero .md files
    md_files = list(ROOT.rglob("*.md"))
    if md_files:
        errors.append(f"Forbidden markdown files found: {md_files}")

    # 2. Required files
    for rel in REQUIRED_FILES:
        if not (ROOT / rel).exists():
            errors.append(f"Missing required file: {rel}")

    # 3. PrivacyInfo.xcprivacy
    privacy_path = ROOT / "Resources/PrivacyInfo.xcprivacy"
    if privacy_path.exists():
        try:
            plistlib.loads(privacy_path.read_bytes())
        except Exception as exc:
            errors.append(f"Invalid PrivacyInfo.xcprivacy plist: {exc}")

    # 4. Asset JSONs & AppIcon PNG
    for json_file in (ROOT / "Resources/Assets.xcassets").rglob("*.json"):
        try:
            json.loads(json_file.read_text(encoding="utf-8"))
        except Exception as exc:
            errors.append(f"Invalid JSON in {json_file}: {exc}")

    icon_path = ROOT / "Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
    if icon_path.exists():
        raw = icon_path.read_bytes()
        if not raw.startswith(b"\x89PNG\r\n\x1a\n") or raw[12:16] != b"IHDR":
            errors.append("AppIcon.png is not a valid PNG")
        else:
            w, h = struct.unpack(">II", raw[16:24])
            if (w, h) != (1024, 1024):
                errors.append(f"AppIcon.png dimensions {w}x{h} != 1024x1024")

    # 5. YAML sanity checks
    project_yml = (ROOT / "project.yml").read_text(encoding="utf-8")
    for token in ["TinyPress", 'SWIFT_VERSION: "5.0"', "NSPhotoLibraryUsageDescription", "GENERATE_INFOPLIST_FILE: YES"]:
        if token not in project_yml:
            errors.append(f"project.yml missing token: {token}")
    if "\t" in project_yml:
        errors.append("project.yml contains tab indentation")

    workflow_yml = (ROOT / ".github/workflows/build-unsigned-ipa.yml").read_text(encoding="utf-8")
    for token in ["macos-latest", "xcodegen", "CODE_SIGNING_ALLOWED=NO", "ditto -c -k", "upload-artifact@v4"]:
        if token not in workflow_yml:
            errors.append(f"build-unsigned-ipa.yml missing token: {token}")
    if "\t" in workflow_yml:
        errors.append("build-unsigned-ipa.yml contains tab indentation")

    # 6. Swift checks
    all_cleaned_swift = []
    swift_files = sorted((ROOT / "Sources").rglob("*.swift"))
    for swift_path in swift_files:
        raw_src = swift_path.read_text(encoding="utf-8")
        cleaned = strip_comments_and_strings(raw_src)
        all_cleaned_swift.append(cleaned)

        errors.extend(check_balanced(cleaned, swift_path.relative_to(ROOT)))

        imports = set(re.findall(r"^\s*import\s+([A-Za-z0-9_]+)", cleaned, re.MULTILINE))
        for pattern, fw in FRAMEWORK_RULES:
            if re.search(pattern, cleaned) and fw not in imports:
                errors.append(f"{swift_path.relative_to(ROOT)}: uses {fw} symbols without 'import {fw}'")

        if re.search(r"\btry\s+[^;\n]*\.(heifRepresentation|jpegRepresentation)\(", cleaned):
            errors.append(f"{swift_path.relative_to(ROOT)}: invalid 'try' on non-throwing CIContext representation method")

    combined = "\n".join(all_cleaned_swift)
    for type_name in REQUIRED_TYPES:
        matches = re.findall(rf"\b(?:struct|class|final class|actor|enum)\s+{type_name}\b", combined)
        if len(matches) != 1:
            errors.append(f"Expected 1 definition of {type_name}, found {len(matches)}")

    if errors:
        print("VERIFICATION FAILED:")
        for e in errors:
            print(" -", e)
        return 1

    print(f"VERIFICATION PASSED: {len(swift_files)} Swift files, assets, plist, YAML, and 0 .md files.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
