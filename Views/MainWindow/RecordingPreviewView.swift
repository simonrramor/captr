import SwiftUI
import AVKit

struct RecordingPreviewView: View {
    let item: MediaItem
    @State private var player: AVPlayer?

    var body: some View {
        VStack(spacing: 0) {
            previewContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            detailsPanel
        }
        .onChange(of: item.id) { _, _ in
            setupPlayer()
        }
        .onAppear {
            setupPlayer()
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }

    @ViewBuilder
    private var previewContent: some View {
        switch item.type {
        case .recording:
            if let player = player {
                VideoPlayer(player: player)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

        case .screenshot:
            if let image = NSImage(contentsOf: item.url) {
                ScrollView([.horizontal, .vertical]) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(8)
                }
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var detailsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.fileName)
                .font(.headline)
                .lineLimit(1)

            HStack(spacing: 16) {
                DetailLabel(icon: "calendar", text: item.formattedDate)

                if let duration = item.formattedDuration {
                    DetailLabel(icon: "clock", text: duration)
                }

                DetailLabel(icon: "doc", text: item.formattedFileSize)
            }

            HStack(spacing: 8) {
                Button {
                    NSWorkspace.shared.open(item.url)
                } label: {
                    Label("Open", systemImage: "arrow.up.forward.square")
                }
                .buttonStyle(.bordered)

                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([item.url])
                } label: {
                    Label("Show in Finder", systemImage: "folder")
                }
                .buttonStyle(.bordered)

                Spacer()

                ShareLink(item: item.url) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial)
    }

    private func setupPlayer() {
        if item.type == .recording {
            player = AVPlayer(url: item.url)
        } else {
            player = nil
        }
    }
}

struct DetailLabel: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}
