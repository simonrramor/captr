import Foundation

/// Facade that routes `translate` calls to whichever provider the user picked
/// in Settings. Providers are held for the lifetime of the service so Apple's
/// hidden hosting panel and Claude's URLSession stay warm between calls.
@MainActor
final class TranslationService {
    let settings: TranslationSettings
    lazy var apple = AppleTranslationProvider()
    private lazy var claude = ClaudeTranslationProvider(settings: settings)

    init(settings: TranslationSettings) {
        self.settings = settings
    }

    /// Name of the engine that will run the next translation — safe to read on
    /// the main thread before awaiting `translate`. The popup surfaces this so
    /// the user knows whether they're looking at on-device or cloud output.
    var currentEngineName: String {
        activeProvider.displayName
    }

    func prewarm() {
        activeProvider.prewarm()
    }

    func translate(_ text: String, from source: Locale.Language, to target: Locale.Language) async throws -> String {
        try await activeProvider.translate(text, from: source, to: target)
    }

    private var activeProvider: TranslationProvider {
        switch settings.engine {
        case .apple: return apple
        case .claude: return claude
        }
    }
}
