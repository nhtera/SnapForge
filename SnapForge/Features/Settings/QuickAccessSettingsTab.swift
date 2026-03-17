import SwiftUI

// MARK: - Quick Access Tab

struct QuickAccessSettingsTab: View {
    @AppStorage("showQuickAccess") private var showQuickAccess = true
    @AppStorage("quickAccessTimeout") private var quickAccessTimeout = 5.0
    @AppStorage("quickAccessAutoClose") private var autoClose = false
    @AppStorage("quickAccessCloseAfterDrag") private var closeAfterDrag = true

    var body: some View {
        Form {
            Section("Visibility") {
                Toggle("Show Quick Access overlay after capture", isOn: $showQuickAccess)
            }

            Section("Auto-close") {
                Toggle("Auto-close after delay", isOn: $autoClose)
                if autoClose {
                    HStack {
                        Text("Interval")
                        Slider(value: $quickAccessTimeout, in: 3...30, step: 1)
                        Text("\(Int(quickAccessTimeout))s")
                            .font(.system(.body, design: .monospaced))
                            .frame(width: 30)
                    }
                }
            }

            Section("Drag & Drop") {
                Toggle("Close after dragging", isOn: $closeAfterDrag)
                    .help("Hold ⌥ (Option) to keep the overlay open after dragging")
            }
        }
        .formStyle(.grouped)
    }
}
