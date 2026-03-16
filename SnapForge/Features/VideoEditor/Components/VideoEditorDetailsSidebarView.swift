import SwiftUI

/// Left sidebar showing video file metadata and details.
struct VideoEditorDetailsSidebarView: View {
    @Bindable var state: VideoEditorState

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                // Header
                HStack {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.blue)
                    Text("Video Details")
                        .font(.system(size: 13, weight: .semibold))
                }

                Divider()

                // File Info
                VideoEditorSidebarSection(title: "File") {
                    VideoEditorDetailRow(label: "Name", value: state.filename)
                    VideoEditorDetailRow(
                        label: "Path",
                        value: state.videoURL.deletingLastPathComponent().path
                    )
                    VideoEditorDetailRow(label: "Size", value: state.fileSizeString)
                    VideoEditorDetailRow(
                        label: "Format",
                        value: state.fileExtension.uppercased()
                    )
                }

                // Video Info
                VideoEditorSidebarSection(title: "Video") {
                    VideoEditorDetailRow(label: "Resolution", value: state.resolutionString)
                    VideoEditorDetailRow(label: "Aspect Ratio", value: state.aspectRatioString)
                    VideoEditorDetailRow(label: "Duration", value: state.formattedDuration)
                }

                // Dates
                VideoEditorSidebarSection(title: "Dates") {
                    if let created = state.fileCreationDate {
                        VideoEditorDetailRow(
                            label: "Created",
                            value: created.formatted(date: .abbreviated, time: .shortened)
                        )
                    }
                    if let modified = state.fileModificationDate {
                        VideoEditorDetailRow(
                            label: "Modified",
                            value: modified.formatted(date: .abbreviated, time: .shortened)
                        )
                    }
                }

                Spacer(minLength: DesignTokens.Spacing.lg)
            }
            .padding(DesignTokens.Spacing.md)
        }
        .frame(maxHeight: .infinity)
    }
}
