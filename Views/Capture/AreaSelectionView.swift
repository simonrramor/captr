import SwiftUI
import AppKit

// MARK: - Native Area Selection View (handles mouse events directly)

class AreaSelectionNSView: NSView {
    var onAreaSelected: ((CGRect) -> Void)?
    var onCancelled: (() -> Void)?

    private var startPoint: CGPoint?
    private var currentPoint: CGPoint?
    private var isDragging = false
    private var selectionLayer = CAShapeLayer()
    private var dimensionLabel = CATextLayer()
    private var overlayLayer = CALayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        setupLayers()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        setupLayers()
    }

    private func setupLayers() {
        guard let layer = self.layer else { return }

        // Dark overlay covering everything
        overlayLayer.frame = bounds
        overlayLayer.backgroundColor = NSColor.black.withAlphaComponent(0.3).cgColor
        layer.addSublayer(overlayLayer)

        // Selection border
        selectionLayer.fillColor = NSColor.white.withAlphaComponent(0.05).cgColor
        selectionLayer.strokeColor = NSColor.controlAccentColor.cgColor
        selectionLayer.lineWidth = 2
        selectionLayer.isHidden = true
        layer.addSublayer(selectionLayer)

        // Dimension label
        dimensionLabel.fontSize = 12
        dimensionLabel.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
        dimensionLabel.foregroundColor = NSColor.white.cgColor
        dimensionLabel.backgroundColor = NSColor.black.withAlphaComponent(0.6).cgColor
        dimensionLabel.cornerRadius = 4
        dimensionLabel.alignmentMode = .center
        dimensionLabel.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
        dimensionLabel.isHidden = true
        layer.addSublayer(dimensionLabel)
    }

    override func layout() {
        super.layout()
        overlayLayer.frame = bounds
    }

    private var selectionRect: CGRect? {
        guard let start = startPoint, let current = currentPoint else { return nil }
        return CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        startPoint = point
        currentPoint = point
        isDragging = true
        selectionLayer.isHidden = false
        dimensionLabel.isHidden = false
        updateSelectionDisplay()
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        updateSelectionDisplay()
    }

    override func mouseUp(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        isDragging = false

        if let rect = selectionRect, rect.width > 10, rect.height > 10 {
            // Convert from flipped view coordinates to bottom-left origin for the callback
            onAreaSelected?(rect)
        } else {
            // Too small, reset
            startPoint = nil
            currentPoint = nil
            selectionLayer.isHidden = true
            dimensionLabel.isHidden = true
        }
    }

    private func updateSelectionDisplay() {
        guard let rect = selectionRect else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        // Update selection rectangle - use clear cutout approach
        // First update the overlay to have a hole
        let path = CGMutablePath()
        path.addRect(bounds)
        path.addRect(rect)

        let maskLayer = CAShapeLayer()
        maskLayer.path = path
        maskLayer.fillRule = .evenOdd
        overlayLayer.mask = maskLayer

        // Update selection border
        selectionLayer.path = CGPath(rect: rect, transform: nil)
        selectionLayer.isHidden = false

        // Update dimension label
        let labelText = "\(Int(rect.width)) x \(Int(rect.height))"
        dimensionLabel.string = labelText
        let labelWidth = CGFloat(labelText.count) * 8 + 16
        let labelHeight: CGFloat = 22
        dimensionLabel.frame = CGRect(
            x: rect.midX - labelWidth / 2,
            y: rect.minY - labelHeight - 8,
            width: labelWidth,
            height: labelHeight
        )
        dimensionLabel.isHidden = false

        CATransaction.commit()
    }

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
}

// MARK: - Area Selection Window Controller

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

            let selectionView = AreaSelectionNSView(frame: screen.frame)
            selectionView.onAreaSelected = { [weak self] rect in
                let screenRect = self?.convertToScreenCoordinates(rect, in: screen) ?? rect
                onSelected(screenRect)
                self?.closeOverlay()
            }
            selectionView.onCancelled = { [weak self] in
                onCancelled()
                self?.closeOverlay()
            }

            window.contentView = selectionView
            window.makeKeyAndOrderFront(nil)
            // Make the view accept first mouse immediately
            window.makeFirstResponder(selectionView)
            windows.append(window)
        }

        // Ensure we become the active app so key events are received
        NSApp.activate(ignoringOtherApps: true)

        // Make the first overlay window key after activation
        if let firstWindow = windows.first {
            firstWindow.makeKeyAndOrderFront(nil)
            if let view = firstWindow.contentView as? AreaSelectionNSView {
                firstWindow.makeFirstResponder(view)
            }
        }

        // Push crosshair cursor
        NSCursor.crosshair.push()
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
        // NSView coordinates: origin at bottom-left of the screen window
        // CGWindowListCreateImage uses CG global coordinates: origin at top-left of main display
        // NSScreen.frame uses bottom-left origin (Cocoa), we need to convert to CG top-left origin
        let mainScreenHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height

        // Convert the rect's position from view-local (bottom-left) to global CG (top-left)
        // 1. Get the global Y of the rect's top edge in Cocoa coords
        let globalCocoaTop = screen.frame.origin.y + rect.origin.y + rect.height
        // 2. Flip to CG coords (top-left origin)
        let cgY = mainScreenHeight - globalCocoaTop

        return CGRect(
            x: screen.frame.origin.x + rect.origin.x,
            y: cgY,
            width: rect.width,
            height: rect.height
        )
    }
}

// MARK: - Recording Area Overlay (shown during area recording)

struct RecordingAreaOverlayView: NSViewRepresentable {
    let recordingRect: CGRect
    let screenFrame: CGRect

    func makeNSView(context: Context) -> RecordingOverlayNSView {
        let view = RecordingOverlayNSView()
        view.recordingRect = recordingRect
        view.screenFrame = screenFrame
        return view
    }

    func updateNSView(_ nsView: RecordingOverlayNSView, context: Context) {
        nsView.recordingRect = recordingRect
        nsView.screenFrame = screenFrame
        nsView.needsDisplay = true
    }
}

class RecordingOverlayNSView: NSView {
    var recordingRect: CGRect = .zero
    var screenFrame: CGRect = .zero

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // Fill entire view with dark overlay
        context.setFillColor(NSColor.black.withAlphaComponent(0.4).cgColor)
        context.fill(bounds)

        // Cut out the recording area (convert screen coords to view coords)
        let localRect = CGRect(
            x: recordingRect.origin.x - screenFrame.origin.x,
            y: recordingRect.origin.y - screenFrame.origin.y,
            width: recordingRect.width,
            height: recordingRect.height
        )

        // Clear the recording area
        context.setBlendMode(.clear)
        context.fill(localRect)

        // Draw border around the recording area
        context.setBlendMode(.normal)
        context.setStrokeColor(NSColor.systemBlue.withAlphaComponent(0.6).cgColor)
        context.setLineWidth(2)
        context.stroke(localRect.insetBy(dx: -1, dy: -1))
    }
}

class RecordingAreaOverlayController {
    private var windows: [NSWindow] = []

    @MainActor
    func showOverlay(recordingRect: CGRect) {
        closeOverlay()

        for screen in NSScreen.screens {
            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.level = .floating
            window.isOpaque = false
            window.backgroundColor = .clear
            window.ignoresMouseEvents = true
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.isReleasedWhenClosed = false
            window.hasShadow = false

            let hostingView = NSHostingView(rootView:
                RecordingAreaOverlayView(
                    recordingRect: recordingRect,
                    screenFrame: screen.frame
                )
            )
            window.contentView = hostingView
            window.orderFrontRegardless()
            windows.append(window)
        }
    }

    func closeOverlay() {
        for window in windows {
            window.close()
        }
        windows.removeAll()
    }
}

// MARK: - Overlay Window

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
