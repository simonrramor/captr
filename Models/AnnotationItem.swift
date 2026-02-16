import Foundation
import SwiftUI

enum AnnotationTool: String, CaseIterable, Identifiable {
    case pen = "Pen"
    case arrow = "Arrow"
    case line = "Line"
    case rectangle = "Rectangle"
    case ellipse = "Ellipse"
    case text = "Text"
    case highlighter = "Highlighter"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .pen: return "pencil.tip"
        case .arrow: return "arrow.up.right"
        case .line: return "line.diagonal"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .text: return "textformat"
        case .highlighter: return "highlighter"
        }
    }
}

struct AnnotationItem: Identifiable {
    let id = UUID()
    let tool: AnnotationTool
    var points: [CGPoint]
    var color: Color
    var lineWidth: CGFloat
    var text: String?
    var startPoint: CGPoint?
    var endPoint: CGPoint?
    var opacity: Double

    init(tool: AnnotationTool, color: Color = .red, lineWidth: CGFloat = 3.0, opacity: Double = 1.0) {
        self.tool = tool
        self.points = []
        self.color = color
        self.lineWidth = lineWidth
        self.opacity = tool == .highlighter ? 0.3 : opacity
    }
}

struct AnnotationState {
    var items: [AnnotationItem] = []
    var undoneItems: [AnnotationItem] = []
    var currentTool: AnnotationTool = .pen
    var currentColor: Color = .red
    var currentLineWidth: CGFloat = 3.0
    var isAnnotating: Bool = false
    var currentText: String = ""

    mutating func undo() {
        guard let last = items.popLast() else { return }
        undoneItems.append(last)
    }

    mutating func redo() {
        guard let last = undoneItems.popLast() else { return }
        items.append(last)
    }

    mutating func clearAll() {
        undoneItems.append(contentsOf: items)
        items.removeAll()
    }

    var canUndo: Bool { !items.isEmpty }
    var canRedo: Bool { !undoneItems.isEmpty }
}
