import SwiftUI
import AppKit

struct AnnotationCanvasView: View {
    let image: NSImage
    @Binding var annotationState: AnnotationState
    @State private var currentItem: AnnotationItem?
    @State private var imageSize: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            let displaySize = calculateDisplaySize(for: image.size, in: geometry.size)
            let offset = CGSize(
                width: (geometry.size.width - displaySize.width) / 2,
                height: (geometry.size.height - displaySize.height) / 2
            )

            ZStack {
                Color(nsColor: .windowBackgroundColor)

                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: displaySize.width, height: displaySize.height)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)

                Canvas { context, size in
                    let allItems = annotationState.items + (currentItem.map { [$0] } ?? [])

                    for item in allItems {
                        drawAnnotation(item, in: &context)
                    }
                }
                .frame(width: displaySize.width, height: displaySize.height)
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { value in
                            let localPoint = CGPoint(
                                x: value.location.x - offset.width,
                                y: value.location.y - offset.height
                            )

                            if currentItem == nil {
                                var item = AnnotationItem(
                                    tool: annotationState.currentTool,
                                    color: annotationState.currentColor,
                                    lineWidth: annotationState.currentLineWidth
                                )
                                let startLocal = CGPoint(
                                    x: value.startLocation.x - offset.width,
                                    y: value.startLocation.y - offset.height
                                )
                                item.startPoint = startLocal
                                item.points = [startLocal]
                                currentItem = item
                            }

                            switch annotationState.currentTool {
                            case .pen, .highlighter:
                                currentItem?.points.append(localPoint)
                            case .arrow, .line, .rectangle, .ellipse:
                                currentItem?.endPoint = localPoint
                            case .text:
                                currentItem?.endPoint = localPoint
                            }
                        }
                        .onEnded { _ in
                            if var item = currentItem {
                                if item.tool == .text {
                                    item.text = annotationState.currentText.isEmpty ? "Text" : annotationState.currentText
                                }
                                annotationState.items.append(item)
                                annotationState.undoneItems.removeAll()
                            }
                            currentItem = nil
                        }
                )
            }
            .onAppear {
                imageSize = displaySize
            }
        }
    }

    private func calculateDisplaySize(for imageSize: CGSize, in containerSize: CGSize) -> CGSize {
        let widthRatio = containerSize.width / imageSize.width
        let heightRatio = containerSize.height / imageSize.height
        let scale = min(widthRatio, heightRatio, 1.0)
        return CGSize(
            width: imageSize.width * scale,
            height: imageSize.height * scale
        )
    }

    private func drawAnnotation(_ item: AnnotationItem, in context: inout GraphicsContext) {
        switch item.tool {
        case .pen, .highlighter:
            guard item.points.count >= 2 else { return }
            var path = Path()
            path.move(to: item.points[0])
            for point in item.points.dropFirst() {
                path.addLine(to: point)
            }
            context.stroke(
                path,
                with: .color(item.color.opacity(item.opacity)),
                lineWidth: item.tool == .highlighter ? item.lineWidth * 4 : item.lineWidth
            )

        case .line:
            guard let start = item.startPoint, let end = item.endPoint else { return }
            var path = Path()
            path.move(to: start)
            path.addLine(to: end)
            context.stroke(path, with: .color(item.color), lineWidth: item.lineWidth)

        case .arrow:
            guard let start = item.startPoint, let end = item.endPoint else { return }
            var path = Path()
            path.move(to: start)
            path.addLine(to: end)

            let angle = atan2(end.y - start.y, end.x - start.x)
            let arrowLength: CGFloat = 15
            let arrowAngle: CGFloat = .pi / 6

            let arrowPoint1 = CGPoint(
                x: end.x - arrowLength * cos(angle - arrowAngle),
                y: end.y - arrowLength * sin(angle - arrowAngle)
            )
            let arrowPoint2 = CGPoint(
                x: end.x - arrowLength * cos(angle + arrowAngle),
                y: end.y - arrowLength * sin(angle + arrowAngle)
            )

            path.move(to: end)
            path.addLine(to: arrowPoint1)
            path.move(to: end)
            path.addLine(to: arrowPoint2)

            context.stroke(path, with: .color(item.color), lineWidth: item.lineWidth)

        case .rectangle:
            guard let start = item.startPoint, let end = item.endPoint else { return }
            let rect = CGRect(
                x: min(start.x, end.x),
                y: min(start.y, end.y),
                width: abs(end.x - start.x),
                height: abs(end.y - start.y)
            )
            context.stroke(Path(rect), with: .color(item.color), lineWidth: item.lineWidth)

        case .ellipse:
            guard let start = item.startPoint, let end = item.endPoint else { return }
            let rect = CGRect(
                x: min(start.x, end.x),
                y: min(start.y, end.y),
                width: abs(end.x - start.x),
                height: abs(end.y - start.y)
            )
            context.stroke(Path(ellipseIn: rect), with: .color(item.color), lineWidth: item.lineWidth)

        case .text:
            guard let start = item.startPoint, let text = item.text, !text.isEmpty else { return }
            let resolvedText = context.resolve(Text(text).font(.system(size: 18, weight: .medium)).foregroundColor(item.color))
            context.draw(resolvedText, at: start, anchor: .topLeading)
        }
    }

    func renderAnnotatedImage() -> NSImage {
        let size = image.size
        let result = NSImage(size: size)

        result.lockFocus()

        image.draw(in: NSRect(origin: .zero, size: size))

        let context = NSGraphicsContext.current!.cgContext

        for item in annotationState.items {
            context.setStrokeColor(NSColor(item.color).withAlphaComponent(item.opacity).cgColor)
            context.setLineWidth(item.lineWidth)
            context.setLineCap(.round)
            context.setLineJoin(.round)

            switch item.tool {
            case .pen, .highlighter:
                guard item.points.count >= 2 else { continue }
                let lw = item.tool == .highlighter ? item.lineWidth * 4 : item.lineWidth
                context.setLineWidth(lw)
                let scaleX = size.width / imageSize.width
                let scaleY = size.height / imageSize.height
                context.move(to: CGPoint(x: item.points[0].x * scaleX, y: size.height - item.points[0].y * scaleY))
                for point in item.points.dropFirst() {
                    context.addLine(to: CGPoint(x: point.x * scaleX, y: size.height - point.y * scaleY))
                }
                context.strokePath()

            case .line:
                guard let start = item.startPoint, let end = item.endPoint else { continue }
                let scaleX = size.width / imageSize.width
                let scaleY = size.height / imageSize.height
                context.move(to: CGPoint(x: start.x * scaleX, y: size.height - start.y * scaleY))
                context.addLine(to: CGPoint(x: end.x * scaleX, y: size.height - end.y * scaleY))
                context.strokePath()

            case .arrow:
                guard let start = item.startPoint, let end = item.endPoint else { continue }
                let scaleX = size.width / imageSize.width
                let scaleY = size.height / imageSize.height
                let s = CGPoint(x: start.x * scaleX, y: size.height - start.y * scaleY)
                let e = CGPoint(x: end.x * scaleX, y: size.height - end.y * scaleY)

                context.move(to: s)
                context.addLine(to: e)
                context.strokePath()

                let angle = atan2(e.y - s.y, e.x - s.x)
                let arrowLength: CGFloat = 15 * max(scaleX, scaleY)
                let arrowAngle: CGFloat = .pi / 6

                context.move(to: e)
                context.addLine(to: CGPoint(
                    x: e.x - arrowLength * cos(angle - arrowAngle),
                    y: e.y - arrowLength * sin(angle - arrowAngle)
                ))
                context.move(to: e)
                context.addLine(to: CGPoint(
                    x: e.x - arrowLength * cos(angle + arrowAngle),
                    y: e.y - arrowLength * sin(angle + arrowAngle)
                ))
                context.strokePath()

            case .rectangle:
                guard let start = item.startPoint, let end = item.endPoint else { continue }
                let scaleX = size.width / imageSize.width
                let scaleY = size.height / imageSize.height
                let rect = CGRect(
                    x: min(start.x, end.x) * scaleX,
                    y: size.height - max(start.y, end.y) * scaleY,
                    width: abs(end.x - start.x) * scaleX,
                    height: abs(end.y - start.y) * scaleY
                )
                context.stroke(rect)

            case .ellipse:
                guard let start = item.startPoint, let end = item.endPoint else { continue }
                let scaleX = size.width / imageSize.width
                let scaleY = size.height / imageSize.height
                let rect = CGRect(
                    x: min(start.x, end.x) * scaleX,
                    y: size.height - max(start.y, end.y) * scaleY,
                    width: abs(end.x - start.x) * scaleX,
                    height: abs(end.y - start.y) * scaleY
                )
                context.strokeEllipse(in: rect)

            case .text:
                guard let start = item.startPoint, let text = item.text else { continue }
                let scaleX = size.width / imageSize.width
                let scaleY = size.height / imageSize.height
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 18 * max(scaleX, scaleY), weight: .medium),
                    .foregroundColor: NSColor(item.color)
                ]
                let string = NSAttributedString(string: text, attributes: attrs)
                string.draw(at: NSPoint(x: start.x * scaleX, y: size.height - start.y * scaleY - 20))
            }
        }

        result.unlockFocus()
        return result
    }
}
