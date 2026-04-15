import SwiftUI

@MainActor
final class TranslationPopupState: ObservableObject {
    enum Phase: Equatable {
        case loading
        case loaded(String)
        case failed(String)
    }

    @Published var phase: Phase = .loading
}

struct TranslationPopupView: View {
    @ObservedObject var popupState: TranslationPopupState
    let onCopy: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "character.book.closed")
                    .foregroundStyle(.secondary)
                Text("Translation")
                    .font(.headline)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }

            Divider()

            content

            HStack {
                Spacer()
                if case .loaded = popupState.phase {
                    Button(action: onCopy) {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
        }
        .padding(16)
        .frame(width: 380, alignment: .leading)
        .background(.regularMaterial)
    }

    @ViewBuilder
    private var content: some View {
        switch popupState.phase {
        case .loading:
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("Translating…")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)

        case .loaded(let text):
            ScrollView {
                Text(text)
                    .font(.system(size: 14))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 300)

        case .failed(let message):
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.system(size: 13))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 36)
        }
    }
}
