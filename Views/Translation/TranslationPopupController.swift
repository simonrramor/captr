import SwiftUI
import AppKit

@MainActor
class TranslationPopupController {
    private var panel: NSPanel?
    private var popupState: TranslationPopupState?
    private var hostingView: NSHostingView<TranslationPopupView>?

    /// Opens the popup in a loading state so the user gets instant feedback
    /// while OCR and translation run in the background.
    func showLoading() {
        close()

        let state = TranslationPopupState()
        self.popupState = state

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

        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let panelSize = hosting.fittingSize
            let x = screenFrame.midX - panelSize.width / 2
            let y = screenFrame.midY - panelSize.height / 2
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        self.panel = panel
        self.hostingView = hosting

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
    }

    /// SwiftUI needs a layout pass before `fittingSize` reflects the new content,
    /// so defer the panel resize to the next run-loop tick. Recenter on the
    /// popup's current midpoint so content updates don't cause it to jump.
    private func resizeToFit() {
        guard let panel = panel, let hosting = hostingView else { return }
        DispatchQueue.main.async { [weak panel, weak hosting] in
            guard let panel = panel, let hosting = hosting else { return }
            let newSize = hosting.fittingSize
            let currentFrame = panel.frame
            let origin = NSPoint(
                x: currentFrame.midX - newSize.width / 2,
                y: currentFrame.midY - newSize.height / 2
            )
            panel.setFrame(NSRect(origin: origin, size: newSize), display: true, animate: true)
        }
    }
}
