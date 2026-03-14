import SwiftUI

/// Layers panel sidebar for the annotation editor.
/// Shows all annotations as reorderable layers with visibility and lock controls.
struct LayersPanelView: View {
  @ObservedObject var state: AnnotateState

  var body: some View {
    VStack(spacing: 0) {
      // Header
      HStack {
        Text("Layers")
          .font(.headline)
        Spacer()
        Text("\(state.annotations.count)")
          .font(.caption)
          .foregroundStyle(.secondary)
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .background(.quaternary, in: Capsule())
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 8)

      Divider()

      // Layer list (reversed so topmost layer appears first)
      if state.annotations.isEmpty {
        emptyState
      } else {
        layerList
      }
    }
    .frame(width: 220)
    .background(.ultraThinMaterial)
  }

  // MARK: - Empty State

  private var emptyState: some View {
    VStack(spacing: 8) {
      Image(systemName: "square.3.layers.3d.slash")
        .font(.system(size: 28))
        .foregroundStyle(.secondary)
      Text("No annotations")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding()
  }

  // MARK: - Layer List

  private var layerList: some View {
    List {
      // Show in reverse order (topmost annotation = first in list)
      ForEach(state.annotations.reversed()) { annotation in
        LayerRowView(
          annotation: annotation,
          isSelected: state.selectedAnnotationId == annotation.id,
          isHidden: state.hiddenAnnotationIds.contains(annotation.id),
          isLocked: state.lockedAnnotationIds.contains(annotation.id),
          onSelect: {
            state.selectedAnnotationId = annotation.id
          },
          onToggleVisibility: {
            state.toggleVisibility(id: annotation.id)
          },
          onToggleLock: {
            state.toggleLock(id: annotation.id)
          },
          onDelete: {
            state.saveState()
            state.annotations.removeAll { $0.id == annotation.id }
            if state.selectedAnnotationId == annotation.id {
              state.selectedAnnotationId = nil
            }
          }
        )
      }
      .onMove { source, destination in
        // Convert reversed indices back to real indices
        let count = state.annotations.count
        let realSource = IndexSet(source.map { count - 1 - $0 })
        let realDestination = count - destination
        state.moveAnnotation(from: realSource, to: realDestination)
      }
    }
    .listStyle(.sidebar)
    .scrollContentBackground(.hidden)
  }
}

// MARK: - Layer Row

struct LayerRowView: View {
  let annotation: AnnotationItem
  let isSelected: Bool
  let isHidden: Bool
  let isLocked: Bool
  let onSelect: () -> Void
  let onToggleVisibility: () -> Void
  let onToggleLock: () -> Void
  let onDelete: () -> Void

  @State private var isHovering = false

  var body: some View {
    HStack(spacing: 6) {
      // Visibility toggle
      Button(action: onToggleVisibility) {
        Image(systemName: isHidden ? "eye.slash" : "eye")
          .font(.system(size: 11))
          .foregroundStyle(isHidden ? .tertiary : .secondary)
      }
      .buttonStyle(.plain)
      .help(isHidden ? "Show" : "Hide")

      // Lock toggle
      Button(action: onToggleLock) {
        Image(systemName: isLocked ? "lock.fill" : "lock.open")
          .font(.system(size: 11))
          .foregroundStyle(isLocked ? .orange : .secondary)
      }
      .buttonStyle(.plain)
      .help(isLocked ? "Unlock" : "Lock")

      // Annotation type icon
      Image(systemName: annotation.type.icon)
        .font(.system(size: 12))
        .foregroundStyle(isHidden ? .tertiary : .primary)
        .frame(width: 16)

      // Annotation label
      Text(annotation.type.displayName)
        .font(.caption)
        .lineLimit(1)
        .foregroundStyle(isHidden ? .tertiary : .primary)

      Spacer()

      // Delete button (on hover)
      if isHovering {
        Button(action: onDelete) {
          Image(systemName: "trash")
            .font(.system(size: 10))
            .foregroundStyle(.red)
        }
        .buttonStyle(.plain)
        .help("Delete")
      }
    }
    .padding(.vertical, 4)
    .padding(.horizontal, 6)
    .background(
      RoundedRectangle(cornerRadius: 4)
        .fill(isSelected ? Color.accentColor.opacity(0.2) : .clear)
    )
    .contentShape(Rectangle())
    .onTapGesture(perform: onSelect)
    .onHover { hovering in
      isHovering = hovering
    }
  }
}
