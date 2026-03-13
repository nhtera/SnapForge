import SwiftUI

/// Annotation editor view — full canvas with tool palette for marking up captured images.
struct AnnotationView: View {
    let image: NSImage
    @State private var viewModel = AnnotationViewModel()
    @State private var currentDragStart: CGPoint?
    @State private var currentDragEnd: CGPoint?
    @State private var currentPencilPoints: [CGPoint] = []
    @State private var isEditing = false
    @State private var editingTextID: UUID?
    @State private var editingText: String = ""
    @State private var canvasSize: CGSize = .zero
    @State private var imageRect: CGRect = .zero

    var body: some View {
        HSplitView {
            // Canvas area
            GeometryReader { geo in
                ZStack {
                    Color(nsColor: .windowBackgroundColor)

                    // Image layer
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .background(GeometryReader { imgGeo in
                            Color.clear.onAppear {
                                canvasSize = geo.size
                                imageRect = calcImageRect(canvasSize: geo.size, imageSize: image.size)
                            }
                        })
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(20)

                    // Annotation canvas overlay
                    Canvas { context, size in
                        drawAnnotations(context: &context, size: size)
                        drawCurrentDrag(context: &context, size: size)
                    }
                    .allowsHitTesting(true)
                    .gesture(drawingGesture)
                    .onContinuousHover(coordinateSpace: .local) { phase in
                        if case .active(let point) = phase {
                            viewModel.cursorPosition = point
                        }
                    }

                    // Text editing overlay
                    if isEditing, let editID = editingTextID {
                        textEditingOverlay(for: editID)
                    }
                }
                .onChange(of: geo.size) { _, newSize in
                    canvasSize = newSize
                    imageRect = calcImageRect(canvasSize: newSize, imageSize: image.size)
                }
            }

            // Tool palette (right sidebar)
            ToolPaletteView(viewModel: viewModel)
                .frame(width: 220)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: { viewModel.undo() }) {
                    Image(systemName: "arrow.uturn.backward")
                }
                .disabled(!viewModel.canUndo)
                .help("Undo (⌘Z)")
                .keyboardShortcut("z", modifiers: .command)

                Button(action: { viewModel.redo() }) {
                    Image(systemName: "arrow.uturn.forward")
                }
                .disabled(!viewModel.canRedo)
                .help("Redo (⌘⇧Z)")
                .keyboardShortcut("z", modifiers: [.command, .shift])

                Button(action: { viewModel.clearAll() }) {
                    Image(systemName: "trash")
                }
                .disabled(viewModel.annotations.isEmpty)
                .help("Clear All")

                Divider()

                Button("Export") {
                    exportImage()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Image Rect Calculation

    private func calcImageRect(canvasSize: CGSize, imageSize: NSSize) -> CGRect {
        let padding: CGFloat = 20
        let availableWidth = canvasSize.width - padding * 2
        let availableHeight = canvasSize.height - padding * 2
        let imageAspect = imageSize.width / imageSize.height
        let availableAspect = availableWidth / availableHeight

        var displayWidth: CGFloat
        var displayHeight: CGFloat

        if imageAspect > availableAspect {
            displayWidth = availableWidth
            displayHeight = availableWidth / imageAspect
        } else {
            displayHeight = availableHeight
            displayWidth = availableHeight * imageAspect
        }

        let x = padding + (availableWidth - displayWidth) / 2
        let y = padding + (availableHeight - displayHeight) / 2
        return CGRect(x: x, y: y, width: displayWidth, height: displayHeight)
    }

    // MARK: - Drawing Gesture

    private var drawingGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                switch viewModel.selectedTool {
                case .pencil, .highlighter:
                    if currentPencilPoints.isEmpty {
                        currentPencilPoints.append(value.startLocation)
                    }
                    currentPencilPoints.append(value.location)
                case .text:
                    break // Text uses tap
                case .select:
                    break // Select uses tap
                default:
                    currentDragStart = value.startLocation
                    currentDragEnd = value.location
                }
            }
            .onEnded { value in
                finalizeAnnotation(start: value.startLocation, end: value.location)
            }
            .simultaneously(with: TapGesture().onEnded {
                handleTap()
            })
    }

    private func handleTap() {
        // If currently editing text, commit it first
        if isEditing, let editID = editingTextID {
            commitTextEditing(id: editID)
            return
        }

        let pos = viewModel.cursorPosition
        switch viewModel.selectedTool {
        case .text:
            viewModel.addAnnotation(TextAnnotation(
                position: pos,
                text: "",
                font: .systemFont(ofSize: 16),
                color: viewModel.selectedColor,
                backgroundColor: nil,
                style: .plain
            ))
            editingTextID = viewModel.annotations.last?.id
            editingText = ""
            isEditing = true
        case .counter:
            let num = viewModel.nextCounterNumber()
            viewModel.addAnnotation(CounterAnnotation(
                position: pos,
                number: num,
                color: viewModel.selectedColor,
                size: 28
            ))
        case .select:
            // Try to select an annotation at this position
            viewModel.selectAnnotation(at: pos)
        default:
            break
        }
    }

    private func finalizeAnnotation(start: CGPoint, end: CGPoint) {
        let rect = CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )

        switch viewModel.selectedTool {
        case .arrow:
            viewModel.addAnnotation(ArrowAnnotation(
                startPoint: start,
                endPoint: end,
                color: viewModel.selectedColor,
                strokeWidth: viewModel.strokeWidth,
                isCurved: false
            ))

        case .line:
            viewModel.addAnnotation(ArrowAnnotation(
                type: .line,
                startPoint: start,
                endPoint: end,
                color: viewModel.selectedColor,
                strokeWidth: viewModel.strokeWidth,
                isCurved: false
            ))

        case .rectangle:
            viewModel.addAnnotation(ShapeAnnotation(
                type: .rectangle,
                rect: rect,
                color: viewModel.selectedColor,
                strokeWidth: viewModel.strokeWidth,
                isFilled: false,
                cornerRadius: 0
            ))

        case .ellipse:
            viewModel.addAnnotation(ShapeAnnotation(
                type: .ellipse,
                rect: rect,
                color: viewModel.selectedColor,
                strokeWidth: viewModel.strokeWidth,
                isFilled: false,
                cornerRadius: 0
            ))

        case .pencil:
            guard currentPencilPoints.count > 2 else { break }
            viewModel.addAnnotation(PencilAnnotation(
                points: currentPencilPoints,
                color: viewModel.selectedColor,
                strokeWidth: viewModel.strokeWidth,
                isSmoothed: true
            ))

        case .highlighter:
            guard currentPencilPoints.count > 2 else { break }
            viewModel.addAnnotation(PencilAnnotation(
                type: .highlighter,
                points: currentPencilPoints,
                color: viewModel.selectedColor.opacity(0.3),
                strokeWidth: max(viewModel.strokeWidth * 3, 12),
                isSmoothed: false
            ))

        case .blur, .pixelate, .spotlight:
            viewModel.addAnnotation(EffectAnnotation(
                type: viewModel.selectedTool,
                rect: rect,
                intensity: viewModel.opacity
            ))

        case .crop:
            viewModel.cropRect = rect

        default:
            break
        }

        // Reset drag state
        currentDragStart = nil
        currentDragEnd = nil
        currentPencilPoints = []
    }

    // MARK: - Canvas Rendering

    private func drawAnnotations(context: inout GraphicsContext, size: CGSize) {
        for annotation in viewModel.annotations {
            drawAnnotation(annotation, context: &context)
        }
    }

    private func drawAnnotation(_ annotation: any AnnotationItem, context: inout GraphicsContext) {
        // Skip rendering text that is currently being edited (TextField is shown instead)
        if annotation.id == editingTextID && isEditing {
            return
        }

        if let shape = annotation as? ShapeAnnotation {
            drawShape(shape, context: &context)
        } else if let arrow = annotation as? ArrowAnnotation {
            drawArrow(arrow, context: &context)
        } else if let pencil = annotation as? PencilAnnotation {
            drawPencil(pencil, context: &context)
        } else if let text = annotation as? TextAnnotation {
            drawText(text, context: &context)
        } else if let effect = annotation as? EffectAnnotation {
            drawEffect(effect, context: &context)
        } else if let counter = annotation as? CounterAnnotation {
            drawCounter(counter, context: &context)
        }

        // Selection indicator
        if annotation.isSelected {
            drawSelectionHandles(for: annotation, context: &context)
        }
    }

    private func drawShape(_ shape: ShapeAnnotation, context: inout GraphicsContext) {
        let path: Path
        switch shape.type {
        case .ellipse:
            path = Path(ellipseIn: shape.rect)
        case .rectangle:
            if shape.cornerRadius > 0 {
                path = Path(roundedRect: shape.rect, cornerRadius: shape.cornerRadius)
            } else {
                path = Path(shape.rect)
            }
        default:
            path = Path(shape.rect)
        }

        if shape.isFilled {
            context.fill(path, with: .color(shape.color))
        }
        context.stroke(path, with: .color(shape.color), lineWidth: shape.strokeWidth)
    }

    private func drawArrow(_ arrow: ArrowAnnotation, context: inout GraphicsContext) {
        var path = Path()
        path.move(to: arrow.startPoint)

        if arrow.isCurved, let cp = arrow.controlPoint {
            path.addQuadCurve(to: arrow.endPoint, control: cp)
        } else {
            path.addLine(to: arrow.endPoint)
        }

        context.stroke(path, with: .color(arrow.color), lineWidth: arrow.strokeWidth)

        // Draw arrowhead (only for arrow type, not line)
        if arrow.type == .arrow {
            let angle = atan2(arrow.endPoint.y - arrow.startPoint.y,
                            arrow.endPoint.x - arrow.startPoint.x)
            let headLength: CGFloat = max(arrow.strokeWidth * 4, 12)
            let headAngle: CGFloat = .pi / 6

            var arrowHead = Path()
            arrowHead.move(to: arrow.endPoint)
            arrowHead.addLine(to: CGPoint(
                x: arrow.endPoint.x - headLength * cos(angle - headAngle),
                y: arrow.endPoint.y - headLength * sin(angle - headAngle)
            ))
            arrowHead.move(to: arrow.endPoint)
            arrowHead.addLine(to: CGPoint(
                x: arrow.endPoint.x - headLength * cos(angle + headAngle),
                y: arrow.endPoint.y - headLength * sin(angle + headAngle)
            ))

            context.stroke(arrowHead, with: .color(arrow.color),
                          style: StrokeStyle(lineWidth: arrow.strokeWidth, lineCap: .round))
        }
    }

    private func drawPencil(_ pencil: PencilAnnotation, context: inout GraphicsContext) {
        guard pencil.points.count >= 2 else { return }

        var path = Path()
        path.move(to: pencil.points[0])

        if pencil.isSmoothed && pencil.points.count > 2 {
            // Catmull-Rom spline interpolation for smooth curves
            for i in 1..<pencil.points.count {
                let p0 = pencil.points[max(0, i - 1)]
                let p1 = pencil.points[i]
                let cp = CGPoint(
                    x: (p0.x + p1.x) / 2,
                    y: (p0.y + p1.y) / 2
                )
                path.addQuadCurve(to: p1, control: cp)
            }
        } else {
            for point in pencil.points.dropFirst() {
                path.addLine(to: point)
            }
        }

        context.stroke(path, with: .color(pencil.color),
                      style: StrokeStyle(lineWidth: pencil.strokeWidth, lineCap: .round, lineJoin: .round))
    }

    private func drawText(_ text: TextAnnotation, context: inout GraphicsContext) {
        let resolvedText = context.resolve(
            Text(text.text)
                .font(.system(size: text.font.pointSize))
                .foregroundColor(text.color)
        )

        // Background for boxed/callout styles
        if text.style == .boxed || text.style == .callout {
            let textSize = resolvedText.measure(in: CGSize(width: 500, height: 200))
            let bgRect = CGRect(
                x: text.position.x - 6,
                y: text.position.y - 4,
                width: textSize.width + 12,
                height: textSize.height + 8
            )

            if text.style == .boxed {
                context.fill(Path(roundedRect: bgRect, cornerRadius: 4),
                           with: .color(text.backgroundColor ?? .white.opacity(0.9)))
                context.stroke(Path(roundedRect: bgRect, cornerRadius: 4),
                             with: .color(text.color), lineWidth: 1)
            } else if text.style == .callout {
                context.fill(Path(roundedRect: bgRect, cornerRadius: 8),
                           with: .color(text.color.opacity(0.15)))
            }
        }

        context.draw(resolvedText, at: text.position, anchor: .topLeading)
    }

    private func drawEffect(_ effect: EffectAnnotation, context: inout GraphicsContext) {
        switch effect.type {
        case .blur:
            // Isolate blur in its own layer so it doesn't leak to other annotations
            context.drawLayer { layerContext in
                // Draw a frosted-glass overlay to represent the blur region
                layerContext.clip(to: Path(effect.rect))
                layerContext.addFilter(.blur(radius: 8 * effect.intensity))
                layerContext.fill(Path(effect.rect), with: .color(.white.opacity(0.4)))
            }
            // Dashed border (outside the layer, so it's crisp)
            context.stroke(Path(effect.rect), with: .color(.blue.opacity(0.6)),
                          style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            // Label
            let label = context.resolve(
                Text("BLUR").font(.system(size: 10, weight: .bold)).foregroundColor(.blue.opacity(0.7))
            )
            context.draw(label, at: CGPoint(x: effect.rect.midX, y: effect.rect.minY - 10), anchor: .center)

        case .pixelate:
            // Isolate pixelate in its own layer
            context.drawLayer { layerContext in
                layerContext.clip(to: Path(effect.rect))
                // Mosaic grid pattern
                let gridSize: CGFloat = max(6, 14 * effect.intensity)
                for x in stride(from: effect.rect.minX, to: effect.rect.maxX, by: gridSize) {
                    for y in stride(from: effect.rect.minY, to: effect.rect.maxY, by: gridSize) {
                        let cellRect = CGRect(x: x, y: y, width: gridSize, height: gridSize)
                        let grayValue = Double.random(in: 0.3...0.7)
                        layerContext.fill(Path(cellRect), with: .color(.gray.opacity(grayValue)))
                    }
                }
            }
            // Dashed border
            context.stroke(Path(effect.rect), with: .color(.purple.opacity(0.6)),
                          style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            let label = context.resolve(
                Text("PIXELATE").font(.system(size: 10, weight: .bold)).foregroundColor(.purple.opacity(0.7))
            )
            context.draw(label, at: CGPoint(x: effect.rect.midX, y: effect.rect.minY - 10), anchor: .center)

        case .spotlight:
            // Isolate spotlight dimming in its own layer
            context.drawLayer { layerContext in
                // Draw dark overlay covering everything
                layerContext.fill(Path(CGRect(origin: .zero, size: canvasSize)),
                                with: .color(.black.opacity(0.5)))
                // Cut out the spotlight area
                layerContext.blendMode = .destinationOut
                layerContext.fill(Path(roundedRect: effect.rect, cornerRadius: 8),
                                with: .color(.white))
            }
            // Bright border around spotlight area
            context.stroke(Path(roundedRect: effect.rect, cornerRadius: 8),
                          with: .color(.yellow.opacity(0.6)), lineWidth: 2)

        default:
            break
        }
    }

    private func drawCounter(_ counter: CounterAnnotation, context: inout GraphicsContext) {
        let radius = counter.size / 2
        let circleRect = CGRect(
            x: counter.position.x - radius,
            y: counter.position.y - radius,
            width: counter.size,
            height: counter.size
        )

        // Filled circle
        context.fill(Path(ellipseIn: circleRect), with: .color(counter.color))

        // Number text
        let numberText = context.resolve(
            Text("\(counter.number)")
                .font(.system(size: counter.size * 0.55, weight: .bold))
                .foregroundColor(.white)
        )
        context.draw(numberText, at: counter.position, anchor: .center)
    }

    private func drawSelectionHandles(for annotation: any AnnotationItem, context: inout GraphicsContext) {
        let handleSize: CGFloat = 8
        var corners: [CGPoint] = []

        if let shape = annotation as? ShapeAnnotation {
            let r = shape.rect
            corners = [
                CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
                CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY)
            ]
        } else if let arrow = annotation as? ArrowAnnotation {
            corners = [arrow.startPoint, arrow.endPoint]
        }

        for corner in corners {
            let handleRect = CGRect(
                x: corner.x - handleSize / 2,
                y: corner.y - handleSize / 2,
                width: handleSize,
                height: handleSize
            )
            context.fill(Path(roundedRect: handleRect, cornerRadius: 2),
                        with: .color(.white))
            context.stroke(Path(roundedRect: handleRect, cornerRadius: 2),
                         with: .color(.accentColor), lineWidth: 1.5)
        }
    }

    // MARK: - Draw Current Drag Preview

    private func drawCurrentDrag(context: inout GraphicsContext, size: CGSize) {
        guard let start = currentDragStart, let end = currentDragEnd else {
            // Draw pencil preview
            if !currentPencilPoints.isEmpty {
                var path = Path()
                path.move(to: currentPencilPoints[0])
                for point in currentPencilPoints.dropFirst() {
                    path.addLine(to: point)
                }
                let isHighlighter = viewModel.selectedTool == .highlighter
                context.stroke(path,
                             with: .color(viewModel.selectedColor.opacity(isHighlighter ? 0.3 : 1.0)),
                             style: StrokeStyle(
                                lineWidth: isHighlighter ? max(viewModel.strokeWidth * 3, 12) : viewModel.strokeWidth,
                                lineCap: .round,
                                lineJoin: .round
                             ))
            }
            return
        }

        let rect = CGRect(
            x: min(start.x, end.x), y: min(start.y, end.y),
            width: abs(end.x - start.x), height: abs(end.y - start.y)
        )

        switch viewModel.selectedTool {
        case .rectangle:
            context.stroke(Path(rect), with: .color(viewModel.selectedColor.opacity(0.6)),
                          style: StrokeStyle(lineWidth: viewModel.strokeWidth, dash: [4, 4]))
        case .ellipse:
            context.stroke(Path(ellipseIn: rect), with: .color(viewModel.selectedColor.opacity(0.6)),
                          style: StrokeStyle(lineWidth: viewModel.strokeWidth, dash: [4, 4]))
        case .arrow, .line:
            var path = Path()
            path.move(to: start)
            path.addLine(to: end)
            context.stroke(path, with: .color(viewModel.selectedColor.opacity(0.6)),
                          lineWidth: viewModel.strokeWidth)
        case .blur, .pixelate, .spotlight, .crop:
            context.stroke(Path(rect), with: .color(.blue.opacity(0.5)),
                          style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
        default:
            break
        }
    }

    // MARK: - Text Editing

    private func textEditingOverlay(for id: UUID) -> some View {
        let textAnnotation = viewModel.annotations.first { $0.id == id } as? TextAnnotation
        let pos = textAnnotation?.position ?? .zero

        return ZStack {
            // Click-away backdrop to commit text
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    commitTextEditing(id: id)
                }

            TextField("Type here...", text: $editingText)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 16))
                .foregroundColor(Color(nsColor: NSColor(textAnnotation?.color ?? .red)))
                .frame(minWidth: 120, maxWidth: 300)
                .fixedSize()
                .position(x: pos.x + 60, y: pos.y + 10)
                .onSubmit {
                    commitTextEditing(id: id)
                }
                .onAppear {
                    // Focus the text field after a short delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        NSApp.keyWindow?.makeFirstResponder(nil)
                    }
                }
        }
    }

    private func commitTextEditing(id: UUID) {
        if editingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // Remove empty text annotations
            viewModel.removeAnnotation(id: id)
        } else {
            viewModel.updateText(id: id, newText: editingText)
        }
        isEditing = false
        editingTextID = nil
    }

    // MARK: - Export

    private func exportImage() {
        let exportService = ExportService()
        guard let rendered = exportService.renderAnnotatedImage(
            baseImage: image,
            annotations: viewModel.annotations,
            canvasSize: canvasSize,
            imageRect: imageRect
        ) else { return }

        // Save via StorageService
        let storage = StorageService()
        let filename = storage.generateImageFilename()
        if let savedURL = try? storage.saveImage(rendered, filename: filename) {
            print("✅ Exported annotated image: \(savedURL.path)")
            ClipboardService().copyImage(rendered)
        }
    }
}

// MARK: - Tool Palette

struct ToolPaletteView: View {
    @Bindable var viewModel: AnnotationViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Tool grid
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 8) {
                ForEach(AnnotationType.allCases) { tool in
                    ToolButton(
                        tool: tool,
                        isSelected: viewModel.selectedTool == tool
                    ) {
                        viewModel.selectedTool = tool
                    }
                }
            }
            .padding()

            Divider()

            // Tool settings
            VStack(alignment: .leading, spacing: 12) {
                // Color picker
                HStack {
                    Text("Color")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    ColorPicker("", selection: $viewModel.selectedColor)
                        .labelsHidden()
                }

                // Quick colors
                HStack(spacing: 6) {
                    ForEach([Color.red, .orange, .yellow, .green, .blue, .purple, .white, .black], id: \.self) { color in
                        Circle()
                            .fill(color)
                            .frame(width: 18, height: 18)
                            .overlay(Circle().stroke(.secondary.opacity(0.3), lineWidth: 1))
                            .overlay(
                                viewModel.selectedColor.description == color.description
                                    ? Circle().stroke(.primary, lineWidth: 2).padding(-2)
                                    : nil
                            )
                            .onTapGesture { viewModel.selectedColor = color }
                    }
                }

                // Stroke width
                VStack(alignment: .leading, spacing: 4) {
                    Text("Thickness: \(Int(viewModel.strokeWidth))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: $viewModel.strokeWidth, in: 1...20, step: 1)
                }

                // Opacity
                VStack(alignment: .leading, spacing: 4) {
                    Text("Opacity: \(Int(viewModel.opacity * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: $viewModel.opacity, in: 0.1...1.0, step: 0.1)
                }

                Divider()

                // Fill toggle (for shapes)
                if viewModel.selectedTool == .rectangle || viewModel.selectedTool == .ellipse {
                    Toggle("Fill Shape", isOn: $viewModel.fillShape)
                        .font(.caption)
                }
            }
            .padding()

            Spacer()

            // Bottom actions
            VStack(spacing: 8) {
                Button(action: { viewModel.clearAll() }) {
                    Label("Clear All", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding()
        }
        .background(.background)
    }
}

// MARK: - Tool Button

struct ToolButton: View {
    let tool: AnnotationType
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: tool.icon)
                    .font(.system(size: 18))
                Text(tool.rawValue)
                    .font(.system(size: 8))
            }
            .frame(width: 44, height: 44)
            .background(isSelected ? Color.accentColor.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .help(tool.rawValue)
    }
}
