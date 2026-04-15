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

    private let cornerRadius: CGFloat = 16
    private let iconButtonSize: CGFloat = 36
    private let iconButtonCornerRadius: CGFloat = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            header
            content
            footer
        }
        .padding(24)
        .frame(width: 460, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))
        )
    }

    private var header: some View {
        HStack(alignment: .top) {
            Text("Translation")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.primary)

            Spacer()

            iconButton(systemName: "xmark", action: onDismiss)
                .help("Close")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch popupState.phase {
        case .loading:
            HStack(spacing: 12) {
                ProgressView()
                    .controlSize(.small)
                Text("Translating…")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)

        case .loaded(let text):
            ScrollView {
                Text(text)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxHeight: 320)

        case .failed(let message):
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.system(size: 18))
                Text(message)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 60)
        }
    }

    @ViewBuilder
    private var footer: some View {
        HStack {
            Spacer()
            if case .loaded = popupState.phase {
                iconButton(systemName: "doc.on.doc", action: onCopy)
                    .help("Copy")
            }
        }
        .frame(minHeight: iconButtonSize)
    }

    private func iconButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: iconButtonSize, height: iconButtonSize)
                .background(
                    RoundedRectangle(cornerRadius: iconButtonCornerRadius, style: .continuous)
                        .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.5))
                )
        }
        .buttonStyle(.plain)
    }
}
