import Foundation
import AVFoundation
import CoreMedia

class AudioManager: NSObject {
    private var captureSession: AVCaptureSession?
    private var audioOutput: AVCaptureAudioDataOutput?
    private var bufferHandler: ((CMSampleBuffer) -> Void)?
    private let sessionQueue = DispatchQueue(label: "com.screenrecorder.audio")

    var isMicrophoneActive: Bool {
        captureSession?.isRunning ?? false
    }

    func startMicrophoneCapture(handler: @escaping (CMSampleBuffer) -> Void) {
        bufferHandler = handler

        sessionQueue.async { [weak self] in
            self?.setupCaptureSession()
        }
    }

    func stopMicrophoneCapture() {
        sessionQueue.async { [weak self] in
            self?.captureSession?.stopRunning()
            self?.captureSession = nil
            self?.audioOutput = nil
            self?.bufferHandler = nil
        }
    }

    private func setupCaptureSession() {
        let session = AVCaptureSession()
        session.beginConfiguration()

        guard let microphone = AVCaptureDevice.default(for: .audio) else {
            print("No microphone available")
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: microphone)
            if session.canAddInput(input) {
                session.addInput(input)
            }
        } catch {
            print("Failed to create microphone input: \(error)")
            return
        }

        let output = AVCaptureAudioDataOutput()
        output.setSampleBufferDelegate(self, queue: sessionQueue)

        if session.canAddOutput(output) {
            session.addOutput(output)
        }

        session.commitConfiguration()
        session.startRunning()

        captureSession = session
        audioOutput = output
    }

    static func availableMicrophones() -> [AVCaptureDevice] {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )
        return discoverySession.devices
    }
}

extension AudioManager: AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        bufferHandler?(sampleBuffer)
    }
}
