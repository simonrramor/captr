import AppKit
import AVFoundation
import SwiftUI

@MainActor
class DeviceMirrorWindow {
    private var window: NSWindow?
    private var displayTimer: Timer?
    private var iosMirror: IOSDeviceMirror?
    private var androidMirror: AndroidDeviceMirror?
    private weak var appState: AppState?

    // MARK: - iOS Mirror Window

    func openIOSMirrorWindow(session: AVCaptureSession, deviceName: String, mirror: IOSDeviceMirror, appState: AppState) {
        closeWindow()

        self.iosMirror = mirror
        self.appState = appState

        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspect
        previewLayer.backgroundColor = NSColor.black.cgColor

        let hostView = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 700))
        hostView.wantsLayer = true
        hostView.layer = previewLayer

        let controlsHeight: CGFloat = 50

        let controlsView = makeControlsView(width: 400, height: controlsHeight, isIOS: true)

        let contentHeight = 700 + controlsHeight
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: contentHeight))

        hostView.frame = NSRect(x: 0, y: controlsHeight, width: 400, height: 700)
        hostView.autoresizingMask = [.width, .height]
        containerView.addSubview(hostView)
        containerView.addSubview(controlsView)

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: contentHeight),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        win.title = "Mirror - \(deviceName)"
        win.contentView = containerView
        win.center()
        win.setFrameAutosaveName("IOSMirrorWindow")

        window = win
        win.makeKeyAndOrderFront(nil)

        // #region agent log
        debugLog("iOS mirror window opened", ["sessionRunning": session.isRunning, "deviceName": deviceName])
        // #endregion
    }

    // MARK: - Android Mirror Window

    func openAndroidMirrorWindow(mirror: AndroidDeviceMirror, appState: AppState) {
        closeWindow()

        self.androidMirror = mirror
        self.appState = appState

        let deviceRes = mirror.deviceResolution
        let aspect = deviceRes.width / deviceRes.height
        let windowHeight: CGFloat = 700
        let windowWidth: CGFloat = windowHeight * aspect
        let controlsHeight: CGFloat = 80

        let imageView = NSImageView(frame: NSRect(x: 0, y: controlsHeight, width: windowWidth, height: windowHeight))
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.backgroundColor = NSColor.black.cgColor
        imageView.autoresizingMask = [.width, .height]
        if let frame = mirror.currentFrame {
            imageView.image = frame
        }

        let controlsView = makeControlsView(width: windowWidth, height: controlsHeight, isIOS: false)

        let contentHeight = windowHeight + controlsHeight
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: windowWidth, height: contentHeight))
        containerView.addSubview(imageView)
        containerView.addSubview(controlsView)

        // Click/drag handler on image view
        let clickView = AndroidClickView(frame: NSRect(x: 0, y: controlsHeight, width: windowWidth, height: windowHeight))
        clickView.autoresizingMask = [.width, .height]
        clickView.mirror = mirror
        containerView.addSubview(clickView)

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: windowWidth, height: contentHeight),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        win.title = "Mirror - \(mirror.mirroringDeviceName)"
        win.contentView = containerView
        win.center()
        win.setFrameAutosaveName("AndroidMirrorWindow")
        win.minSize = NSSize(width: 200, height: 400)

        window = win
        win.makeKeyAndOrderFront(nil)

        // Start display timer to update the NSImageView from currentFrame
        displayTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak mirror, weak imageView] _ in
            guard let mirror = mirror, let imageView = imageView else { return }
            Task { @MainActor in
                if let frame = mirror.currentFrame {
                    imageView.image = frame
                }
            }
        }

        // #region agent log
        debugLog("Android mirror window opened", ["deviceName": mirror.mirroringDeviceName,
                                                    "resolution": "\(deviceRes.width)x\(deviceRes.height)"])
        // #endregion
    }

    func closeWindow() {
        if let timer = displayTimer {
            timer.invalidate()
            displayTimer = nil
        }
        if let win = window {
            win.close()
            window = nil
        }
        iosMirror = nil
        androidMirror = nil
    }

    var isOpen: Bool {
        window?.isVisible == true
    }

    // MARK: - Controls Builder

    private func makeControlsView(width: CGFloat, height: CGFloat, isIOS: Bool) -> NSView {
        let controlsView = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        controlsView.wantsLayer = true
        controlsView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        controlsView.autoresizingMask = [.width]

        var xOffset: CGFloat = 10

        if !isIOS {
            // Android navigation buttons
            let backBtn = makeButton(title: "◀", x: xOffset, y: height - 38, width: 40)
            backBtn.target = self
            backBtn.action = #selector(androidNavBack(_:))
            controlsView.addSubview(backBtn)
            xOffset += 45

            let homeBtn = makeButton(title: "●", x: xOffset, y: height - 38, width: 40)
            homeBtn.target = self
            homeBtn.action = #selector(androidNavHome(_:))
            controlsView.addSubview(homeBtn)
            xOffset += 45

            let recentsBtn = makeButton(title: "▪▪", x: xOffset, y: height - 38, width: 40)
            recentsBtn.target = self
            recentsBtn.action = #selector(androidNavRecents(_:))
            controlsView.addSubview(recentsBtn)
        }

        // Record button
        let recordBtn = makeButton(title: "Record", x: 10, y: 8, color: .systemRed)
        recordBtn.target = self
        recordBtn.action = #selector(recordTapped(_:))
        controlsView.addSubview(recordBtn)

        // Screenshot button
        let ssBtn = makeButton(title: "Screenshot", x: 105, y: 8, color: .systemBlue)
        ssBtn.target = self
        ssBtn.action = #selector(screenshotTapped(_:))
        controlsView.addSubview(ssBtn)

        // Disconnect button
        let disconnectBtn = makeButton(title: "Disconnect", x: 210, y: 8, color: .systemGray)
        disconnectBtn.target = self
        disconnectBtn.action = #selector(disconnectTapped(_:))
        controlsView.addSubview(disconnectBtn)

        return controlsView
    }

    private func makeButton(title: String, x: CGFloat, y: CGFloat, width: CGFloat = 90, color: NSColor = .controlTextColor) -> NSButton {
        let button = NSButton(frame: NSRect(x: x, y: y, width: width, height: 28))
        button.title = title
        button.bezelStyle = .rounded
        button.contentTintColor = color
        button.font = .systemFont(ofSize: 12, weight: .medium)
        return button
    }

    // MARK: - Button Actions

    @objc private func recordTapped(_ sender: NSButton) {
        if let mirror = iosMirror {
            if mirror.isRecording {
                Task {
                    let url = await mirror.stopRecording()
                    if let url = url {
                        await appState?.mediaLibrary.addRecording(at: url)
                        appState?.showSavedNotification("Device recording saved")
                    }
                }
                sender.title = "Record"
            } else {
                mirror.startRecording()
                sender.title = "Stop"
            }
        } else if let mirror = androidMirror {
            if mirror.isRecording {
                Task {
                    if let url = await mirror.stopRecording() {
                        await appState?.mediaLibrary.addRecording(at: url)
                        appState?.showSavedNotification("Device recording saved")
                    }
                }
                sender.title = "Record"
            } else {
                mirror.startRecording()
                sender.title = "Stop"
            }
        }
    }

    @objc private func screenshotTapped(_ sender: NSButton) {
        var image: NSImage?
        if let mirror = iosMirror {
            image = mirror.takeScreenshot()
        } else if let mirror = androidMirror {
            image = mirror.takeScreenshot()
        }
        if let image = image {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects([image])
            appState?.showSavedNotification("Screenshot copied to clipboard")
        }
    }

    @objc private func disconnectTapped(_ sender: NSButton) {
        iosMirror?.stopMirroring()
        androidMirror?.stopMirroring()
        closeWindow()
    }

    @objc private func androidNavBack(_ sender: NSButton) {
        androidMirror?.sendBack()
    }

    @objc private func androidNavHome(_ sender: NSButton) {
        androidMirror?.sendHome()
    }

    @objc private func androidNavRecents(_ sender: NSButton) {
        androidMirror?.sendRecents()
    }

    // #region agent log
    private func debugLog(_ message: String, _ data: [String: Any] = [:]) {
        let logPath = NSString(string: "~/Screen recorder/.cursor/debug.log").expandingTildeInPath
        let payload: [String: Any] = [
            "timestamp": Int(Date().timeIntervalSince1970 * 1000),
            "location": "DeviceMirrorWindow",
            "message": message,
            "data": data
        ]
        if let jsonData = try? JSONSerialization.data(withJSONObject: payload),
           let jsonStr = String(data: jsonData, encoding: .utf8) {
            let line = jsonStr + "\n"
            if let handle = FileHandle(forWritingAtPath: logPath) {
                handle.seekToEndOfFile()
                handle.write(line.data(using: .utf8)!)
                handle.closeFile()
            } else {
                FileManager.default.createFile(atPath: logPath, contents: line.data(using: .utf8))
            }
        }
    }
    // #endregion
}

// MARK: - Android Click/Drag View

class AndroidClickView: NSView {
    weak var mirror: AndroidDeviceMirror?
    private var dragStartPoint: NSPoint = .zero

    override func mouseDown(with event: NSEvent) {
        dragStartPoint = convert(event.locationInWindow, from: nil)
    }

    override func mouseUp(with event: NSEvent) {
        let endPoint = convert(event.locationInWindow, from: nil)
        guard let mirror = mirror else { return }

        let viewSize = bounds.size
        let start = CGPoint(x: dragStartPoint.x, y: viewSize.height - dragStartPoint.y)
        let end = CGPoint(x: endPoint.x, y: viewSize.height - endPoint.y)

        let dist = sqrt(pow(end.x - start.x, 2) + pow(end.y - start.y, 2))

        Task { @MainActor in
            if dist < 15 {
                mirror.handleTap(at: start, viewSize: viewSize)
            } else {
                mirror.handleSwipe(from: start, to: end, viewSize: viewSize)
            }
        }
    }
}
