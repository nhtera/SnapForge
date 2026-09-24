import SwiftUI

/// Renders audio waveform as mirrored bars over the timeline thumbnails.
struct AudioWaveformView: View {
    let amplitudes: [Float]
    var color: Color = .blue.opacity(0.25)

    var body: some View {
        Canvas { context, size in
            guard !amplitudes.isEmpty else { return }

            let count = amplitudes.count
            let barWidth = size.width / CGFloat(count)
            let midY = size.height / 2

            for (i, amplitude) in amplitudes.enumerated() {
                let halfHeight = CGFloat(amplitude) * midY
                let x = CGFloat(i) * barWidth
                let rect = CGRect(
                    x: x,
                    y: midY - halfHeight,
                    width: max(1, barWidth - 1),
                    height: halfHeight * 2
                )
                context.fill(Path(rect), with: .color(color))
            }
        }
    }
}
