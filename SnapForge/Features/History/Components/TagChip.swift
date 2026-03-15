import SwiftUI

/// Small tag chip for tag-based filtering in History.
struct TagChip: View {
    let tag: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("#\(tag)")
                .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(
                    isSelected ? Color.accentColor.opacity(0.2) : Color(white: 0.2),
                    in: Capsule()
                )
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
        }
        .buttonStyle(.plain)
    }
}
