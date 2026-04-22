import Foundation

/// Translates an array of OCR segments in a single Claude Messages API call
/// by wrapping each input in an `<s id="N">` sentinel tag. The model is
/// asked to preserve the same tag structure in its response, which lets us
/// deterministically split the output back into per-segment translations.
/// Keeps the system prompt tuned for OCR noise (missing accents, dropped
/// characters, run-together words) shared with `ClaudeTranslationProvider`.
@MainActor
final class ClaudeBatchTranslator: BatchTranslator {
    private let settings: TranslationSettings
    private let session: URLSession

    init(settings: TranslationSettings, session: URLSession = .shared) {
        self.settings = settings
        self.session = session
    }

    func translateBatch(_ strings: [String], from source: Locale.Language, to target: Locale.Language) async throws -> [String] {
        guard !strings.isEmpty else { return [] }
        guard let apiKey = settings.claudeAPIKey, !apiKey.isEmpty else {
            throw TranslationProviderError.missingAPIKey
        }

        let sourceName = Locale.current.localizedString(forLanguageCode: source.maximalIdentifier) ?? source.maximalIdentifier
        let targetName = Locale.current.localizedString(forLanguageCode: target.maximalIdentifier) ?? target.maximalIdentifier

        let system = """
        You translate text for a screen-capture tool. Input is a series of
        <s id="N"> tags, each holding one OCR'd text segment. The OCR is noisy:
        it may have missing accents, run-together words, dropped punctuation,
        or spurious line breaks. Infer meaning and translate naturally.

        Rules:
        - Translate each segment into \(targetName).
        - The source is likely \(sourceName); trust the text if it's actually
          another language.
        - Render idioms idiomatically, not literally.
        - Preserve tone and register.
        - Return EXACTLY the same <s id="N"> tags in the same order, each
          containing only the English translation of that segment.
        - Do not merge or split segments. If a segment is untranslatable or
          already English, return it unchanged inside its tag.
        - No commentary, no extra tags, no whitespace between tags.
        """

        let user = strings.enumerated()
            .map { "<s id=\"\($0.offset + 1)\">\(escape($0.element))</s>" }
            .joined()

        let body: [String: Any] = [
            "model": settings.claudeModel.apiIdentifier,
            "max_tokens": 4096,
            "system": system,
            "messages": [
                ["role": "user", "content": user]
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
        case 200: break
        case 401, 403: throw TranslationProviderError.invalidAPIKey
        case 429: throw TranslationProviderError.rateLimited
        default:
            throw TranslationProviderError.serverError(http.statusCode, Self.extractErrorMessage(from: data))
        }

        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let content = json["content"] as? [[String: Any]],
            let raw = content.first(where: { ($0["type"] as? String) == "text" })?["text"] as? String
        else {
            throw TranslationProviderError.emptyResponse
        }

        let parsed = Self.parseSegments(raw, expected: strings.count)
        if parsed.count != strings.count {
            throw BatchTranslationError.countMismatch(expected: strings.count, got: parsed.count)
        }
        return parsed
    }

    /// Escapes the five XML characters so the model sees unambiguous tag
    /// boundaries. Unescaping on the response isn't needed because the model
    /// renders natural text inside its reply tags.
    private func escape(_ s: String) -> String {
        s
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    private static func parseSegments(_ raw: String, expected: Int) -> [String] {
        // Match `<s id="N">…</s>` where the body can span lines. Lazy match
        // keeps adjacent segments from collapsing into one capture.
        let pattern = #"<s id="(\d+)">([\s\S]*?)</s>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsRaw = raw as NSString
        let matches = regex.matches(in: raw, range: NSRange(location: 0, length: nsRaw.length))

        // Sort by the captured id so out-of-order responses still map correctly.
        let byId: [(Int, String)] = matches.compactMap { match in
            guard match.numberOfRanges >= 3 else { return nil }
            let idString = nsRaw.substring(with: match.range(at: 1))
            let body = nsRaw.substring(with: match.range(at: 2))
            guard let id = Int(idString) else { return nil }
            return (id, unescape(body))
        }

        if byId.count != expected { return byId.map { $0.1 } }
        return byId
            .sorted { $0.0 < $1.0 }
            .map { $0.1 }
    }

    private static func unescape(_ s: String) -> String {
        s
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
