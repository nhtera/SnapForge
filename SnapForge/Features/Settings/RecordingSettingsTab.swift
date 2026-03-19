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
    @AppStorage("recordingCountdownSeconds") private var countdownSeconds = 3
    @AppStorage("recordingTimerLimit") private var timerLimit = 0
    @AppStorage("autoOpenRecording") private var autoOpen = false
    @AppStorage("autoCopyRecording") private var autoCopy = false
    @AppStorage("regionSnappingEnabled") private var snapEnabled = true
    @AppStorage("recordingBorderStyle") private var borderStyle = "solid"

    // Click highlight settings
    @AppStorage("clickHighlightSize") private var clickSize: Double = 44
    @AppStorage("clickHighlightRippleCount") private var clickRipples = 1
    @AppStorage("clickHighlightOpacity") private var clickOpacity: Double = 0.7
    @AppStorage("clickHighlightAnimationDuration") private var clickDuration: Double = 0.5

    // Keystroke overlay settings
    @AppStorage("keystrokeFontSize") private var keystrokeFontSize: Double = 22
    @AppStorage("keystrokePosition") private var keystrokePosition = "bottomCenter"
    @AppStorage("keystrokeDisplayDuration") private var keystrokeDuration: Double = 1.5

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

                if highlightClicks && showCursor {
                    clickHighlightSettings
                }
            }

            Section("Keyboard") {
                Toggle("Show keystrokes", isOn: $showKeystrokes)

                if showKeystrokes {
                    keystrokeSettings
                }
            }

            Section("Recording Area") {
                Toggle("Dim screen while recording", isOn: $dimScreen)
                Toggle("Snap to window edges", isOn: $snapEnabled)

                Picker("Border Style", selection: $borderStyle) {
                    ForEach(RecordingBorderStyle.allCases) { style in
                        Text(style.displayName).tag(style.rawValue)
                    }
                }

                Picker("Countdown", selection: $countdownSeconds) {
                    Text("None").tag(0)
                    Text("3 seconds").tag(3)
                    Text("5 seconds").tag(5)
                    Text("10 seconds").tag(10)
                }

                Picker("Auto-stop after", selection: $timerLimit) {
                    Text("Off").tag(0)
                    Text("30 seconds").tag(30)
                    Text("1 minute").tag(60)
                    Text("5 minutes").tag(300)
                    Text("10 minutes").tag(600)
                }
            }

            Section("After Recording") {
                Toggle("Automatically open recording", isOn: $autoOpen)
                Toggle("Copy file to clipboard", isOn: $autoCopy)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Click Highlight Sub-Settings

    private var clickHighlightSettings: some View {
        Group {
            HStack {
                Text("Size")
                Slider(value: $clickSize, in: 20...100, step: 2)
                Text("\(Int(clickSize))px")
                    .font(.system(.body, design: .monospaced))
                    .frame(width: 48, alignment: .trailing)
            }
            Stepper("Ripple Count: \(clickRipples)", value: $clickRipples, in: 1...5)
            HStack {
                Text("Opacity")
                Slider(value: $clickOpacity, in: 0.2...1.0, step: 0.1)
                Text("\(Int(clickOpacity * 100))%")
                    .font(.system(.body, design: .monospaced))
                    .frame(width: 40, alignment: .trailing)
            }
            HStack {
                Text("Duration")
                Slider(value: $clickDuration, in: 0.3...2.0, step: 0.1)
                Text("\(String(format: "%.1f", clickDuration))s")
                    .font(.system(.body, design: .monospaced))
                    .frame(width: 36, alignment: .trailing)
            }
        }
    }

    // MARK: - Keystroke Overlay Sub-Settings

    private var keystrokeSettings: some View {
        Group {
            HStack {
                Text("Font Size")
                Slider(value: $keystrokeFontSize, in: 12...32, step: 2)
                Text("\(Int(keystrokeFontSize))pt")
                    .font(.system(.body, design: .monospaced))
                    .frame(width: 40, alignment: .trailing)
            }
            Picker("Position", selection: $keystrokePosition) {
                ForEach(KeystrokeOverlayPosition.allCases) { pos in
                    Text(pos.displayName).tag(pos.rawValue)
                }
            }
            HStack {
                Text("Display Duration")
                Slider(value: $keystrokeDuration, in: 0.5...3.0, step: 0.5)
                Text("\(String(format: "%.1f", keystrokeDuration))s")
                    .font(.system(.body, design: .monospaced))
                    .frame(width: 36, alignment: .trailing)
            }
        }
    }
}

struct RecordingVideoSubTab: View {
    @AppStorage(SettingsKey.recordingVideoFormat) private var videoFormat = "mov"
    @AppStorage(SettingsKey.recordingVideoQuality) private var videoQuality = "high"
    @AppStorage(SettingsKey.recordingFPS) private var recordingFPS = 30
    @AppStorage(SettingsKey.recordingCodec) private var recordingCodec = "h264"
    @AppStorage(SettingsKey.recordingResolution) private var recordingResolution = "retina"

    @State private var showAdvanced = false

    var body: some View {
        Form {
            Section("Format") {
                Picker("Video Format", selection: $videoFormat) {
                    Text("MOV — best quality").tag("mov")
                    Text("MP4 — wider compatibility").tag("mp4")
                }
            }

            Section("Quality") {
                Picker("Quality", selection: $videoQuality) {
                    Text("High").tag("high")
                    Text("Medium").tag("medium")
                    Text("Low").tag("low")
                }
            }

            Section("Frame Rate") {
                Picker("FPS", selection: $recordingFPS) {
                    Text("24 fps — cinematic").tag(24)
                    Text("30 fps — standard").tag(30)
                    Text("60 fps — smooth").tag(60)
                }
            }

            Section {
                DisclosureGroup("Advanced", isExpanded: $showAdvanced) {
                    Picker("Video Codec", selection: $recordingCodec) {
                        Text("H.264 — best compatibility").tag("h264")
                        Text("HEVC (H.265) — smaller files").tag("hevc")
                    }
                    Picker("Output Resolution", selection: $recordingResolution) {
                        Text("Retina (2x) — full quality").tag("retina")
                        Text("Standard (1x) — smaller files").tag("standard")
                    }
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
