import Foundation
import AppKit
import UniformTypeIdentifiers

/// Handles exporting captured images to various formats.
final class ExportService {

    enum ExportError: Error, LocalizedError {
        case noImageData
        case writeFailed(String)
        case unsupportedFormat(String)

        var errorDescription: String? {
            switch self {
            case .noImageData: return "No image data available"
            case .writeFailed(let path): return "Failed to write to: \(path)"
            case .unsupportedFormat(let fmt): return "Unsupported format: \(fmt)"
            }
        }
    }

    // MARK: - Export Image

    func exportImage(_ image: NSImage, format: ImageExportFormat, quality: CGFloat = 0.9, to url: URL) throws {
        guard let tiffData = image.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData) else {
            throw ExportError.noImageData
        }

        let data: Data?

        switch format {
        case .png:
            data = bitmapRep.representation(using: .png, properties: [:])
        case .jpg:
            data = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: quality])
        case .heic:
            data = bitmapRep.heicData(compressionQuality: quality)
        case .webp:
            // WebP requires CGImageDestination
            data = exportAsWebP(bitmapRep: bitmapRep, quality: quality)
        }

        guard let imageData = data else {
            throw ExportError.noImageData
        }

        do {
            try imageData.write(to: url)
        } catch {
            throw ExportError.writeFailed(url.path)
        }
    }

    // MARK: - WebP Export

    private func exportAsWebP(bitmapRep: NSBitmapImageRep, quality: CGFloat) -> Data? {
        guard let cgImage = bitmapRep.cgImage else { return nil }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data as CFMutableData,
            UTType.webP.identifier as CFString,
            1,
            nil
        ) else { return nil }

        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality
        ]

        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)

        guard CGImageDestinationFinalize(destination) else { return nil }

        return data as Data
    }

    // MARK: - Render Annotations onto Image

    func renderAnnotatedImage(
        baseImage: NSImage,
        annotations: [any AnnotationItem],
        canvasSize: CGSize,
        imageRect: CGRect
    ) -> NSImage? {
        let imageSize = baseImage.size
        let result = NSImage(size: imageSize)
        result.lockFocus()

        // Draw the base image
        baseImage.draw(in: NSRect(origin: .zero, size: imageSize))

        guard let context = NSGraphicsContext.current?.cgContext else {
            result.unlockFocus()
            return nil
        }

        // Transform: canvas coordinates → image coordinates
        let scaleX = imageSize.width / imageRect.width
        let scaleY = imageSize.height / imageRect.height

        // Render effects first (they modify the base image)
        for annotation in annotations {
            if let effect = annotation as? EffectAnnotation {
                renderEffect(effect, in: context, baseImage: baseImage, imageSize: imageSize, imageRect: imageRect, scaleX: scaleX, scaleY: scaleY)
            }
        }

        context.saveGState()
        // Flip coordinate system (NSImage draws bottom-up)
        context.translateBy(x: 0, y: imageSize.height)
        context.scaleBy(x: 1, y: -1)
        // Map from canvas rect to full image
        context.translateBy(x: -imageRect.origin.x * scaleX, y: -imageRect.origin.y * scaleY)
        context.scaleBy(x: scaleX, y: scaleY)

        for annotation in annotations {
            if !(annotation is EffectAnnotation) {
                renderAnnotation(annotation, in: context)
            }
        }

        context.restoreGState()
        result.unlockFocus()

        return result
    }

    private func renderEffect(
        _ effect: EffectAnnotation,
        in context: CGContext,
        baseImage: NSImage,
        imageSize: CGSize,
        imageRect: CGRect,
        scaleX: CGFloat,
        scaleY: CGFloat
    ) {
        // Convert canvas rect to image coordinates
        let imgX = (effect.rect.minX - imageRect.minX) * scaleX
        let imgY = (effect.rect.minY - imageRect.minY) * scaleY
        let imgW = effect.rect.width * scaleX
        let imgH = effect.rect.height * scaleY

        // Image coordinate region (bottom-up for NSImage)
        let imageRegion = CGRect(
            x: max(0, imgX),
            y: max(0, imageSize.height - imgY - imgH),
            width: min(imgW, imageSize.width),
            height: min(imgH, imageSize.height)
        )

        switch effect.type {
        case .pixelate:
            let pixelSize = max(6, 14 * effect.intensity)
            BlurEffectRenderer.drawPixelatedRegion(
                in: context,
                sourceImage: baseImage,
                region: imageRegion,
                pixelSize: pixelSize
            )
        case .blur:
            let radius = 20.0 * Double(effect.intensity)
            BlurEffectRenderer.drawGaussianRegion(
                in: context,
                sourceImage: baseImage,
                region: imageRegion,
                radius: radius
            )
        case .spotlight:
            // Dim everything except spotlight
            context.saveGState()
            let fullRect = CGRect(origin: .zero, size: imageSize)
            context.setFillColor(NSColor.black.withAlphaComponent(0.5).cgColor)
            context.fill(fullRect)
            context.setBlendMode(.clear)
            context.fill(imageRegion)
            context.setBlendMode(.normal)
            context.restoreGState()
        default:
            break
        }
    }

    private func renderAnnotation(_ annotation: any AnnotationItem, in context: CGContext) {
        if let shape = annotation as? ShapeAnnotation {
            renderShape(shape, in: context)
        } else if let arrow = annotation as? ArrowAnnotation {
            renderArrow(arrow, in: context)
        } else if let pencil = annotation as? PencilAnnotation {
            renderPencil(pencil, in: context)
        } else if let text = annotation as? TextAnnotation {
            renderText(text, in: context)
        } else if let counter = annotation as? CounterAnnotation {
            renderCounter(counter, in: context)
        }
    }

    private func renderShape(_ shape: ShapeAnnotation, in context: CGContext) {
        let color = NSColor(shape.color).cgColor
        context.setStrokeColor(color)
        context.setLineWidth(shape.strokeWidth)

        if shape.type == .ellipse {
            if shape.isFilled {
                context.setFillColor(color)
                context.fillEllipse(in: shape.rect)
            }
            context.strokeEllipse(in: shape.rect)
        } else {
            let path: CGPath
            if shape.cornerRadius > 0 {
                path = CGPath(roundedRect: shape.rect, cornerWidth: shape.cornerRadius, cornerHeight: shape.cornerRadius, transform: nil)
            } else {
                path = CGPath(rect: shape.rect, transform: nil)
            }
            if shape.isFilled {
                context.setFillColor(color)
                context.addPath(path)
                context.fillPath()
            }
            context.addPath(path)
            context.strokePath()
        }
    }

    private func renderArrow(_ arrow: ArrowAnnotation, in context: CGContext) {
        let color = NSColor(arrow.color).cgColor
        context.setStrokeColor(color)
        context.setLineWidth(arrow.strokeWidth)
        context.setLineCap(.round)

        context.move(to: arrow.startPoint)
        if arrow.isCurved, let cp = arrow.controlPoint {
            context.addQuadCurve(to: arrow.endPoint, control: cp)
        } else {
            context.addLine(to: arrow.endPoint)
        }
        context.strokePath()

        // Arrowhead
        if arrow.type == .arrow {
            let angle = atan2(arrow.endPoint.y - arrow.startPoint.y,
                            arrow.endPoint.x - arrow.startPoint.x)
            let headLength: CGFloat = max(arrow.strokeWidth * 4, 12)
            let headAngle: CGFloat = .pi / 6

            context.move(to: arrow.endPoint)
            context.addLine(to: CGPoint(
                x: arrow.endPoint.x - headLength * cos(angle - headAngle),
                y: arrow.endPoint.y - headLength * sin(angle - headAngle)
            ))
            context.move(to: arrow.endPoint)
            context.addLine(to: CGPoint(
                x: arrow.endPoint.x - headLength * cos(angle + headAngle),
                y: arrow.endPoint.y - headLength * sin(angle + headAngle)
            ))
            context.strokePath()
        }
    }

    private func renderPencil(_ pencil: PencilAnnotation, in context: CGContext) {
        guard pencil.points.count >= 2 else { return }
        let color = NSColor(pencil.color).cgColor
        context.setStrokeColor(color)
        context.setLineWidth(pencil.strokeWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        context.move(to: pencil.points[0])
        for point in pencil.points.dropFirst() {
            context.addLine(to: point)
        }
        context.strokePath()
    }

    private func renderText(_ text: TextAnnotation, in context: CGContext) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: text.font,
            .foregroundColor: NSColor(text.color)
        ]
        let nsString = text.text as NSString
        // Flip context for text rendering (text draws upside down in flipped context)
        context.saveGState()
        context.translateBy(x: text.position.x, y: text.position.y)
        context.scaleBy(x: 1, y: -1)
        nsString.draw(at: .zero, withAttributes: attributes)
        context.restoreGState()
    }

    private func renderCounter(_ counter: CounterAnnotation, in context: CGContext) {
        let radius = counter.size / 2
        let circleRect = CGRect(
            x: counter.position.x - radius,
            y: counter.position.y - radius,
            width: counter.size,
            height: counter.size
        )

        // Filled circle
        let color = NSColor(counter.color).cgColor
        context.setFillColor(color)
        context.fillEllipse(in: circleRect)

        // Number text
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: counter.size * 0.55),
            .foregroundColor: NSColor.white
        ]
        let text = "\(counter.number)" as NSString
        let textSize = text.size(withAttributes: attributes)

        context.saveGState()
        context.translateBy(x: counter.position.x - textSize.width / 2,
                          y: counter.position.y + textSize.height / 2)
        context.scaleBy(x: 1, y: -1)
        text.draw(at: .zero, withAttributes: attributes)
        context.restoreGState()
    }

    // MARK: - Filename

    func generateFilename(prefix: String = "SnapForge", format: ImageExportFormat) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())
        return "\(prefix)_\(timestamp).\(format.fileExtension)"
    }
}

// MARK: - NSBitmapImageRep HEIC Extension
extension NSBitmapImageRep {
    func heicData(compressionQuality: CGFloat = 0.9) -> Data? {
        guard let cgImage = self.cgImage else { return nil }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data as CFMutableData,
            "public.heic" as CFString,
            1,
            nil
        ) else { return nil }

        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: compressionQuality
        ]

        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }

        return data as Data
    }
}
