import SwiftUI
import AppKit

@MainActor
class TranslationPopupController {
    private var panel: NSPanel?
    private var popupState: TranslationPopupState?
    private var hostingView: NSHostingView<TranslationPopupView>?

    /// Anchor rect (CG global coordinates — top-left origin, main screen basis)
    /// of the selected area, used to keep the popup near the source text as
    /// its content grows.
    private var anchorRect: CGRect?

    /// Opens the popup in a loading state so the user gets instant feedback
    /// while OCR and translation run in the background. If `anchor` is given,
    /// the popup is positioned next to that rect; otherwise it centers on the
    /// active screen.
    func showLoading(anchor: CGRect? = nil) {
        close()

        let state = TranslationPopupState()
        self.popupState = state
        self.anchorRect = anchor

        let view = TranslationPopupView(
            popupState: state,
            onCopy: { [weak self] in
                if case .loaded(let text) = state.phase {
                    TextCaptureService.copyToClipboard(text)
                }
                self?.close()
            },
            onDismiss: { [weak self] in
                self?.close()
            }
        )

        let hosting = NSHostingView(rootView: view)
        hosting.frame.size = hosting.fittingSize

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.contentView = hosting
        panel.isMovableByWindowBackground = true

        self.panel = panel
        self.hostingView = hosting

        if let anchor = anchor {
            positionNear(anchor: anchor)
        } else {
            centerOnScreen()
        }

        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Updates an existing loading popup with the translated text, or opens
    /// the popup directly in the loaded state if it wasn't already showing.
    func show(translatedText: String) {
        if popupState == nil { showLoading() }
        popupState?.phase = .loaded(translatedText)
        resizeToFit()
    }

    func showError(_ message: String) {
        if popupState == nil { showLoading() }
        popupState?.phase = .failed(message)
        resizeToFit()
    }

    func close() {
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
        popupState = nil
        hostingView = nil
        anchorRect = nil
    }

    /// SwiftUI needs a layout pass before `fittingSize` reflects the new content,
    /// so defer the panel resize to the next run-loop tick. Re-anchor to the
    /// selection rect if we have one; otherwise keep the panel centered on
    /// its current midpoint.
    private func resizeToFit() {
        guard panel != nil, hostingView != nil else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let panel = self.panel, let hosting = self.hostingView else { return }
            let newSize = hosting.fittingSize
            panel.setContentSize(newSize)
            if let anchor = self.anchorRect {
                self.positionNear(anchor: anchor)
            } else {
                let currentFrame = panel.frame
                let origin = NSPoint(
                    x: currentFrame.midX - newSize.width / 2,
                    y: currentFrame.midY - newSize.height / 2
                )
                panel.setFrameOrigin(origin)
            }
        }
    }

    private func centerOnScreen() {
        guard let panel = panel, let hosting = hostingView else { return }
        guard let screen = NSScreen.main else { return }
        let size = hosting.fittingSize
        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - size.width / 2
        let y = screenFrame.midY - size.height / 2
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    /// Place the popup just below the selected rect, flipping above if there
    /// isn't enough room at the bottom, and clamp to the screen's visible
    /// frame so it's never cut off. The anchor comes in CG global coordinates
    /// (top-left origin, main-screen-height basis), matching what
    /// `AreaSelectionWindowController` emits.
    private func positionNear(anchor: CGRect) {
        guard let panel = panel, let hosting = hostingView else { return }
        let popupSize = hosting.fittingSize

        // Convert anchor from CG top-left origin to Cocoa bottom-left origin.
        let mainScreenHeight = NSScreen.screens.first?.frame.height ?? 0
        let cocoaMinY = mainScreenHeight - anchor.origin.y - anchor.height
        let cocoaMaxY = mainScreenHeight - anchor.origin.y
        let cocoaMidX = anchor.origin.x + anchor.width / 2

        // Pick the screen containing the anchor's center; fall back to main.
        let center = NSPoint(x: cocoaMidX, y: (cocoaMinY + cocoaMaxY) / 2)
        let screen = NSScreen.screens.first(where: { $0.frame.contains(center) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? .zero

        let gap: CGFloat = 12
        var x = cocoaMidX - popupSize.width / 2
        // Below the selection by default.
        var y = cocoaMinY - popupSize.height - gap

        // Not enough room below? Flip to above.
        if y < visible.minY {
            y = cocoaMaxY + gap
        }

        // Clamp so the popup stays fully on-screen.
        x = max(visible.minX, min(x, visible.maxX - popupSize.width))
        y = max(visible.minY, min(y, visible.maxY - popupSize.height))

        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
