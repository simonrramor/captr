import Foundation

/// An engine that can translate text from one language to another. Providers
/// encapsulate both fast on-device translation (Apple) and cloud LLM-based
/// translation (Claude). See `AppleTranslationProvider` and
/// `ClaudeTranslationProvider` for concrete implementations.
@MainActor
protocol TranslationProvider {
    /// Human-readable name surfaced in the popup (e.g. "Apple", "Claude Haiku 4.5").
    var displayName: String { get }

    /// Optional warm-up hook invoked while the user is still selecting the
    /// capture area, hiding any one-time setup cost behind their input.
    func prewarm()

    /// Translate `text` from `source` to `target`. Providers may treat `source`
    /// as a hint (Claude auto-detects regardless) or a hard requirement (Apple's
    /// Translation framework needs an explicit pair).
    func translate(_ text: String, from source: Locale.Language, to target: Locale.Language) async throws -> String
}

extension TranslationProvider {
    func prewarm() {}
}

/// Errors a provider can surface to the UI with friendlier messaging than raw
/// `localizedDescription` from system frameworks.
enum TranslationProviderError: LocalizedError {
    case missingAPIKey
    case invalidAPIKey
    case rateLimited
    case network(String)
    case serverError(Int, String?)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Add your Anthropic API key in Settings → Translation."
        case .invalidAPIKey:
            return "The Anthropic API key was rejected. Check it in Settings → Translation."
        case .rateLimited:
            return "Anthropic rate limit hit. Wait a moment and try again."
        case .network(let detail):
            return "Network error: \(detail)"
        case .serverError(let code, let detail):
            if let detail { return "Translation service error (\(code)): \(detail)" }
            return "Translation service error (\(code))."
        case .emptyResponse:
            return "The translator returned an empty response."
        }
    }
}
