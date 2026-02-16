import Foundation
import SwiftUI
import ScreenCaptureKit
import Combine

@MainActor
class AppState: ObservableObject {
    @Published var captureEngine = CaptureEngine()
    @Published var screenshotService = ScreenshotService()
    @Published var textCaptureService = TextCaptureService()
    @Published var mediaLibrary = MediaLibraryManager()
    @Published var permissionsManager = PermissionsManager()
    @Published var shortcutSettings = ShortcutSettings()

    @Published var deviceManager = DeviceManager()
    @Published var iosDeviceMirror = IOSDeviceMirror()
    @Published var androidDeviceMirror: AndroidDeviceMirror?
    var mirrorWindow = DeviceMirrorWindow()

    @Published var selectedSidebarItem: SidebarItem = .home
    @Published var selectedMediaItem: MediaItem?
    @Published var pendingCaptureAction: CaptureType?

    @Published var showAnnotationEditor: Bool = false
    @Published var annotationImage: NSImage?
    @Published var annotationState = AnnotationState()

    @Published var showCountdown: Bool = false
    @Published var countdownValue: Int = 3

    @Published var showNotification: Bool = false
    @Published var notificationMessage: String = ""
    @Published var notificationIsError: Bool = false
    @Published var isRecordingShortcut: Bool = false

    private let areaSelectionController = AreaSelectionWindowController()

    var configuration: CaptureConfiguration {
        get { captureEngine.configuration }
        set { captureEngine.configuration = newValue }
    }

    enum SidebarItem: String, CaseIterable, Identifiable {
        case home = "Home"
        case allMedia = "All Media"
        case recordings = "Recordings"
        case screenshots = "Screenshots"
        case devices = "Devices"

        var id: String { rawValue }

        var iconName: String {
            switch self {
            case .home: return "house.fill"
            case .allMedia: return "square.grid.2x2"
            case .recordings: return "video.fill"
            case .screenshots: return "photo.fill"
            case .devices: return "iphone.and.arrow.forward"
            }
        }

        static var libraryItems: [SidebarItem] {
            [.allMedia, .recordings, .screenshots]
        }
    }

    func initialize() async {
        await permissionsManager.checkAllPermissions()
        await captureEngine.refreshAvailableContent()
        await mediaLibrary.loadLibrary()
        deviceManager.startMonitoring()
        setupAndroidMirror()
    }

    private func setupAndroidMirror() {
        if let adb = deviceManager.adbPath {
            androidDeviceMirror = AndroidDeviceMirror(adbPath: adb)
        }
    }

    // MARK: - Device Mirroring Actions

    func startDeviceMirroring(device: ConnectedDevice) async {
        switch device.platform {
        case .iOS:
            guard let captureDevice = device.captureDevice else {
                showErrorNotification("iOS device not available for capture")
                return
            }
            iosDeviceMirror.startMirroring(device: captureDevice)
            // Open mirror in a new window
            if let session = iosDeviceMirror.captureSession {
                mirrorWindow.openIOSMirrorWindow(session: session, deviceName: device.name, mirror: iosDeviceMirror, appState: self)
            }

        case .android:
            guard let mirror = androidDeviceMirror else {
                setupAndroidMirror()
                guard androidDeviceMirror != nil else {
                    showErrorNotification("ADB not installed. Install via Homebrew: brew install android-platform-tools")
                    return
                }
                await startDeviceMirroring(device: device)
                return
            }
            mirror.startMirroring(device: device)
            // Open mirror in a new window
            mirrorWindow.openAndroidMirrorWindow(mirror: mirror, appState: self)
        }
    }

    func startDeviceMirroringWithRecording(device: ConnectedDevice) async {
        switch device.platform {
        case .iOS:
            guard let captureDevice = device.captureDevice else {
                showErrorNotification("iOS device not available for capture")
                return
            }
            iosDeviceMirror.startMirroring(device: captureDevice)
            Task {
                try? await Task.sleep(nanoseconds: 500_000_000)
                iosDeviceMirror.startRecording()
            }
            if let session = iosDeviceMirror.captureSession {
                mirrorWindow.openIOSMirrorWindow(session: session, deviceName: device.name, mirror: iosDeviceMirror, appState: self)
            }

        case .android:
            guard let mirror = androidDeviceMirror else {
                showErrorNotification("ADB not installed. Install via Homebrew: brew install android-platform-tools")
                return
            }
            mirror.startMirroring(device: device)
            Task {
                try? await Task.sleep(nanoseconds: 500_000_000)
                mirror.startRecording()
            }
            mirrorWindow.openAndroidMirrorWindow(mirror: mirror, appState: self)
        }
    }

    func takeDeviceScreenshot(device: ConnectedDevice) async {
        switch device.platform {
        case .iOS:
            if iosDeviceMirror.isMirroring {
                if let image = iosDeviceMirror.takeScreenshot() {
                    presentAnnotationEditor(with: image)
                } else {
                    showErrorNotification("Failed to capture screenshot from iOS device")
                }
            } else {
                guard let captureDevice = device.captureDevice else {
                    showErrorNotification("iOS device not available")
                    return
                }
                iosDeviceMirror.startMirroring(device: captureDevice)
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if let image = iosDeviceMirror.takeScreenshot() {
                    presentAnnotationEditor(with: image)
                }
                iosDeviceMirror.stopMirroring()
            }

        case .android:
            guard let mirror = androidDeviceMirror else {
                showErrorNotification("ADB not installed")
                return
            }
            if mirror.isMirroring, let image = mirror.takeScreenshot() {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.writeObjects([image])
                showSaveNotification("Device screenshot copied to clipboard")
            } else {
                showErrorNotification("Start mirroring first to take a screenshot")
            }
        }
    }

    func takeIOSDeviceScreenshot() async {
        guard iosDeviceMirror.isMirroring else { return }
        if let image = iosDeviceMirror.takeScreenshot() {
            presentAnnotationEditor(with: image)
        } else {
            showErrorNotification("Failed to capture screenshot")
        }
    }

    func showSavedNotification(_ message: String) {
        showSaveNotification(message)
    }

    // MARK: - Recording Actions

    func startRecording(mode: CaptureMode) async {
        guard await ensureReadyForCapture() else { return }
        configuration.mode = mode

        switch mode {
        case .fullScreen:
            await performCountdownAndRecord()
        case .window:
            await performCountdownAndRecord()
        case .area:
            pendingCaptureAction = .recording
            showAreaSelection()
        }
    }

    private func showAreaSelection() {
        areaSelectionController.showOverlay(
            onSelected: { [weak self] rect in
                guard let self = self else { return }
                Task { @MainActor in
                    await self.onAreaSelected(rect)
                }
            },
            onCancelled: { [weak self] in
                Task { @MainActor in
                    self?.onAreaSelectionCancelled()
                }
            }
        )
    }

    func onAreaSelected(_ rect: CGRect) async {
        configuration.selectedArea = rect

        if let action = pendingCaptureAction {
            pendingCaptureAction = nil
            switch action {
            case .recording:
                configuration.mode = .area
                await performCountdownAndRecord()
            case .screenshot:
                await takeAreaScreenshot(area: rect)
            case .textCapture:
                await performTextCapture(area: rect)
            }
        }
    }

    func onAreaSelectionCancelled() {
        pendingCaptureAction = nil
    }

    private func performCountdownAndRecord() async {
        showCountdown = true
        countdownValue = 3

        for i in stride(from: 3, through: 1, by: -1) {
            countdownValue = i
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }

        showCountdown = false
        await captureEngine.startRecording()
    }

    func stopRecording() async {
        if let url = await captureEngine.stopRecording() {
            await mediaLibrary.addRecording(at: url)
            showSaveNotification("Recording saved")
        }
    }

    func cancelRecording() async {
        await captureEngine.cancelRecording()
    }

    // MARK: - Screenshot Actions

    private func ensureReadyForCapture() async -> Bool {
        if captureEngine.availableDisplays.isEmpty {
            await captureEngine.refreshAvailableContent()
        }
        if captureEngine.availableDisplays.isEmpty {
            showErrorNotification("No displays found. Please check screen recording permission in System Settings.")
            return false
        }
        return true
    }

    func takeScreenshot(mode: CaptureMode) async {
        guard await ensureReadyForCapture() else { return }
        switch mode {
        case .fullScreen:
            await takeFullScreenScreenshot()
        case .window:
            break
        case .area:
            pendingCaptureAction = .screenshot
            showAreaSelection()
        }
    }

    func takeFullScreenScreenshot() async {
        guard await ensureReadyForCapture() else { return }

        let display = configuration.selectedDisplay ?? captureEngine.availableDisplays.first
        if let image = await screenshotService.captureFullScreen(display: display) {
            presentAnnotationEditor(with: image)
        } else if let error = screenshotService.errorMessage {
            showErrorNotification(error)
        }
    }

    func takeWindowScreenshot(_ window: SCWindow) async {
        guard await ensureReadyForCapture() else { return }

        if let image = await screenshotService.captureWindow(window) {
            presentAnnotationEditor(with: image)
        } else if let error = screenshotService.errorMessage {
            showErrorNotification(error)
        }
    }

    func takeAreaScreenshot(area: CGRect) async {
        guard await ensureReadyForCapture() else { return }

        let display = configuration.selectedDisplay ?? captureEngine.availableDisplays.first
        if let image = await screenshotService.captureArea(display: display, area: area) {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects([image])
            showSaveNotification("Screenshot copied to clipboard")
        } else if let error = screenshotService.errorMessage {
            showErrorNotification(error)
        }
    }

    private func presentAnnotationEditor(with image: NSImage) {
        annotationImage = image
        annotationState = AnnotationState()
        showAnnotationEditor = true
    }

    func saveAnnotatedScreenshot(_ image: NSImage) async {
        showAnnotationEditor = false
        if let _ = screenshotService.saveScreenshot(image, annotated: annotationState.items.isEmpty == false) {
            await mediaLibrary.addScreenshot(at: MediaLibraryManager.screenshotsDirectory)
            showSaveNotification("Screenshot saved")
        }
        annotationImage = nil
    }

    func saveScreenshotWithoutAnnotation() async {
        showAnnotationEditor = false
        if let image = annotationImage {
            if let _ = screenshotService.saveScreenshot(image, annotated: false) {
                await mediaLibrary.addScreenshot(at: MediaLibraryManager.screenshotsDirectory)
                showSaveNotification("Screenshot saved")
            }
        }
        annotationImage = nil
    }

    // MARK: - Text Capture Actions

    func startTextCapture() async {
        guard await ensureReadyForCapture() else { return }
        pendingCaptureAction = .textCapture
        showAreaSelection()
    }

    private func performTextCapture(area: CGRect) async {
        if let text = await textCaptureService.captureAndRecognizeArea(area) {
            TextCaptureService.copyToClipboard(text)
            showSaveNotification("Text copied to clipboard")
        } else {
            showErrorNotification(textCaptureService.errorMessage ?? "No text found in the selected area")
        }
    }

    // MARK: - Notifications

    private func showSaveNotification(_ message: String) {
        notificationMessage = message
        notificationIsError = false
        showNotification = true

        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            showNotification = false
        }
    }

    private func showErrorNotification(_ message: String) {
        notificationMessage = message
        notificationIsError = true
        showNotification = true

        Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            showNotification = false
        }
    }
}
