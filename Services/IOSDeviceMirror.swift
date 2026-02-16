import Foundation
import SwiftUI
import AVFoundation
import AppKit
import CoreImage

// Thread-safe buffer writer for device mirror recording
class MirrorBufferWriter: @unchecked Sendable {
    private let assetWriter: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let audioInput: AVAssetWriterInput?
    private let lock = NSLock()
    private var sessionStarted = false
    private var isFinished = false

    init(assetWriter: AVAssetWriter, videoInput: AVAssetWriterInput, audioInput: AVAssetWriterInput?) {
        self.assetWriter = assetWriter
        self.videoInput = videoInput
        self.audioInput = audioInput
    }

    func appendVideo(_ buffer: CMSampleBuffer) {
        lock.lock()
        defer { lock.unlock() }
        guard !isFinished, assetWriter.status != .failed else { return }

        if !sessionStarted {
            assetWriter.startWriting()
            assetWriter.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(buffer))
            sessionStarted = true
        }

        guard videoInput.isReadyForMoreMediaData else { return }
        videoInput.append(buffer)
    }

    func appendAudio(_ buffer: CMSampleBuffer) {
        lock.lock()
        defer { lock.unlock() }
        guard !isFinished, sessionStarted, assetWriter.status != .failed else { return }
        guard let audioInput = audioInput, audioInput.isReadyForMoreMediaData else { return }
        audioInput.append(buffer)
    }

    func finishWriting() async {
        lock.lock()
        guard !isFinished, sessionStarted else { lock.unlock(); return }
        isFinished = true
        lock.unlock()

        videoInput.markAsFinished()
        audioInput?.markAsFinished()

        if assetWriter.status == .writing {
            await assetWriter.finishWriting()
        }
    }

    func cancelWriting() {
        lock.lock()
        isFinished = true
        lock.unlock()
        assetWriter.cancelWriting()
    }
}

// Capture delegate running on the background capture queue
class MirrorCaptureHandler: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private var bufferWriter: MirrorBufferWriter?
    private var recording = false
    private let lock = NSLock()
    private var latestCGImage: CGImage?
    private let ciContext = CIContext()
    private var dimensionsCallback: ((CGSize) -> Void)?
    private var hasSentDimensions = false
    // #region agent log
    private var frameCount = 0
    // #endregion

    func setDimensionsCallback(_ callback: @escaping (CGSize) -> Void) {
        dimensionsCallback = callback
    }

    func startRecording(writer: MirrorBufferWriter) {
        lock.lock()
        bufferWriter = writer
        recording = true
        lock.unlock()
    }

    func stopRecording() {
        lock.lock()
        recording = false
        bufferWriter = nil
        lock.unlock()
    }

    func getLatestFrame() -> NSImage? {
        lock.lock()
        let img = latestCGImage
        lock.unlock()
        guard let cg = img else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard sampleBuffer.isValid else { return }

        // #region agent log
        frameCount += 1
        if frameCount <= 3 || frameCount % 100 == 0 {
            let logPath = NSString(string: "~/Screen recorder/.cursor/debug.log").expandingTildeInPath
            let hasImageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) != nil
            let payload: [String: Any] = [
                "timestamp": Int(Date().timeIntervalSince1970 * 1000),
                "location": "MirrorCaptureHandler.captureOutput",
                "message": "iOS frame received",
                "data": ["hypothesisId": "H-A", "frameCount": frameCount, "hasImageBuffer": hasImageBuffer,
                         "isValid": sampleBuffer.isValid]
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

        lock.lock()
        let isRecording = recording
        let writer = bufferWriter
        lock.unlock()

        if isRecording {
            writer?.appendVideo(sampleBuffer)
        }

        // Store latest frame for screenshots
        if let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            let ciImage = CIImage(cvImageBuffer: imageBuffer)
            if let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) {
                lock.lock()
                latestCGImage = cgImage
                lock.unlock()
            }
        }

        // Report video dimensions once
        if !hasSentDimensions, let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer) {
            let dims = CMVideoFormatDescriptionGetDimensions(formatDesc)
            hasSentDimensions = true
            let size = CGSize(width: CGFloat(dims.width), height: CGFloat(dims.height))
            dimensionsCallback?(size)
        }
    }
}

@MainActor
class IOSDeviceMirror: ObservableObject {
    @Published var isMirroring = false
    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var errorMessage: String?
    @Published var videoDimensions: CGSize = .zero
    @Published var mirroringDeviceName: String = ""

    private(set) var captureSession: AVCaptureSession?
    private var captureHandler: MirrorCaptureHandler?
    private var bufferWriter: MirrorBufferWriter?
    private var durationTimer: Timer?
    private var recordingStartDate: Date?
    private var outputURL: URL?
    private let outputQueue = DispatchQueue(label: "com.screenrecorder.ios-mirror", qos: .userInteractive)

    // #region agent log
    private func debugLog(_ message: String, _ data: [String: Any] = [:]) {
        let logPath = NSString(string: "~/Screen recorder/.cursor/debug.log").expandingTildeInPath
        var payload: [String: Any] = [
            "timestamp": Int(Date().timeIntervalSince1970 * 1000),
            "location": "IOSDeviceMirror.swift",
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

    func startMirroring(device: AVCaptureDevice) {
        guard !isMirroring else { return }
        errorMessage = nil
        mirroringDeviceName = device.localizedName

        // #region agent log
        debugLog("startMirroring called", [
            "hypothesisId": "H-A",
            "deviceName": device.localizedName,
            "deviceUniqueID": device.uniqueID,
            "deviceModelID": device.modelID,
            "isConnected": device.isConnected,
            "hasMediaType": device.hasMediaType(.video)
        ])
        // #endregion

        do {
            let session = AVCaptureSession()
            session.sessionPreset = .high

            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else {
                // #region agent log
                debugLog("Cannot add device input", ["hypothesisId": "H-A"])
                // #endregion
                errorMessage = "Cannot add device input"
                return
            }
            session.addInput(input)

            let handler = MirrorCaptureHandler()
            handler.setDimensionsCallback { [weak self] size in
                // #region agent log
                self?.debugLog("Got video dimensions from delegate", [
                    "hypothesisId": "H-A",
                    "width": size.width,
                    "height": size.height
                ])
                // #endregion
                Task { @MainActor [weak self] in
                    self?.videoDimensions = size
                }
            }

            let videoOut = AVCaptureVideoDataOutput()
            videoOut.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            videoOut.alwaysDiscardsLateVideoFrames = true
            videoOut.setSampleBufferDelegate(handler, queue: outputQueue)

            guard session.canAddOutput(videoOut) else {
                // #region agent log
                debugLog("Cannot add video output", ["hypothesisId": "H-A"])
                // #endregion
                errorMessage = "Cannot add video output"
                return
            }
            session.addOutput(videoOut)

            captureSession = session
            captureHandler = handler

            // #region agent log
            debugLog("About to call session.startRunning()", [
                "hypothesisId": "H-A",
                "sessionIsRunning": session.isRunning,
                "inputCount": session.inputs.count,
                "outputCount": session.outputs.count
            ])
            // #endregion

            session.startRunning()

            // #region agent log
            debugLog("After session.startRunning()", [
                "hypothesisId": "H-A",
                "sessionIsRunning": session.isRunning
            ])
            // #endregion

            isMirroring = true

        } catch {
            // #region agent log
            debugLog("Exception in startMirroring", ["hypothesisId": "H-A", "error": error.localizedDescription])
            // #endregion
            errorMessage = "Failed to start mirroring: \(error.localizedDescription)"
        }
    }

    func stopMirroring() {
        if isRecording {
            captureHandler?.stopRecording()
            Task { await bufferWriter?.finishWriting() }
            isRecording = false
            stopDurationTimer()
        }

        captureSession?.stopRunning()
        captureSession = nil
        captureHandler = nil
        bufferWriter = nil
        isMirroring = false
        videoDimensions = .zero
        mirroringDeviceName = ""
    }

    func startRecording() {
        guard isMirroring, !isRecording else { return }

        do {
            let outputDir = MediaLibraryManager.recordingsDirectory
            try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

            let fileName = "iOS Device \(Date().screenRecorderFileName).mp4"
            let url = outputDir.appendingPathComponent(fileName)
            outputURL = url

            let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)

            let w = videoDimensions.width > 0 ? Int(videoDimensions.width) : 1080
            let h = videoDimensions.height > 0 ? Int(videoDimensions.height) : 1920

            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: w,
                AVVideoHeightKey: h,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: 8_000_000,
                    AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
                ]
            ]

            let vInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            vInput.expectsMediaDataInRealTime = true
            writer.add(vInput)

            let bw = MirrorBufferWriter(assetWriter: writer, videoInput: vInput, audioInput: nil)
            bufferWriter = bw
            captureHandler?.startRecording(writer: bw)

            isRecording = true
            recordingStartDate = Date()
            startDurationTimer()

        } catch {
            errorMessage = "Failed to start recording: \(error.localizedDescription)"
        }
    }

    func stopRecording() async -> URL? {
        guard isRecording else { return nil }
        isRecording = false
        stopDurationTimer()

        captureHandler?.stopRecording()
        await bufferWriter?.finishWriting()
        bufferWriter = nil

        let url = outputURL
        outputURL = nil
        return url
    }

    func takeScreenshot() -> NSImage? {
        return captureHandler?.getLatestFrame()
    }

    private func startDurationTimer() {
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, let start = self.recordingStartDate else { return }
                self.recordingDuration = Date().timeIntervalSince(start)
            }
        }
    }

    private func stopDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
        recordingDuration = 0
        recordingStartDate = nil
    }
}

// SwiftUI wrapper for AVCaptureVideoPreviewLayer
struct IOSDevicePreviewView: NSViewRepresentable {
    let session: AVCaptureSession

    class PreviewNSView: NSView {
        override func makeBackingLayer() -> CALayer {
            let layer = AVCaptureVideoPreviewLayer()
            layer.videoGravity = .resizeAspect
            layer.backgroundColor = NSColor.black.cgColor
            return layer
        }

        override init(frame: CGRect) {
            super.init(frame: frame)
            wantsLayer = true
        }

        required init?(coder: NSCoder) { fatalError() }

        var previewLayer: AVCaptureVideoPreviewLayer? {
            layer as? AVCaptureVideoPreviewLayer
        }
    }

    func makeNSView(context: Context) -> PreviewNSView {
        let view = PreviewNSView(frame: .zero)
        view.previewLayer?.session = session
        // #region agent log
        let logPath = NSString(string: "~/Screen recorder/.cursor/debug.log").expandingTildeInPath
        let payload: [String: Any] = [
            "timestamp": Int(Date().timeIntervalSince1970 * 1000),
            "location": "IOSDevicePreviewView.makeNSView",
            "message": "Preview NSView created",
            "data": ["hypothesisId": "H-B", "hasPreviewLayer": view.previewLayer != nil,
                     "sessionIsRunning": session.isRunning, "viewFrame": "\(view.frame)"]
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
        // #endregion
        return view
    }

    func updateNSView(_ nsView: PreviewNSView, context: Context) {
        nsView.previewLayer?.session = session
        // #region agent log
        let logPath = NSString(string: "~/Screen recorder/.cursor/debug.log").expandingTildeInPath
        let payload: [String: Any] = [
            "timestamp": Int(Date().timeIntervalSince1970 * 1000),
            "location": "IOSDevicePreviewView.updateNSView",
            "message": "Preview NSView updated",
            "data": ["hypothesisId": "H-B", "hasPreviewLayer": nsView.previewLayer != nil,
                     "viewBounds": "\(nsView.bounds)", "layerBounds": "\(nsView.previewLayer?.bounds ?? .zero)",
                     "layerFrame": "\(nsView.previewLayer?.frame ?? .zero)"]
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
        // #endregion
    }
}
