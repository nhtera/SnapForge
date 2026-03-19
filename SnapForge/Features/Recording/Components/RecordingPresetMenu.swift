import SwiftUI

/// Dropdown menu for recording presets — apply saved configurations with one click.
struct RecordingPresetMenu: View {
    @Bindable var state: RecordingToolbarState
    @State private var presets = RecordingPreset.loadAll()
    @State private var showSavePopover = false
    @State private var newPresetName = ""

    var body: some View {
        Menu {
            ForEach(presets) { preset in
                Button {
                    state.applyPreset(preset)
                } label: {
                    HStack {
                        Text(preset.name)
                        if preset.isBuiltIn {
                            Text("Built-in").foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Divider()

            Button("Save Current...") {
                newPresetName = ""
                showSavePopover = true
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "list.bullet.rectangle")
                    .font(.system(size: 12))
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .bold))
            }
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .popover(isPresented: $showSavePopover) {
            savePresetPopover
        }
        .accessibilityLabel("Recording presets")
    }

    private var savePresetPopover: some View {
        VStack(spacing: 12) {
            Text("Save Preset")
                .font(.system(size: 13, weight: .semibold))

            TextField("Preset name", text: $newPresetName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)

            HStack(spacing: 8) {
                Button("Cancel") { showSavePopover = false }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                Button("Save") {
                    guard !newPresetName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    let preset = RecordingPreset(name: newPresetName, from: state)
                    presets.append(preset)
                    RecordingPreset.saveUserPresets(presets)
                    showSavePopover = false
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(newPresetName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(16)
    }
}
