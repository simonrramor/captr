import Foundation

/// Translates via Anthropic's Messages API. Tuned for OCR-noisy input: the
/// system prompt tells the model to infer meaning despite missing accents,
/// run-together words, or dropped characters, and to render idioms naturally
/// rather than literally.
@MainActor
final class ClaudeTranslationProvider: TranslationProvider {
    private let settings: TranslationSettings
    private let session: URLSession

    init(settings: TranslationSettings, session: URLSession = .shared) {
        self.settings = settings
        self.session = session
    }

    var displayName: String {
        "Claude \(settings.claudeModel.displayName)"
    }

    func translate(_ text: String, from source: Locale.Language, to target: Locale.Language) async throws -> String {
        guard let apiKey = settings.claudeAPIKey, !apiKey.isEmpty else {
            throw TranslationProviderError.missingAPIKey
        }

        let sourceName = Locale.current.localizedString(forLanguageCode: source.maximalIdentifier) ?? source.maximalIdentifier
        let targetName = Locale.current.localizedString(forLanguageCode: target.maximalIdentifier) ?? target.maximalIdentifier

        let system = """
        You translate text for a screen-capture tool. The input comes from OCR
        so it often contains noise: missing accents, run-together words
        (\"ami\" instead of \"a mi\"), dropped punctuation, or spurious line
        breaks. Infer the intended meaning and translate naturally.

        Rules:
        - Translate into \(targetName).
        - The source is likely \(sourceName), but trust the text if it's
          actually another language.
        - Render idioms idiomatically, not literally. For example, Spanish
          \"la verdad\" at the start of a sentence is usually \"to be honest\",
          not \"the truth\".
        - Preserve tone and register (casual stays casual, formal stays formal).
        - Do not add commentary, explanations, quotes, or language labels.
          Return only the translated text.
        """

        let body: [String: Any] = [
            "model": settings.claudeModel.apiIdentifier,
            "max_tokens": 2048,
            "system": system,
            "messages": [
                ["role": "user", "content": text]
            ]
        ]

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw TranslationProviderError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw TranslationProviderError.network("No HTTP response")
        }

        switch http.statusCode {
        case 200:
            break
        case 401, 403:
            throw TranslationProviderError.invalidAPIKey
        case 429:
            throw TranslationProviderError.rateLimited
        default:
            let detail = Self.extractErrorMessage(from: data)
            throw TranslationProviderError.serverError(http.statusCode, detail)
        }

        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let content = json["content"] as? [[String: Any]],
            let firstText = content.first(where: { ($0["type"] as? String) == "text" })?["text"] as? String
        else {
            throw TranslationProviderError.emptyResponse
        }

        let trimmed = firstText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TranslationProviderError.emptyResponse }
        return trimmed
    }

    private static func extractErrorMessage(from data: Data) -> String? {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let error = json["error"] as? [String: Any],
            let message = error["message"] as? String
        else { return nil }
        return message
    }
}
