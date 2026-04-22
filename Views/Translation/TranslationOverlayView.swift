import SwiftUI

@MainActor
final class TranslationOverlayState: ObservableObject {
    enum Phase: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    @Published var image: NSImage
    @Published var phase: Phase = .loading
    @Published var engineName: String?

    init(image: NSImage) {
        self.image = image
    }
}

/// The visible layer of the in-place translation overlay: the composited
/// screenshot at full panel size, plus a floating toolbar in the top-right
/// corner that lets the user save the composite, copy it, or close the
/// overlay. The whole surface is also a drag handle for repositioning — so
/// the user can move it off the original text to compare, or anywhere else.
struct TranslationOverlayView: View {
    @ObservedObject var state: TranslationOverlayState
    let onRetry: () -> Void
    let onSave: () -> Void
    let onCopy: () -> Void
    let onClose: () -> Void

    var body: some View {
        Image(nsImage: state.image)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fill)
            .overlay(alignment: .topTrailing) { toolbar }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private var toolbar: some View {
        switch state.phase {
        case .loading:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Translating…")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.black)
                closeButton
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.white)
            )
            .padding(8)

        case .loaded:
            HStack(spacing: 4) {
                toolbarButton(system: "square.and.arrow.down", help: "Save", action: onSave)
                toolbarButton(system: "doc.on.doc", help: "Copy", action: onCopy)
                closeButton
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.white)
            )
            .padding(8)

        case .failed(let message):
            HStack(spacing: 4) {
                Button(action: onRetry) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .bold))
                        Text(message)
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                closeButton
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.white)
            )
            .padding(8)
        }
    }

    private var closeButton: some View {
        toolbarButton(system: "xmark", help: "Close", action: onClose)
    }

    private func toolbarButton(system: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.black)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
