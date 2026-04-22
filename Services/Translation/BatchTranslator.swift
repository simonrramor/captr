import Foundation

/// A translator that can process many strings in a single call. Batching lets
/// the in-place translation pipeline translate every OCR segment in one API
/// round-trip instead of N, which matters for UI screenshots with 20+ labels.
/// Falls back to per-item concurrent translation handled at the
/// `TranslationService` layer if a batch run fails structurally (e.g. the
/// model returns fewer segments than it was asked for).
@MainActor
protocol BatchTranslator {
    func translateBatch(_ strings: [String], from source: Locale.Language, to target: Locale.Language) async throws -> [String]
}

enum BatchTranslationError: Error {
    /// The model returned a different number of segments than we sent. The
    /// facade catches this and falls back to per-item translation.
    case countMismatch(expected: Int, got: Int)
}
