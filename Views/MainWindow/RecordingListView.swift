import SwiftUI

struct RecordingListView: View {
    @EnvironmentObject var appState: AppState
    let items: [MediaItem]

    var body: some View {
        List(selection: $appState.selectedMediaItem) {
            ForEach(items) { item in
                RecordingListRow(item: item)
                    .tag(item)
                    .contextMenu {
                        Button("Open") {
                            appState.mediaLibrary.openInDefaultApp(item)
                        }
                        Button("Show in Finder") {
                            appState.mediaLibrary.revealInFinder(item)
                        }
                        Divider()
                        Button("Delete", role: .destructive) {
                            appState.mediaLibrary.deleteItem(item)
                            if appState.selectedMediaItem?.id == item.id {
                                appState.selectedMediaItem = nil
                            }
                        }
                    }
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }
}

struct RecordingListRow: View {
    let item: MediaItem

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                if let thumbnail = item.thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 60, height: 40)
                        .clipped()
                        .cornerRadius(4)
                } else {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 60, height: 40)
                        .overlay(
                            Image(systemName: item.type.iconName)
                                .font(.system(size: 16))
                                .foregroundColor(.secondary)
                        )
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.fileName)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Image(systemName: item.type.iconName)
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Text(item.formattedDate)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if let duration = item.formattedDuration {
                        Text("·")
                            .foregroundColor(.secondary)
                        Text(duration)
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.secondary)
                    }

                    Text("·")
                        .foregroundColor(.secondary)
                    Text(item.formattedFileSize)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 2)
    }
}
