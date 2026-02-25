import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ZStack {
            screenshotBar
                .padding(8)
                .fixedSize()
                .background(Color(nsColor: NSColor(white: 0.12, alpha: 1.0)))
                .cornerRadius(12)
                .preferredColorScheme(.dark)

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

    private var screenshotBar: some View {
        HStack(spacing: 12) {
            // Mode picker
            HStack(spacing: 4) {
                ForEach([CaptureMode.fullScreen, .window, .area], id: \.self) { mode in
                    Button {
                        appState.screenshotMode = mode
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: mode.iconName)
                                .font(.system(size: 11))
                            Text(mode.rawValue)
                                .font(.system(size: 12))
                        }
                        .foregroundColor(appState.screenshotMode == mode ? .white : .secondary)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(appState.screenshotMode == mode ? Color(nsColor: NSColor(white: 0.30, alpha: 1.0)) : Color(nsColor: NSColor(white: 0.20, alpha: 1.0)))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            // Capture button
            Button {
                Task { await appState.captureScreenshot() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 11))
                    Text("Capture")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.vertical, 8)
                .padding(.horizontal, 16)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.accentColor)
                )
            }
            .buttonStyle(.plain)

            // Settings gear
            Button {
                appState.showSettingsPopover = true
            } label: {
                Image("SettingsIcon")
                    .resizable()
                    .frame(width: 16, height: 16)
                    .foregroundColor(.white)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(nsColor: NSColor(white: 0.12, alpha: 1.0)))
                    )
            }
            .buttonStyle(.plain)
            .popover(isPresented: $appState.showSettingsPopover) {
                SettingsPopup()
                    .environmentObject(appState)
            }
        }
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

                Section("Shortcuts") {
                    ForEach(ShortcutAction.allCases) { action in
                        ShortcutRow(
                            action: action,
                            shortcutSettings: appState.shortcutSettings
                        )
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
        .frame(width: 380, height: 500)
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
