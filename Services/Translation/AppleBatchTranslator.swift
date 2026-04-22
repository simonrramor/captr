import Foundation

/// Apple's Translation framework has no batch endpoint, so this "batch"
/// translator just fans out to the single-string `AppleTranslationProvider`
/// across a `TaskGroup`. Concurrency is capped so we don't hammer the
/// on-device session with dozens of simultaneous requests, which empirically
/// makes the hidden hosting view churn through configurations badly.
@MainActor
final class AppleBatchTranslator: BatchTranslator {
    private let provider: AppleTranslationProvider
    private let maxConcurrency: Int

    init(provider: AppleTranslationProvider, maxConcurrency: Int = 6) {
        self.provider = provider
        self.maxConcurrency = maxConcurrency
    }

    func translateBatch(_ strings: [String], from source: Locale.Language, to target: Locale.Language) async throws -> [String] {
        guard !strings.isEmpty else { return [] }

        var results = Array(repeating: "", count: strings.count)

        try await withThrowingTaskGroup(of: (Int, String).self) { group in
            var next = 0
            let limit = min(maxConcurrency, strings.count)
            let provider = self.provider

            // Seed the group with the first `limit` tasks.
            for _ in 0..<limit {
                let idx = next
                next += 1
                group.addTask { @MainActor in
                    let translated = try await provider.translate(strings[idx], from: source, to: target)
                    return (idx, translated)
                }
            }

            // As each finishes, kick off the next one.
            while let (idx, translated) = try await group.next() {
                results[idx] = translated
                if next < strings.count {
                    let taskIdx = next
                    next += 1
                    group.addTask { @MainActor in
                        let t = try await provider.translate(strings[taskIdx], from: source, to: target)
                        return (taskIdx, t)
                    }
                }
            }
        }

        return results
    }
}
