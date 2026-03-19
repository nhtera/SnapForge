import SwiftUI

/// Compact dropdown for aspect ratio and size presets in the pre-record toolbar
struct RecordingAspectRatioMenu: View {
    @Bindable var toolbarState: RecordingToolbarState

    var body: some View {
        Menu {
            Section("Aspect Ratio") {
                ForEach(RecordingAspectRatio.allCases) { ratio in
                    Button {
                        toolbarState.aspectRatio = ratio
                        toolbarState.onAspectRatioChanged?(ratio)
                    } label: {
                        HStack {
                            Text(ratio.displayName)
                            if toolbarState.aspectRatio == ratio {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
            Divider()
            Section("Size Presets") {
                ForEach(RecordingSizePreset.allCases) { preset in
                    Button {
                        toolbarState.sizePreset = preset
                        if let size = preset.size {
                            toolbarState.onSizePresetSelected?(size)
                        }
                    } label: {
                        HStack {
                            Text(preset.displayName)
                            if toolbarState.sizePreset == preset {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "aspectratio")
                Text(toolbarState.aspectRatio.displayName)
                    .font(.system(size: 11))
            }
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}
