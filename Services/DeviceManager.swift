import Foundation
import AVFoundation
import Combine

struct ConnectedDevice: Identifiable, Hashable {
    let id: String
    let name: String
    let platform: DevicePlatform
    var captureDevice: AVCaptureDevice?
    var adbSerial: String?

    enum DevicePlatform: String, Codable {
        case iOS = "iOS"
        case android = "Android"

        var iconName: String {
            switch self {
            case .iOS: return "iphone"
            case .android: return "candybarphone"
            }
        }
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: ConnectedDevice, rhs: ConnectedDevice) -> Bool {
        lhs.id == rhs.id
    }
}

@MainActor
class DeviceManager: ObservableObject {
    @Published var devices: [ConnectedDevice] = []
    @Published var adbPath: String?
    @Published var scrcpyPath: String?
    @Published var isInstalling = false
    @Published var statusMessage: String?

    private var deviceObservers: [NSObjectProtocol] = []
    private var scanTimer: Timer?

    var adbAvailable: Bool { adbPath != nil }
    var scrcpyAvailable: Bool { scrcpyPath != nil }
    var iosDevices: [ConnectedDevice] { devices.filter { $0.platform == .iOS } }
    var androidDevices: [ConnectedDevice] { devices.filter { $0.platform == .android } }

    init() {
        findTools()
    }

    func startMonitoring() {
        scanIOSDevices()
        if adbAvailable {
            scanAndroidDevices()
        }

        let connected = NotificationCenter.default.addObserver(
            forName: .AVCaptureDeviceWasConnected,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.scanIOSDevices() }
        }

        let disconnected = NotificationCenter.default.addObserver(
            forName: .AVCaptureDeviceWasDisconnected,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.scanIOSDevices() }
        }

        deviceObservers = [connected, disconnected]

        if adbAvailable {
            scanTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.scanAndroidDevices() }
            }
        }
    }

    func stopMonitoring() {
        deviceObservers.forEach { NotificationCenter.default.removeObserver($0) }
        deviceObservers.removeAll()
        scanTimer?.invalidate()
        scanTimer = nil
    }

    func findTools() {
        let adbPaths = [
            "/opt/homebrew/bin/adb",
            "/usr/local/bin/adb",
            "\(NSHomeDirectory())/Library/Android/sdk/platform-tools/adb"
        ]
        adbPath = adbPaths.first { FileManager.default.fileExists(atPath: $0) }

        let scrcpyPaths = [
            "/opt/homebrew/bin/scrcpy",
            "/usr/local/bin/scrcpy"
        ]
        scrcpyPath = scrcpyPaths.first { FileManager.default.fileExists(atPath: $0) }
    }

    func scanIOSDevices() {
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external],
            mediaType: .video,
            position: .unspecified
        )

        let iosDevices = session.devices.map { device in
            // Clean up display name - strip "Camera" suffix from Continuity Camera labels
            var displayName = device.localizedName
            if displayName.hasSuffix(" Camera") {
                displayName = String(displayName.dropLast(7))
            }

            return ConnectedDevice(
                id: device.uniqueID,
                name: displayName,
                platform: .iOS,
                captureDevice: device
            )
        }

        let android = devices.filter { $0.platform == .android }
        devices = iosDevices + android
    }

    func scanAndroidDevices() {
        guard let adbPath = adbPath else { return }

        Task.detached {
            let output = DeviceManager.runCommand(adbPath, arguments: ["devices", "-l"])
            var androidDevices: [ConnectedDevice] = []

            for line in output.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty,
                      !trimmed.starts(with: "List"),
                      !trimmed.starts(with: "*") else { continue }

                let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                guard parts.count >= 2, parts[1] == "device" else { continue }

                let serial = parts[0]
                var name = "Android Device"

                if let modelPart = parts.first(where: { $0.starts(with: "model:") }) {
                    name = String(modelPart.dropFirst(6)).replacingOccurrences(of: "_", with: " ")
                }

                androidDevices.append(ConnectedDevice(
                    id: serial,
                    name: name,
                    platform: .android,
                    adbSerial: serial
                ))
            }

            await MainActor.run { [weak self] in
                let ios = self?.devices.filter { $0.platform == .iOS } ?? []
                self?.devices = ios + androidDevices
            }
        }
    }

    func installAndroidTools() async {
        let brewPaths = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
        guard let brewPath = brewPaths.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            statusMessage = "Homebrew is required. Install from https://brew.sh first."
            return
        }

        isInstalling = true
        statusMessage = "Installing scrcpy & ADB via Homebrew... This may take a few minutes."

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global().async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: brewPath)
                process.arguments = ["install", "scrcpy"]
                process.standardOutput = Pipe()
                process.standardError = Pipe()
                try? process.run()
                process.waitUntilExit()
                continuation.resume()
            }
        }

        findTools()
        isInstalling = false

        if scrcpyAvailable && adbAvailable {
            statusMessage = "Installed successfully! Connect an Android device to get started."
            startMonitoring()
        } else if adbAvailable {
            statusMessage = "ADB installed but scrcpy failed. Try: brew install scrcpy"
        } else {
            statusMessage = "Installation failed. Try running: brew install scrcpy"
        }
    }

    nonisolated static func runCommand(_ path: String, arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        try? process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
