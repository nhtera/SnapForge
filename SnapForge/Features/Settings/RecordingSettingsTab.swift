import SwiftUI

// MARK: - Recording Tab

struct RecordingSettingsTab: View {
    @State private var recordingSubTab = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $recordingSubTab) {
                Text("General").tag(0)
                Text("Video").tag(1)
                Text("GIF").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 40)
            .padding(.top, 12)

            switch recordingSubTab {
            case 0: RecordingGeneralSubTab()
            case 1: RecordingVideoSubTab()
            case 2: RecordingGIFSubTab()
            default: EmptyView()
            }
        }
    }
}

struct RecordingGeneralSubTab: View {
    @AppStorage("showRecordingControls") private var showControls = true
    @AppStorage("showRecordingTimer") private var showTimer = true
    @AppStorage("showCursorInRecording") private var showCursor = true
    @AppStorage("highlightClicks") private var highlightClicks = false
    @AppStorage("showKeystrokes") private var showKeystrokes = false
    @AppStorage("dimScreenWhileRecording") private var dimScreen = true
    @AppStorage("showRecordingCountdown") private var showCountdown = false

    var body: some View {
        Form {
            Section("Controls") {
                Toggle("Show controls while recording", isOn: $showControls)
                Toggle("Display recording time in menu bar", isOn: $showTimer)
            }

            Section("Cursor") {
                Toggle("Show cursor", isOn: $showCursor)
                Toggle("Highlight clicks", isOn: $highlightClicks)
                    .disabled(!showCursor)
            }

            Section("Keyboard") {
                Toggle("Show keystrokes", isOn: $showKeystrokes)
            }

            Section("Recording Area") {
                Toggle("Dim screen while recording", isOn: $dimScreen)
                Toggle("Show countdown before recording", isOn: $showCountdown)
            }
        }
        .formStyle(.grouped)
    }
}

struct RecordingVideoSubTab: View {
    @AppStorage("recordingFPS") private var recordingFPS = 30
    @AppStorage("recordingCodec") private var recordingCodec = "h264"
    @AppStorage("recordingResolution") private var recordingResolution = "retina"

    var body: some View {
        Form {
            Section("Frame Rate") {
                Picker("FPS", selection: $recordingFPS) {
                    Text("24 fps — cinematic").tag(24)
                    Text("30 fps — standard").tag(30)
                    Text("60 fps — smooth").tag(60)
                }
            }

            Section("Codec") {
                Picker("Video Codec", selection: $recordingCodec) {
                    Text("H.264 — best compatibility").tag("h264")
                    Text("HEVC (H.265) — smaller files").tag("hevc")
                }
            }

            Section("Resolution") {
                Picker("Output Resolution", selection: $recordingResolution) {
                    Text("Retina (2x) — full quality").tag("retina")
                    Text("Standard (1x) — smaller files").tag("standard")
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct RecordingGIFSubTab: View {
    @AppStorage("gifFPS") private var gifFPS = 15
    @AppStorage("gifMaxWidth") private var gifMaxWidth = 640
    @AppStorage("gifQuality") private var gifQuality = 0.8
    @AppStorage("gifLoopCount") private var gifLoopCount = 0

    var body: some View {
        Form {
            Section("Frame Rate") {
                Stepper("GIF FPS: \(gifFPS)", value: $gifFPS, in: 5...30, step: 5)
                Text("Higher FPS = smoother but larger files")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Dimensions") {
                Stepper("Max Width: \(gifMaxWidth)px", value: $gifMaxWidth, in: 320...1920, step: 160)
                Text("GIF will be scaled down if wider than this")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Quality") {
                HStack {
                    Text("Color Quality")
                    Slider(value: $gifQuality, in: 0.3...1.0, step: 0.1)
                    Text("\(Int(gifQuality * 100))%")
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 40)
                }
            }

            Section("Looping") {
                Picker("Loop Count", selection: $gifLoopCount) {
                    Text("Infinite").tag(0)
                    Text("1 time").tag(1)
                    Text("3 times").tag(3)
                    Text("5 times").tag(5)
                }
            }
        }
        .formStyle(.grouped)
    }
}
