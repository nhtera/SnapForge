import SwiftUI

/// Small modal sheet for adding a tag to a capture in History.
struct TagInputSheet: View {
    var viewModel: HistoryViewModel
    @State private var tagText = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("Add Tag")
                .font(.headline)

            TextField("Enter tag name…", text: $tagText)
                .textFieldStyle(.roundedBorder)
                .onSubmit { submit() }

            HStack {
                Button("Cancel") { viewModel.showingTagInput = false }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Add") { submit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(tagText.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 300)
    }

    private func submit() {
        guard !tagText.isEmpty else { return }
        if let capture = viewModel.tagInputCapture {
            viewModel.addTag(tagText, to: capture)
        }
        viewModel.showingTagInput = false
    }
}
