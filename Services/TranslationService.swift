import Foundation
import SwiftUI
import Translation
import AppKit

@MainActor
class TranslationService {
    private var panel: NSPanel?

    func translate(_ text: String, from source: Locale.Language, to target: Locale.Language) async throws -> String {
        tearDown()

        let state = TranslationState()
        state.pendingText = text
        state.config = .init(source: source, target: target)

        let result: String = try await withCheckedThrowingContinuation { continuation in
            state.pendingContinuation = continuation

            let hostView = TranslationHostView(state: state)
            let hosting = NSHostingController(rootView: AnyView(hostView))
            hosting.view.frame = NSRect(x: 0, y: 0, width: 1, height: 1)

            let p = NSPanel(
                contentRect: NSRect(x: -10000, y: -10000, width: 1, height: 1),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            p.isOpaque = false
            p.backgroundColor = .clear
            p.level = .floating
            p.hasShadow = false
            p.isReleasedWhenClosed = false
            p.ignoresMouseEvents = true
            p.collectionBehavior = [.canJoinAllSpaces, .stationary]
            p.alphaValue = 0
            p.contentView = hosting.view
            p.orderFrontRegardless()
            self.panel = p
        }

        tearDown()
        return result
    }

    private func tearDown() {
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
    }
}

@MainActor
private class TranslationState: ObservableObject {
    @Published var config: TranslationSession.Configuration?
    var pendingText: String?
    var pendingContinuation: CheckedContinuation<String, Error>?
}

private struct TranslationHostView: View {
    @ObservedObject var state: TranslationState

    var body: some View {
        Color.clear
            .translationTask(state.config) { session in
                guard let text = state.pendingText,
                      let continuation = state.pendingContinuation else { return }
                state.pendingText = nil
                state.pendingContinuation = nil
                do {
                    let response = try await session.translate(text)
                    continuation.resume(returning: response.targetText)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
    }
}
