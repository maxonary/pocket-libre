import Foundation
import CryptoKit
import AVFoundation

struct Recording: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let fileName: String
    let importedAt: Date
    let duration: Double
    var transcript: String?
    var transcriptionFlag: String?
    var title: String?
    var displayTitle: String { title ?? transcript.flatMap(SpeechResult.titleExcerpt) ?? name }
    var reviewFlag: String? { transcriptionFlag ?? transcript.flatMap(SpeechResult.reviewReason) }
}

enum LocalError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

/// Owns only copies in Application Support. Never modifies a source recording.
actor LocalLibrary {
    let root: URL
    init(root: URL) { self.root = root }
    static var defaultRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PocketLibre", isDirectory: true)
    }
    func prepare() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                                                attributes: [.protectionKey: FileProtectionType.complete])
        var url = root
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }
    func all() throws -> [Recording] {
        try prepare()
        let index = root.appendingPathComponent("library.json")
        guard FileManager.default.fileExists(atPath: index.path) else { return [] }
        return try JSONDecoder().decode([Recording].self, from: Data(contentsOf: index))
    }
    private func save(_ records: [Recording]) throws {
        try JSONEncoder().encode(records).write(to: root.appendingPathComponent("library.json"),
                                               options: [.atomic, .completeFileProtection])
    }
    func audioURL(_ record: Recording) -> URL { root.appendingPathComponent(record.fileName) }
    func importFile(_ source: URL) async throws -> Recording {
        try prepare()
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        let ext = source.pathExtension.lowercased()
        guard ["mp3", "m4a", "wav", "aiff", "aif", "caf", "flac"].contains(ext) else {
            throw LocalError.message("Dieses Audioformat wird noch nicht unterstützt.")
        }
        // Coordinate reads with Files / external volumes, then work on a private staging copy.
        let staging = root.appendingPathComponent("import-\(UUID().uuidString).\(ext)")
        defer { try? FileManager.default.removeItem(at: staging) }
        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: source, options: [], error: &coordinationError) { url in
            do { try FileManager.default.copyItem(at: url, to: staging) } catch { copyError = error }
        }
        if let error = coordinationError ?? copyError as NSError? { throw error }
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: staging.path)
        let handle = try FileHandle(forReadingFrom: staging)
        defer { try? handle.close() }
        var hash = SHA256()
        while let bytes = try handle.read(upToCount: 1_048_576), !bytes.isEmpty {
            try Task.checkCancellation()
            hash.update(data: bytes)
        }
        let id = hash.finalize().map { String(format: "%02x", $0) }.joined()
        let asset = AVURLAsset(url: staging)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else { throw LocalError.message("Die Aufnahme enthält kein lesbares Audio.") }
        // Re-read after awaiting AVFoundation so overlapping imports cannot overwrite the index.
        var records = try all()
        if let existing = records.first(where: { $0.id == id }) { return existing }
        let record = Recording(id: id, name: source.deletingPathExtension().lastPathComponent,
                               fileName: "\(id).\(ext)", importedAt: Date(), duration: duration)
        let destination = root.appendingPathComponent(record.fileName)
        if !FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.moveItem(at: staging, to: destination)
        }
        records.insert(record, at: 0)
        try save(records)
        return record
    }
    func setTitle(_ title: String, for id: String) throws {
        var records = try all()
        guard let index = records.firstIndex(where: { $0.id == id }) else { throw LocalError.message("Aufnahme nicht mehr vorhanden.") }
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count <= 120 else { throw LocalError.message("Bitte höchstens 120 Zeichen verwenden.") }
        records[index].title = clean.isEmpty ? nil : clean
        try save(records)
    }
    func flagForReview(_ id: String, reason: String = "Keine verständliche Sprache erkannt") throws {
        var records = try all()
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        records[index].transcriptionFlag = reason
        try save(records)
    }
    func setTranscript(_ text: String, for id: String) throws {
        var records = try all()
        guard let index = records.firstIndex(where: { $0.id == id }) else {
            throw LocalError.message("Aufnahme nicht mehr vorhanden.")
        }
        records[index].transcript = text
        records[index].transcriptionFlag = nil
        try save(records)
    }
}
