import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ZStack {
            NavigationSplitView {
                SidebarView()
            } detail: {
                DetailView()
            }
            .navigationSplitViewStyle(.balanced)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    toolbarContent
                }
            }

            if appState.showCountdown {
                CountdownView(value: appState.countdownValue)
                    .transition(.opacity)
            }

            if appState.showAnnotationEditor, let image = appState.annotationImage {
                AnnotationEditorView(
                    image: image,
                    annotationState: $appState.annotationState,
                    onSave: { annotatedImage in
                        Task { await appState.saveAnnotatedScreenshot(annotatedImage) }
                    },
                    onSaveOriginal: {
                        Task { await appState.saveScreenshotWithoutAnnotation() }
                    },
                    onCancel: {
                        appState.showAnnotationEditor = false
                        appState.annotationImage = nil
                    }
                )
                .transition(.move(edge: .bottom))
            }

            if appState.showNotification {
                VStack {
                    Spacer()
                    NotificationBanner(message: appState.notificationMessage, isError: appState.notificationIsError)
                        .padding(.bottom, 20)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .animation(.spring(response: 0.3), value: appState.showNotification)
            }
        }
    }

    @ViewBuilder
    private var toolbarContent: some View {
        if !appState.captureEngine.state.isActive {
            Menu {
                Button {
                    Task { await appState.startRecording(mode: .fullScreen) }
                } label: {
                    Label("Full Screen", systemImage: "rectangle.inset.filled")
                }

                Button {
                    Task { await appState.startRecording(mode: .window) }
                } label: {
                    Label("Window", systemImage: "macwindow")
                }

                Button {
                    Task { await appState.startRecording(mode: .area) }
                } label: {
                    Label("Selected Area", systemImage: "rectangle.dashed")
                }
            } label: {
                Label("Record", systemImage: "record.circle")
            }
            .menuStyle(.borderlessButton)

            Menu {
                Button {
                    Task { await appState.takeFullScreenScreenshot() }
                } label: {
                    Label("Full Screen", systemImage: "rectangle.inset.filled")
                }

                Button {
                    Task { await appState.takeScreenshot(mode: .area) }
                } label: {
                    Label("Selected Area", systemImage: "rectangle.dashed")
                }
            } label: {
                Label("Screenshot", systemImage: "camera")
            }
            .menuStyle(.borderlessButton)
        }
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @EnvironmentObject var appState: AppState
    @State private var showSettings = false
    @State private var showShortcuts = false

    var body: some View {
        List(selection: $appState.selectedSidebarItem) {
            Label("Home", systemImage: "house.fill")
                .tag(AppState.SidebarItem.home)

            Section("Library") {
                ForEach(AppState.SidebarItem.libraryItems) { item in
                    Label(item.rawValue, systemImage: item.iconName)
                        .tag(item)
                }
            }

            Section("Devices") {
                Label {
                    HStack {
                        Text("Device Mirror")
                        Spacer()
                        if !appState.deviceManager.devices.isEmpty {
                            Text("\(appState.deviceManager.devices.count)")
                                .font(.caption2.weight(.medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.2))
                                .foregroundColor(.green)
                                .cornerRadius(8)
                        }
                    }
                } icon: {
                    Image(systemName: "iphone.and.arrow.forward")
                }
                .tag(AppState.SidebarItem.devices)

                if appState.iosDeviceMirror.isMirroring || appState.androidDeviceMirror?.isMirroring == true {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                        Text("Mirroring Active")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                    .padding(.leading, 28)
                }
            }

            Section {
                Button {
                    showShortcuts = true
                } label: {
                    Label("Shortcuts", systemImage: "keyboard")
                }
                .buttonStyle(.plain)

                Button {
                    showSettings = true
                } label: {
                    Label("Settings", systemImage: "gear")
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 320)
        .sheet(isPresented: $showSettings) {
            SettingsPopup()
                .environmentObject(appState)
        }
        .sheet(isPresented: $showShortcuts) {
            ShortcutsPopup()
                .environmentObject(appState)
        }
    }
}

// MARK: - Shortcuts Popup

struct ShortcutsPopup: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Keyboard Shortcuts")
                    .font(.headline)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            Form {
                ForEach(ShortcutAction.allCases) { action in
                    ShortcutRow(
                        action: action,
                        shortcutSettings: appState.shortcutSettings
                    )
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("Reset to Defaults") {
                    appState.shortcutSettings.resetToDefaults()
                }
                .font(.caption)

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 400, height: 350)
    }
}

// MARK: - Settings Popup

struct SettingsPopup: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Settings")
                    .font(.headline)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            Form {
                Section("Recording") {
                    Toggle(isOn: Binding(
                        get: { appState.configuration.captureSystemAudio },
                        set: { appState.configuration.captureSystemAudio = $0 }
                    )) {
                        Label("System Audio", systemImage: "speaker.wave.2")
                    }

                    Toggle(isOn: Binding(
                        get: { appState.configuration.captureMicrophone },
                        set: { appState.configuration.captureMicrophone = $0 }
                    )) {
                        Label("Microphone", systemImage: "mic")
                    }

                    Toggle(isOn: Binding(
                        get: { appState.configuration.showCursor },
                        set: { appState.configuration.showCursor = $0 }
                    )) {
                        Label("Show Cursor", systemImage: "cursorarrow")
                    }

                    Picker(selection: Binding(
                        get: { appState.configuration.frameRate },
                        set: { appState.configuration.frameRate = $0 }
                    )) {
                        Text("30 fps").tag(30)
                        Text("60 fps").tag(60)
                    } label: {
                        Label("Frame Rate", systemImage: "speedometer")
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
        .frame(width: 380, height: 320)
    }
}

// MARK: - Detail View

struct DetailView: View {
    @EnvironmentObject var appState: AppState

    var filteredItems: [MediaItem] {
        switch appState.selectedSidebarItem {
        case .home:
            return []
        case .allMedia:
            return appState.mediaLibrary.allItems
        case .recordings:
            return appState.mediaLibrary.recordings
        case .screenshots:
            return appState.mediaLibrary.screenshots
        case .devices:
            return []
        }
    }

    var body: some View {
        Group {
            if appState.selectedSidebarItem == .home {
                homeView
            } else if appState.selectedSidebarItem == .devices {
                DeviceMirrorView()
            } else if appState.captureEngine.state.isActive {
                recordingActiveView
            } else if filteredItems.isEmpty {
                emptyLibraryView
            } else {
                HSplitView {
                    mediaGridView
                        .frame(minWidth: 300)
                    
                    if let selected = appState.selectedMediaItem {
                        RecordingPreviewView(item: selected)
                            .frame(minWidth: 250, idealWidth: 300)
                    }
                }
            }
        }
        .navigationTitle(navigationTitle)
    }

    private var navigationTitle: String {
        if appState.selectedSidebarItem == .home {
            return "Screenshot"
        }
        if appState.selectedSidebarItem == .devices {
            if appState.iosDeviceMirror.isMirroring {
                return "Device Mirror - \(appState.iosDeviceMirror.mirroringDeviceName)"
            } else if appState.androidDeviceMirror?.isMirroring == true {
                return "Device Mirror - \(appState.androidDeviceMirror?.mirroringDeviceName ?? "Android")"
            }
            return "Device Mirror"
        }
        return appState.captureEngine.state.isActive ? "Recording" : appState.selectedSidebarItem.rawValue
    }

    private var recordingActiveView: some View {
        VStack(spacing: 24) {
            Spacer()

            Circle()
                .fill(Color.red)
                .frame(width: 16, height: 16)
                .modifier(PulseAnimation())

            Text(DurationFormatter.format(appState.captureEngine.recordingDuration))
                .font(.system(size: 56, weight: .medium, design: .monospaced))
                .foregroundColor(.primary)

            Text("Recording in progress...")
                .font(.title3)
                .foregroundColor(.secondary)

            Button {
                Task { await appState.stopRecording() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 18))
                    Text("Stop Recording")
                        .font(.system(size: 18, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(width: 220, height: 56)
                .background(Color.red)
                .cornerRadius(14)
            }
            .buttonStyle(.plain)

            Button {
                Task { await appState.cancelRecording() }
            } label: {
                Text("Cancel")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var homeView: some View {
        VStack(spacing: 24) {
            Text("What would you like to do?")
                .font(.title2.weight(.medium))
                .foregroundColor(.secondary)
                .padding(.bottom, 4)

            LazyVGrid(columns: [
                GridItem(.fixed(220), spacing: 16),
                GridItem(.fixed(220), spacing: 16)
            ], spacing: 16) {
                HomeButton(
                    title: "Record\nWhole Screen",
                    icon: "rectangle.inset.filled",
                    accent: .red
                ) {
                    Task { await appState.startRecording(mode: .fullScreen) }
                }

                HomeButton(
                    title: "Record\nSelected Area",
                    icon: "rectangle.dashed",
                    accent: .red
                ) {
                    Task { await appState.startRecording(mode: .area) }
                }

                HomeButton(
                    title: "Screenshot\nWhole Screen",
                    icon: "camera.fill",
                    accent: .blue
                ) {
                    Task { await appState.takeFullScreenScreenshot() }
                }

                HomeButton(
                    title: "Screenshot\nSelected Area",
                    icon: "rectangle.dashed.and.arrow.up.forward",
                    accent: .blue
                ) {
                    Task { await appState.takeScreenshot(mode: .area) }
                }

                HomeButton(
                    title: "Text Capture\nSelected Area",
                    icon: "text.viewfinder",
                    accent: .green
                ) {
                    Task { await appState.startTextCapture() }
                }

                HomeButton(
                    title: "Mirror\nDevice",
                    icon: "iphone.and.arrow.forward",
                    accent: .purple
                ) {
                    appState.selectedSidebarItem = .devices
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyLibraryView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: appState.selectedSidebarItem == .recordings ? "video.fill" : (appState.selectedSidebarItem == .screenshots ? "photo.fill" : "square.grid.2x2"))
                .font(.system(size: 48, weight: .thin))
                .foregroundColor(.secondary.opacity(0.5))

            Text("No \(appState.selectedSidebarItem.rawValue) Yet")
                .font(.title3.weight(.medium))
                .foregroundColor(.secondary)

            Text("Your captures will appear here.")
                .font(.subheadline)
                .foregroundColor(.secondary.opacity(0.7))

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var mediaGridView: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 12)
            ], spacing: 12) {
                ForEach(filteredItems) { item in
                    MediaGridCell(item: item, isSelected: appState.selectedMediaItem?.id == item.id)
                        .onTapGesture {
                            appState.selectedMediaItem = item
                        }
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
            .padding(16)
        }
    }
}

// MARK: - Media Grid Cell

struct MediaGridCell: View {
    let item: MediaItem
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                if let thumbnail = item.thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(16/10, contentMode: .fill)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .aspectRatio(16/10, contentMode: .fill)
                        .overlay(
                            Image(systemName: item.type.iconName)
                                .font(.system(size: 30))
                                .foregroundColor(.secondary)
                        )
                }

                if item.type == .recording, let duration = item.formattedDuration {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Text(duration)
                                .font(.caption2.weight(.medium).monospacedDigit())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.black.opacity(0.7))
                                .foregroundColor(.white)
                                .cornerRadius(4)
                                .padding(6)
                        }
                    }
                }
            }
            .cornerRadius(8)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.fileName)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack {
                    Text(item.formattedDate)
                    Text("·")
                    Text(item.formattedFileSize)
                }
                .font(.caption2)
                .foregroundColor(.secondary)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 6)
        }
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
    }
}

// MARK: - Pulse Animation

struct PulseAnimation: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPulsing ? 1.4 : 1.0)
            .opacity(isPulsing ? 0.5 : 1.0)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear { isPulsing = true }
    }
}

// MARK: - Home Button

struct HomeButton: View {
    let title: String
    let icon: String
    let accent: Color
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 36, weight: .medium))
                    .foregroundColor(accent)

                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 220, height: 140)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isHovering ? accent.opacity(0.08) : Color.gray.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isHovering ? accent.opacity(0.4) : Color.gray.opacity(0.15), lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
}

// MARK: - Shortcut Row

struct ShortcutRow: View {
    let action: ShortcutAction
    @ObservedObject var shortcutSettings: ShortcutSettings
    @EnvironmentObject var appState: AppState
    @State private var isRecording = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(action.rawValue, systemImage: action.iconName)
                .font(.system(size: 12))

            ShortcutRecorderButton(
                combo: shortcutSettings.binding(for: action),
                isRecording: $isRecording,
                onRecord: { combo in
                    shortcutSettings.setBinding(combo, for: action)
                    appState.isRecordingShortcut = false
                },
                onClear: {
                    shortcutSettings.setBinding(.empty, for: action)
                },
                onStartRecording: {
                    appState.isRecordingShortcut = true
                },
                onStopRecording: {
                    appState.isRecordingShortcut = false
                }
            )
        }
        .padding(.vertical, 2)
    }
}

struct ShortcutRecorderButton: View {
    let combo: KeyCombo
    @Binding var isRecording: Bool
    let onRecord: (KeyCombo) -> Void
    let onClear: () -> Void
    var onStartRecording: () -> Void = {}
    var onStopRecording: () -> Void = {}

    @State private var eventMonitor: Any?

    var body: some View {
        HStack(spacing: 4) {
            Button {
                if isRecording {
                    stopListening()
                } else {
                    startListening()
                }
            } label: {
                HStack(spacing: 4) {
                    if isRecording {
                        Text("Press shortcut...")
                            .font(.system(size: 11))
                            .foregroundColor(.accentColor)
                    } else {
                        Text(combo.displayString)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(combo.isEmpty ? .secondary : .primary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(isRecording ? Color.accentColor.opacity(0.1) : Color.gray.opacity(0.1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(isRecording ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            if !combo.isEmpty {
                Button {
                    onClear()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear shortcut")
            }
        }
        .onDisappear {
            stopListening()
        }
    }

    private func startListening() {
        isRecording = true
        onStartRecording()

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            if event.keyCode == 53 {
                stopListening()
                return nil
            }

            guard !modifiers.isEmpty else { return nil }

            let combo = KeyCombo(keyCode: event.keyCode, modifiers: modifiers.rawValue)
            onRecord(combo)
            stopListening()
            return nil
        }
    }

    private func stopListening() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        isRecording = false
        onStopRecording()
    }
}

// MARK: - Notification Banner

struct NotificationBanner: View {
    let message: String
    var isError: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundColor(isError ? .orange : .green)
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: 400)
        .background(.ultraThinMaterial)
        .cornerRadius(10)
        .shadow(radius: 10)
    }
}
