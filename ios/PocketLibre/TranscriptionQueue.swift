import Foundation
import Combine

@MainActor
final class TranscriptionQueue: ObservableObject {
    @Published private(set) var pending: [String] = []
    @Published private(set) var active: String?
    @Published private(set) var failures: [String: String] = [:]
    var blocked = false { didSet { start() } }
    var process: ((String) async throws -> Void)?
    private var worker: Task<Void, Never>?
    var running: Bool { active != nil }
    func contains(_ id: String) -> Bool { active == id || pending.contains(id) }
    func enqueue(_ ids: [String]) {
        for id in ids where !contains(id) { pending.append(id); failures[id] = nil }
        start()
    }
    func stop() { pending = []; worker?.cancel() }
    private func start() {
        guard worker == nil, !blocked, !pending.isEmpty, let process else { return }
        worker = Task {
            defer { active = nil; worker = nil; start() }
            while !pending.isEmpty && !blocked && !Task.isCancelled {
                let id = pending.removeFirst(); active = id
                do { try await process(id) }
                catch is CancellationError { break }
                catch { failures[id] = error.localizedDescription }
                active = nil
            }
        }
    }
}

enum SpeechResult {
    static func reviewReason(_ text: String) -> String? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalized = value.trimmingCharacters(in: CharacterSet(charactersIn: "[]().!♪♫ "))
        if ["musik", "music", "hintergrundmusik"].contains(normalized) {
            return "Unsichere Erkennung: nur Musikmarker"
        }
        if value.isEmpty || ["unverständlich", "inaudible", "silence", "keine sprache"].contains(normalized) {
            return "Keine verständliche Sprache erkannt"
        }
        return nil
    }
    static func needsReview(_ text: String) -> Bool { reviewReason(text) != nil }
    // Extractive label, not an invented semantic summary. Custom titles always win.
    static func titleExcerpt(_ text: String) -> String? {
        guard !needsReview(text) else { return nil }
        let sentence = text.split(whereSeparator: { ".!?\n".contains($0) }).first.map(String.init) ?? text
        let words = sentence.split(whereSeparator: { $0.isWhitespace })
        let excerpt = words.prefix(9).joined(separator: " ")
        guard !excerpt.isEmpty else { return nil }
        return String(excerpt.prefix(80)) + (words.count > 9 || excerpt.count > 80 ? " …" : "")
    }
}
