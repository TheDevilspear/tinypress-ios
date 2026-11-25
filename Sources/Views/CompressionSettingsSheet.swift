import SwiftUI
import UIKit

struct CompressionSettingsSheet: View {
    @Binding var settings: CompressionSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Output Format") {
                    Picker("Format", selection: $settings.format) {
                        ForEach(OutputFormat.allCases) { format in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(format.displayName)
                                    .font(DesignTokens.Typography.body)
                                Text(format.subtitle)
                                    .font(DesignTokens.Typography.caption)
                                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                            }
                            .tag(format)
                        }
                    }
                    .pickerStyle(.inline)
                    .onChange(of: settings.format) { _, _ in
                        DesignTokens.Haptics.impact(.light)
                    }
                }

                Section("Quality & Resolution") {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Compression Quality")
                            Spacer()
                            Text("\(Int((settings.quality * 100).rounded()))%")
                                .font(DesignTokens.Typography.monoMetric)
                                .contentTransition(.numericText())
                        }
                        Slider(value: $settings.quality, in: 0.40...0.95, step: 0.05)
                            .onChange(of: settings.quality) { _, _ in
                                DesignTokens.Haptics.impact(.soft)
                            }
                    }

                    Picker("Resolution Scale", selection: $settings.dimensionPreset) {
                        ForEach(DimensionPreset.allCases) { preset in
                            Text(preset.displayName).tag(preset)
                        }
                    }
                    .onChange(of: settings.dimensionPreset) { _, _ in
                        DesignTokens.Haptics.impact(.light)
                    }
                }

                Section("Preservation") {
                    Toggle("Preserve HDR Gain Map", isOn: $settings.preserveHDRGainMap)
                    Toggle("Preserve EXIF, Date, GPS & Albums", isOn: $settings.preserveMetadata)
                    Toggle("Keep Live Photo Video", isOn: $settings.preserveLivePhotoMotion)
                }
            }
            .navigationTitle("Compression Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        DesignTokens.Haptics.impact(.light)
                        dismiss()
                    } label: {
                        Text("Done")
                            .fontWeight(.semibold)
                            .frame(minWidth: DesignTokens.TouchTarget.minimum, minHeight: DesignTokens.TouchTarget.minimum)
                    }
                }
            }
        }
    }
}
