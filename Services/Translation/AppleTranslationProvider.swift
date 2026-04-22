import Foundation
import SwiftUI
import Translation
import AppKit

/// Drives Apple's on-device `Translation` framework from a long-lived hidden
/// NSPanel so that back-to-back translations of the same language pair reuse
/// the underlying `TranslationSession` (set up once via `.translationTask`).
/// When the pair changes we tear down the request stream, which lets SwiftUI
/// swap the session cleanly on the next config change.
@MainActor
final class AppleTranslationProvider: TranslationProvider {
    let displayName = "Apple"

    private var panel: NSPanel?
    private let coordinator = TranslationCoordinator()

    func prewarm() {
        ensurePanel()
    }

    func translate(_ text: String, from source: Locale.Language, to target: Locale.Language) async throws -> String {
        ensurePanel()
        return try await coordinator.submit(text: text, source: source, target: target)
    }

    private func ensurePanel() {
        guard panel == nil else { return }

        let hostView = TranslationHostView(coordinator: coordinator)
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
        panel = p
    }
}

// MARK: - Coordinator

@MainActor
private class TranslationCoordinator: ObservableObject {
    struct Request {
        let text: String
        let continuation: CheckedContinuation<String, Error>
    }

    @Published var config: TranslationSession.Configuration?
    private(set) var stream: AsyncStream<Request>?
    private var streamContinuation: AsyncStream<Request>.Continuation?

    private var currentSourceID: String?
    private var currentTargetID: String?

    func submit(text: String, source: Locale.Language, target: Locale.Language) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let request = Request(text: text, continuation: continuation)

            let sourceID = source.maximalIdentifier
            let targetID = target.maximalIdentifier

            if sourceID == currentSourceID,
               targetID == currentTargetID,
               let cont = streamContinuation {
                cont.yield(request)
            } else {
                streamContinuation?.finish()

                let (newStream, newContinuation) = AsyncStream<Request>.makeStream()
                stream = newStream
                streamContinuation = newContinuation
                currentSourceID = sourceID
                currentTargetID = targetID

                newContinuation.yield(request)

                config = .init(source: source, target: target)
            }
        }
    }
}

// MARK: - Hidden hosting view

private struct TranslationHostView: View {
    @ObservedObject var coordinator: TranslationCoordinator

    var body: some View {
        Color.clear
            .translationTask(coordinator.config) { session in
                guard let stream = coordinator.stream else { return }
                for await request in stream {
                    do {
                        let response = try await session.translate(request.text)
                        request.continuation.resume(returning: response.targetText)
                    } catch {
                        request.continuation.resume(throwing: error)
                    }
                }
            }
    }
}
