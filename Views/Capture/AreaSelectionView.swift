import SwiftUI
import AppKit

struct AreaSelectionOverlay: View {
    let onAreaSelected: (CGRect) -> Void
    let onCancelled: () -> Void

    @State private var startPoint: CGPoint?
    @State private var currentPoint: CGPoint?
    @State private var isDragging = false

    var selectionRect: CGRect? {
        guard let start = startPoint, let current = currentPoint else { return nil }
        return CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()

            if let rect = selectionRect {
                Rectangle()
                    .fill(Color.clear)
                    .background(Color.white.opacity(0.05))
                    .border(Color.accentColor, width: 2)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)

                VStack {
                    Text("\(Int(rect.width)) x \(Int(rect.height))")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial)
                        .cornerRadius(4)
                }
                .position(x: rect.midX, y: rect.maxY + 20)
            }

        
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    if startPoint == nil {
                        startPoint = value.startLocation
                    }
                    currentPoint = value.location
                    isDragging = true
                }
                .onEnded { value in
                    if let rect = selectionRect, rect.width > 10, rect.height > 10 {
                        onAreaSelected(rect)
                    } else {
                        startPoint = nil
                        currentPoint = nil
                        isDragging = false
                    }
                }
        )
    }
}

class AreaSelectionWindowController {
    private var windows: [OverlayWindow] = []
    private var escapeMonitor: Any?

    @MainActor
    func showOverlay(onSelected: @escaping (CGRect) -> Void, onCancelled: @escaping () -> Void) {
        closeOverlay()

        // Install escape key monitor
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Escape
                onCancelled()
                self?.closeOverlay()
                return nil
            }
            return event
        }

        for screen in NSScreen.screens {
            let window = OverlayWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.level = .screenSaver
            window.isOpaque = false
            window.backgroundColor = .clear
            window.ignoresMouseEvents = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.isReleasedWhenClosed = false
            window.acceptsMouseMovedEvents = true

            let hostingView = NSHostingView(rootView:
                AreaSelectionOverlay(
                    onAreaSelected: { [weak self] rect in
                        let screenRect = self?.convertToScreenCoordinates(rect, in: screen) ?? rect
                        onSelected(screenRect)
                        self?.closeOverlay()
                    },
                    onCancelled: { [weak self] in
                        onCancelled()
                        self?.closeOverlay()
                    }
                )
            )
            window.contentView = hostingView
            window.makeKeyAndOrderFront(nil)
            windows.append(window)
        }

        // Push crosshair cursor
        NSCursor.crosshair.push()

        // Ensure we become the active app so key events are received
        NSApp.activate(ignoringOtherApps: true)
    }

    func closeOverlay() {
        // Remove escape monitor
        if let monitor = escapeMonitor {
            NSEvent.removeMonitor(monitor)
            escapeMonitor = nil
        }

        // Pop crosshair cursor
        NSCursor.pop()

        for window in windows {
            window.close()
        }
        windows.removeAll()
    }

    private func convertToScreenCoordinates(_ rect: CGRect, in screen: NSScreen) -> CGRect {
        let screenFrame = screen.frame
        return CGRect(
            x: screenFrame.origin.x + rect.origin.x,
            y: screenFrame.origin.y + rect.origin.y,
            width: rect.width,
            height: rect.height
        )
    }
}

class OverlayWindow: NSWindow {
    private var cursorTrackingArea: NSTrackingArea?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func makeKeyAndOrderFront(_ sender: Any?) {
        super.makeKeyAndOrderFront(sender)
        setupCursorTracking()
        NSCursor.crosshair.set()
    }

    private func setupCursorTracking() {
        guard let view = contentView else { return }

        if let existing = cursorTrackingArea {
            view.removeTrackingArea(existing)
        }

        let area = NSTrackingArea(
            rect: view.bounds,
            options: [.cursorUpdate, .activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
            owner: self,
            userInfo: nil
        )
        view.addTrackingArea(area)
        cursorTrackingArea = area
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.crosshair.set()
    }

    override func mouseMoved(with event: NSEvent) {
        NSCursor.crosshair.set()
        super.mouseMoved(with: event)
    }

    override func mouseEntered(with event: NSEvent) {
        NSCursor.crosshair.set()
        super.mouseEntered(with: event)
    }
}
