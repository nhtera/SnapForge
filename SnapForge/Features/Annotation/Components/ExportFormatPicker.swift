import SwiftUI

/// Export format picker popover for the annotation editor.
struct ExportFormatPicker: View {
    @Binding var exportFormat: ImageExportFormat
    @Binding var exportQuality: CGFloat
    var onCopy: () -> Void
    var onSave: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("Export Format")
                .font(.headline)

            Picker("Format", selection: $exportFormat) {
                ForEach(ImageExportFormat.allCases) { fmt in
                    Text(fmt.rawValue).tag(fmt)
                }
            }
            .pickerStyle(.segmented)

            if exportFormat != .png {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Quality: \(Int(exportQuality * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: $exportQuality, in: 0.1...1.0, step: 0.05)
                }
            }

            HStack(spacing: 12) {
                Button("Copy") { onCopy() }
                Button("Save") { onSave() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 260)
    }
}
