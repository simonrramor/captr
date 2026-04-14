import SwiftUI
import AppKit

@MainActor
class TranslationPopupController {
    private var panel: NSPanel?

    func show(translatedText: String) {
        close()

        let view = TranslationPopupView(
            translatedText: translatedText,
            onCopy: { [weak self] in
                TextCaptureService.copyToClipboard(translatedText)
                self?.close()
            },
            onDismiss: { [weak self] in
                self?.close()
            }
        )

        let hostingView = NSHostingView(rootView: view)
        hostingView.frame.size = hostingView.fittingSize

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: hostingView.fittingSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.contentView = hostingView
        panel.isMovableByWindowBackground = true

        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let panelSize = hostingView.fittingSize
            let x = screenFrame.midX - panelSize.width / 2
            let y = screenFrame.midY - panelSize.height / 2
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.panel = panel
    }

    func close() {
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
    }
}
