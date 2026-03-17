import SwiftUI

// MARK: - Screenshots Tab

struct ScreenshotsSettingsTab: View {
    @AppStorage("imageFormat") private var imageFormat = "png"
    @AppStorage("jpegQuality") private var jpegQuality = 0.9
    @AppStorage("showMagnifier") private var showMagnifier = true
    @AppStorage("showCrosshair") private var showCrosshair = true
    @AppStorage("showDimensions") private var showDimensions = true
    @AppStorage("captureWindowShadow") private var captureWindowShadow = true
    @AppStorage("timerDelay") private var timerDelay = 5
    @AppStorage("freezeScreen") private var freezeScreen = false

    var body: some View {
        Form {
            Section("Default Format") {
                Picker("Image Format", selection: $imageFormat) {
                    Text("PNG").tag("png")
                    Text("JPEG").tag("jpg")
                    Text("WebP").tag("webp")
                    Text("HEIC").tag("heic")
                }
                .pickerStyle(.segmented)

                if imageFormat == "jpg" || imageFormat == "heic" || imageFormat == "webp" {
                    HStack {
                        Text("Quality")
                        Slider(value: $jpegQuality, in: 0.1...1.0, step: 0.05)
                        Text("\(Int(jpegQuality * 100))%")
                            .font(.system(.body, design: .monospaced))
                            .frame(width: 40)
                    }
                }
            }

            Section("Area Selection") {
                Toggle("Show magnifier", isOn: $showMagnifier)
                Toggle("Show crosshair", isOn: $showCrosshair)
                Toggle("Show dimensions", isOn: $showDimensions)
                Toggle("Freeze screen during capture", isOn: $freezeScreen)
                    .help("Takes a snapshot of the screen first so you can select an area from the frozen frame")
            }

            Section("Window Capture") {
                Toggle("Capture window shadow", isOn: $captureWindowShadow)
                    .help("Hold ⌥ (Option) while capturing to toggle shadow")
            }

            Section("Self-Timer") {
                Picker("Countdown delay", selection: $timerDelay) {
                    Text("3 seconds").tag(3)
                    Text("5 seconds").tag(5)
                    Text("10 seconds").tag(10)
                }
            }
        }
        .formStyle(.grouped)
    }
}
