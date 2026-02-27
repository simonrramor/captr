import Foundation
import ScreenCaptureKit
import AVFoundation
import Combine

@MainActor
class CaptureEngine: NSObject, ObservableObject {
    @Published var state: RecordingState = .idle
    @Published var recordingDuration: TimeInterval = 0
    @Published var availableDisplays: [SCDisplay] = []
    @Published var availableWindows: [SCWindow] = []
    @Published var errorMessage: String?

    private var stream: SCStream?
    private var streamOutput: CaptureStreamOutput?
    private var durationTimer: Timer?
    private var recordingStartDate: Date?
    private let audioManager = AudioManager()
    private var outputURL: URL?

    var configuration = CaptureConfiguration()

    func refreshAvailableContent() async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            availableDisplays = content.displays
            availableWindows = content.windows.filter { $0.isOnScreen && $0.title?.isEmpty == false }
            if configuration.selectedDisplay == nil {
                configuration.selectedDisplay = content.displays.first
            }
        } catch {
            errorMessage = "Failed to get screen content: \(error.localizedDescription)"
        }
    }

    func startRecording() async {
        guard state == .idle else { return }
        state = .preparing
        errorMessage = nil

        do {
            try await refreshIfNeeded()

            let filter = try createContentFilter()
            let streamConfig = createStreamConfiguration()

            let outputDir = MediaLibraryManager.recordingsDirectory
            try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

            let fileName = "Screen Recording \(Date().screenRecorderFileName).mp4"
            let url = outputDir.appendingPathComponent(fileName)
            outputURL = url

            let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
            writer.shouldOptimizeForNetworkUse = true

            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: streamConfig.width,
                AVVideoHeightKey: streamConfig.height,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: 8_000_000,
                    AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
                ]
            ]

            let vInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            vInput.expectsMediaDataInRealTime = true
            writer.add(vInput)

            var aInput: AVAssetWriterInput?
            if configuration.captureSystemAudio || configuration.captureMicrophone {
                let audioSettings: [String: Any] = [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: 48000,
                    AVNumberOfChannelsKey: 2,
                    AVEncoderBitRateKey: 192000
                ]
                let audioWriterInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
                audioWriterInput.expectsMediaDataInRealTime = true
                writer.add(audioWriterInput)
                aInput = audioWriterInput
            }

            let bufferWriter = BufferWriter(assetWriter: writer, videoInput: vInput, audioInput: aInput)
            let output = CaptureStreamOutput(bufferWriter: bufferWriter)

            let captureStream = SCStream(filter: filter, configuration: streamConfig, delegate: output)
            try captureStream.addStreamOutput(output, type: .screen, sampleHandlerQueue: .global(qos: .userInteractive))

            if configuration.captureSystemAudio {
                try captureStream.addStreamOutput(output, type: .audio, sampleHandlerQueue: .global(qos: .userInteractive))
            }

            try await captureStream.startCapture()
            stream = captureStream
            streamOutput = output

            if configuration.captureMicrophone {
                audioManager.startMicrophoneCapture { [weak bufferWriter] sampleBuffer in
                    bufferWriter?.appendAudio(sampleBuffer)
                }
            }

            state = .recording
            recordingStartDate = Date()
            startDurationTimer()

        } catch {
            state = .idle
            errorMessage = "Failed to start recording: \(error.localizedDescription)"
        }
    }

    func stopRecording() async -> URL? {
        guard state.isActive else { return nil }
        state = .stopping

        stopDurationTimer()
        audioManager.stopMicrophoneCapture()

        if let stream = stream {
            do {
                try await stream.stopCapture()
            } catch {
                print("Error stopping stream: \(error)")
            }
        }
        stream = nil

        if let output = streamOutput {
            await output.bufferWriter.finishWriting()
        }
        streamOutput = nil

        let url = outputURL
        cleanup()
        return url
    }

    func cancelRecording() async {
        stopDurationTimer()
        audioManager.stopMicrophoneCapture()

        if let stream = stream {
            try? await stream.stopCapture()
        }
        stream = nil

        streamOutput?.bufferWriter.cancelWriting()
        streamOutput = nil

        if let url = outputURL {
            try? FileManager.default.removeItem(at: url)
        }

        cleanup()
    }

    // MARK: - Private Helpers

    private func refreshIfNeeded() async throws {
        if availableDisplays.isEmpty {
            await refreshAvailableContent()
        }
    }

    private func createContentFilter() throws -> SCContentFilter {
        switch configuration.mode {
        case .fullScreen:
            guard let display = configuration.selectedDisplay ?? availableDisplays.first else {
                throw CaptureError.noDisplay
            }
            return SCContentFilter(display: display, excludingWindows: [])

        case .window:
            guard let window = configuration.selectedWindow else {
                throw CaptureError.noWindow
            }
            return SCContentFilter(desktopIndependentWindow: window)

        case .area:
            guard let display = configuration.selectedDisplay ?? availableDisplays.first else {
                throw CaptureError.noDisplay
            }
            return SCContentFilter(display: display, excludingWindows: [])
        }
    }

    private func createStreamConfiguration() -> SCStreamConfiguration {
        let config = SCStreamConfiguration()

        if let display = configuration.selectedDisplay {
            switch configuration.resolution {
            case .native:
                config.width = Int(display.width) * 2
                config.height = Int(display.height) * 2
            case .hd1080:
                config.width = 1920
                config.height = 1080
            case .hd720:
                config.width = 1280
                config.height = 720
            }
        }

        if let area = configuration.selectedArea, configuration.mode == .area {
            config.sourceRect = area
            config.width = min(Int(area.width) * 2, config.width)
            config.height = min(Int(area.height) * 2, config.height)
        }

        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(configuration.frameRate))
        config.showsCursor = configuration.showCursor
        config.capturesAudio = configuration.captureSystemAudio
        config.pixelFormat = kCVPixelFormatType_32BGRA

        return config
    }

    private func startDurationTimer() {
        durationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, let start = self.recordingStartDate else { return }
                self.recordingDuration = Date().timeIntervalSince(start)
            }
        }
    }

    private func stopDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
    }

    private func cleanup() {
        state = .idle
        recordingDuration = 0
        recordingStartDate = nil
        outputURL = nil
    }
}

// MARK: - Buffer Writer (thread-safe, works on capture queue)

class BufferWriter: @unchecked Sendable {
    private let assetWriter: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let audioInput: AVAssetWriterInput?
    private let lock = NSLock()
    private var startTime: CMTime?
    private var sessionStarted = false
    private var isFinished = false

    init(assetWriter: AVAssetWriter, videoInput: AVAssetWriterInput, audioInput: AVAssetWriterInput?) {
        self.assetWriter = assetWriter
        self.videoInput = videoInput
        self.audioInput = audioInput
    }

    func appendVideo(_ sampleBuffer: CMSampleBuffer) {
        lock.lock()
        defer { lock.unlock() }

        guard !isFinished, assetWriter.status != .failed else { return }

        if !sessionStarted {
            assetWriter.startWriting()
            let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            assetWriter.startSession(atSourceTime: timestamp)
            startTime = timestamp
            sessionStarted = true
        }

        guard videoInput.isReadyForMoreMediaData else { return }
        videoInput.append(sampleBuffer)
    }

    func appendAudio(_ sampleBuffer: CMSampleBuffer) {
        lock.lock()
        defer { lock.unlock() }

        guard !isFinished, sessionStarted, assetWriter.status != .failed else { return }
        guard let audioInput = audioInput, audioInput.isReadyForMoreMediaData else { return }
        audioInput.append(sampleBuffer)
    }

    func finishWriting() async {
        lock.lock()
        guard !isFinished, sessionStarted else {
            lock.unlock()
            return
        }
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

// MARK: - Stream Output Delegate

class CaptureStreamOutput: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let bufferWriter: BufferWriter

    init(bufferWriter: BufferWriter) {
        self.bufferWriter = bufferWriter
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard sampleBuffer.isValid else { return }

        switch type {
        case .screen:
            bufferWriter.appendVideo(sampleBuffer)
        case .audio:
            bufferWriter.appendAudio(sampleBuffer)
        case .microphone:
            bufferWriter.appendAudio(sampleBuffer)
        @unknown default:
            break
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("Stream stopped with error: \(error.localizedDescription)")
    }
}

// MARK: - Errors

enum CaptureError: LocalizedError {
    case noDisplay
    case noWindow
    case noArea
    case writingFailed(String)

    var errorDescription: String? {
        switch self {
        case .noDisplay: return "No display selected for capture."
        case .noWindow: return "No window selected for capture."
        case .noArea: return "No area selected for capture."
        case .writingFailed(let msg): return "Writing failed: \(msg)"
        }
    }
}
