import Foundation
import Vision
import AppKit
import CoreGraphics

@MainActor
class TextCaptureService: ObservableObject {
    @Published var errorMessage: String?

    func captureAndRecognizeArea(_ area: CGRect) async -> String? {
        errorMessage = nil

        // Capture directly using CGWindowListCreateImage for reliable screen coordinates
        guard let cgImage = captureScreenArea(area) else {
            errorMessage = "Failed to capture the selected area"
            return nil
        }

        guard let text = await recognizeText(from: cgImage) else {
            errorMessage = "No text found in the selected area"
            return nil
        }

        return text
    }

    private func captureScreenArea(_ area: CGRect) -> CGImage? {
        // CGWindowListCreateImage uses Core Graphics coordinates (top-left origin)
        // The area from our overlay is already in this coordinate system
        let image = CGWindowListCreateImage(
            area,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution, .boundsIgnoreFraming]
        )
        return image
    }

    private func recognizeText(from cgImage: CGImage) async -> String? {
        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    print("Vision error: \(error)")
                    continuation.resume(returning: nil)
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: nil)
                    return
                }

                let recognizedStrings = observations.compactMap { observation in
                    observation.topCandidates(1).first?.string
                }

                let result = recognizedStrings.joined(separator: "\n")
                continuation.resume(returning: result.isEmpty ? nil : result)
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                print("Vision perform error: \(error)")
                continuation.resume(returning: nil)
            }
        }
    }

    static func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
