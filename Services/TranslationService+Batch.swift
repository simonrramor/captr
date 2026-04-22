import Foundation

/// Adds batch translation to the existing `TranslationService` facade. Keeps
/// the single-string API unchanged; callers that don't need batching ignore
/// this extension. Falls back to per-item concurrent translation if the
/// provider's batch path fails structurally (count mismatch) — we'd rather
/// return something than give up.
extension TranslationService {
    /// Translates every string via the active provider's batch endpoint and
    /// returns a parallel array of translations. `nil` entries mean that
    /// particular segment couldn't be translated (after per-item fallback);
    /// the caller should leave those segments showing their original text.
    /// Throws only for hard errors that block any translation — missing API
    /// key, network failure on batch, rate limit — so the UI can show a
    /// retry affordance.
    func translateBatch(_ strings: [String], from source: Locale.Language, to target: Locale.Language) async throws -> [String?] {
        guard !strings.isEmpty else { return [] }

        let batcher = makeBatcher()
        do {
            let strict = try await batcher.translateBatch(strings, from: source, to: target)
            return strict.map(Optional.some)
        } catch BatchTranslationError.countMismatch {
            return await translateConcurrentlyTolerant(strings, from: source, to: target)
        }
    }

    private func makeBatcher() -> BatchTranslator {
        // Re-create each call — these are lightweight wrappers around the
        // underlying providers and shouldn't hold state between invocations.
        // The providers themselves (accessed through this facade) keep their
        // long-lived resources warm.
        switch settings.engine {
        case .claude:
            return ClaudeBatchTranslator(settings: settings)
        case .apple:
            return AppleBatchTranslator(provider: apple)
        }
    }

    /// Last-resort concurrent fallback used when the batch endpoint returns
    /// malformed output. Each per-item failure becomes `nil` in the result so
    /// the compositor can leave that segment's original text visible rather
    /// than masking it with nothing.
    private func translateConcurrentlyTolerant(_ strings: [String], from source: Locale.Language, to target: Locale.Language) async -> [String?] {
        var results = Array<String?>(repeating: nil, count: strings.count)

        await withTaskGroup(of: (Int, String?).self) { group in
            var next = 0
            let limit = min(6, strings.count)

            for _ in 0..<limit {
                let idx = next
                next += 1
                group.addTask { @MainActor [self] in
                    let t = try? await self.translate(strings[idx], from: source, to: target)
                    return (idx, t)
                }
            }

            while let (idx, t) = await group.next() {
                results[idx] = t
                if next < strings.count {
                    let taskIdx = next
                    next += 1
                    group.addTask { @MainActor [self] in
                        let translated = try? await self.translate(strings[taskIdx], from: source, to: target)
                        return (taskIdx, translated)
                    }
                }
            }
        }

        return results
    }
}
