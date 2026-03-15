import SwiftUI

/// Popover for browsing, applying, and saving annotation templates.
struct TemplatePopoverView: View {
  var state: AnnotateState
  @State private var templateService = TemplateService.shared
  @State private var showSaveSheet = false
  @State private var newTemplateName = ""
  @State private var newTemplateDescription = ""

  var body: some View {
    VStack(spacing: 0) {
      // Header
      HStack {
        Text("Templates")
          .font(.system(size: 13, weight: .semibold))
        Spacer()
        if !state.annotations.isEmpty {
          Button(action: { showSaveSheet = true }) {
            Label("Save Current", systemImage: "plus.circle")
              .font(.system(size: 11))
          }
          .buttonStyle(.plain)
          .foregroundStyle(Color.accentColor)
        }
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 10)

      Divider()

      // Template list
      if templateService.templates.isEmpty {
        VStack(spacing: 8) {
          Image(systemName: "doc.on.doc")
            .font(.title2)
            .foregroundStyle(.secondary)
          Text("No templates yet")
            .font(.caption)
            .foregroundStyle(.secondary)
          Text("Add annotations, then save as template")
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
        }
        .padding(20)
      } else {
        ScrollView {
          LazyVStack(spacing: 2) {
            ForEach(templateService.templates) { template in
              templateRow(template)
            }
          }
          .padding(6)
        }
      }
    }
    .frame(width: 260, height: 300)
    .sheet(isPresented: $showSaveSheet) {
      saveTemplateSheet
    }
  }

  // MARK: - Template Row

  private func templateRow(_ template: AnnotationTemplate) -> some View {
    HStack(spacing: 10) {
      // Icon
      ZStack {
        RoundedRectangle(cornerRadius: 6)
          .fill(template.isBuiltIn ? Color.orange.opacity(0.15) : Color.accentColor.opacity(0.15))
          .frame(width: 32, height: 32)
        Image(systemName: template.isBuiltIn ? "star.fill" : "doc.text")
          .font(.system(size: 13))
          .foregroundStyle(template.isBuiltIn ? Color.orange : Color.accentColor)
      }

      VStack(alignment: .leading, spacing: 2) {
        Text(template.name)
          .font(.system(size: 12, weight: .medium))
          .lineLimit(1)
        Text("\(template.items.count) annotation\(template.items.count == 1 ? "" : "s")")
          .font(.system(size: 10))
          .foregroundStyle(.secondary)
      }

      Spacer()

      // Apply button
      Button(action: { applyTemplate(template) }) {
        Text("Apply")
          .font(.system(size: 10, weight: .semibold))
          .padding(.horizontal, 8)
          .padding(.vertical, 3)
          .background(Color.accentColor.opacity(0.15), in: Capsule())
      }
      .buttonStyle(.plain)
      .foregroundStyle(Color.accentColor)

      // Delete button (only for user templates)
      if !template.isBuiltIn {
        Button(action: { deleteTemplate(template) }) {
          Image(systemName: "trash")
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
      }
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 6)
    .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 6))
  }

  // MARK: - Save Sheet

  private var saveTemplateSheet: some View {
    VStack(spacing: 16) {
      Text("Save as Template")
        .font(.headline)

      VStack(alignment: .leading, spacing: 6) {
        Text("Name")
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(.secondary)
        TextField("Template name", text: $newTemplateName)
          .textFieldStyle(.roundedBorder)
      }

      VStack(alignment: .leading, spacing: 6) {
        Text("Description (optional)")
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(.secondary)
        TextField("Brief description", text: $newTemplateDescription)
          .textFieldStyle(.roundedBorder)
      }

      Text("\(state.annotations.count) annotation\(state.annotations.count == 1 ? "" : "s") will be saved")
        .font(.system(size: 11))
        .foregroundStyle(.secondary)

      HStack {
        Button("Cancel") {
          showSaveSheet = false
          newTemplateName = ""
          newTemplateDescription = ""
        }
        .keyboardShortcut(.cancelAction)

        Button("Save") {
          saveTemplate()
        }
        .buttonStyle(.borderedProminent)
        .disabled(newTemplateName.trimmingCharacters(in: .whitespaces).isEmpty)
        .keyboardShortcut(.defaultAction)
      }
    }
    .padding(20)
    .frame(width: 300)
  }

  // MARK: - Actions

  private func applyTemplate(_ template: AnnotationTemplate) {
    let items = templateService.applyTemplate(template)
    state.saveState()
    state.annotations.append(contentsOf: items)
    state.bumpRevision()
    print("✅ Applied template: \(template.name) (\(items.count) annotations)")
  }

  private func saveTemplate() {
    let name = newTemplateName.trimmingCharacters(in: .whitespaces)
    guard !name.isEmpty else { return }

    do {
      try templateService.save(
        annotations: state.annotations,
        name: name,
        description: newTemplateDescription
      )
    } catch {
      print("❌ Template save failed: \(error)")
    }

    newTemplateName = ""
    newTemplateDescription = ""
    showSaveSheet = false
  }

  private func deleteTemplate(_ template: AnnotationTemplate) {
    do {
      try templateService.delete(id: template.id)
    } catch {
      print("❌ Template delete failed: \(error)")
    }
  }
}
