import Foundation
import AVFoundation
import WhisperKit
import ArgmaxCore

/// The SDK's default tokenizer loader can download after a local parse failure.
/// Override it so missing/corrupt assets fail closed, without any network fallback.
final class OfflineWhisperKit: WhisperKit {
    override func loadTokenizerIfNeeded() async throws {
        if tokenizer != nil { return }
        guard let folder = tokenizerFolder,
              let logits = textDecoder.logitsSize, let dimensions = audioEncoder.embedSize else {
            throw LocalError.message("Das lokale Sprachmodell ist unvollständig.")
        }
        // Only the pinned multilingual small model is supported by this app.
        guard logits == 51865, dimensions == 768 else {
            throw LocalError.message("Falsches Sprachmodell. Erwartet wird Whisper small (mehrsprachig).")
        }
        textDecoder.isModelMultilingual = true
        tokenizer = try await LocalTokenizer(folder: folder)
    }
}

/// Strictly local adapter: AutoTokenizer's folder initializer only reads local JSON.
final class LocalTokenizer: WhisperTokenizer {
    private let underlying: TokenizerWrapper
    let specialTokens: SpecialTokens
    let allLanguageTokens: Set<Int>
    init(folder: URL) async throws {
        for file in ["tokenizer.json", "tokenizer_config.json"] {
            guard FileManager.default.fileExists(atPath: folder.appendingPathComponent(file).path) else {
                throw LocalError.message("Sprachmodell fehlt oder ist beschädigt. Bitte erneut laden.")
            }
        }
        let tokenizer = try await AutoTokenizerWrapper.from(modelFolder: folder)
        func token(_ value: String) throws -> Int {
            guard let id = tokenizer.convertTokenToId(value) else {
                throw LocalError.message("Ungültiges deutsches Sprachmodell: \(value).")
            }
            return id
        }
        _ = try token("<|de|>")
        specialTokens = try SpecialTokens(
            endToken: token("<|endoftext|>"), englishToken: token("<|en|>"),
            noSpeechToken: token("<|nospeech|>"), noTimestampsToken: token("<|notimestamps|>"),
            specialTokenBegin: token("<|endoftext|>"), startOfPreviousToken: token("<|startofprev|>"),
            startOfTranscriptToken: token("<|startoftranscript|>"), timeTokenBegin: token("<|0.00|>"),
            transcribeToken: token("<|transcribe|>"), translateToken: token("<|translate|>"),
            whitespaceToken: tokenizer.encode(text: " ", addSpecialTokens: false).first ?? 220)
        allLanguageTokens = Set(Constants.languages.values.compactMap { tokenizer.convertTokenToId("<|\($0)|>") })
        underlying = tokenizer
    }
    func encode(text: String) -> [Int] { underlying.encode(text: text) }
    func decode(tokens: [Int]) -> String { underlying.decode(tokens: tokens) }
    func convertTokenToId(_ token: String) -> Int? { underlying.convertTokenToId(token) }
    func convertIdToToken(_ id: Int) -> String? { underlying.convertIdToToken(id) }
    func splitToWordTokens(tokenIds: [Int]) -> (words: [String], wordTokens: [[Int]]) {
        // Word timestamps are disabled. Preserve Unicode boundaries for SDK consumers.
        var words: [String] = [], groups: [[Int]] = [], pending: [Int] = []
        for token in tokenIds {
            pending.append(token)
            let text = decode(tokens: pending)
            if text.contains("\u{FFFD}") { continue }
            if words.isEmpty || text.hasPrefix(" ") || token >= specialTokens.specialTokenBegin {
                words.append(text); groups.append(pending)
            } else {
                words[words.count - 1] += text; groups[groups.count - 1] += pending
            }
            pending = []
        }
        if !pending.isEmpty { words.append(decode(tokens: pending)); groups.append(pending) }
        return (words, groups)
    }
}

actor OfflineTranscriber {
    static let modelName = "openai_whisper-small"
    let root: URL
    private var pipeline: OfflineWhisperKit?
    init(root: URL) { self.root = root }
    var modelFolder: URL { root.appendingPathComponent("model", isDirectory: true) }
    func isInstalled() -> Bool {
        FileManager.default.fileExists(atPath: modelFolder.appendingPathComponent("ready.json").path)
    }
    /// Explicit setup only. No recording URL is accepted or sent by this method.
    func install(progress: @escaping @Sendable (Double) -> Void) async throws {
        let fm = FileManager.default
        let downloadRoot = root.appendingPathComponent("downloads", isDirectory: true)
        try fm.createDirectory(at: downloadRoot, withIntermediateDirectories: true)
        var excluded = downloadRoot
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try excluded.setResourceValues(values)
        let downloaded = try await WhisperKit.download(variant: Self.modelName, downloadBase: downloadRoot,
                                                        progressCallback: { progress($0.fractionCompleted * 0.95) })
        let staging = root.appendingPathComponent("model-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: staging) }
        try fm.copyItem(at: downloaded, to: staging)
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        for name in ["tokenizer.json", "tokenizer_config.json"] {
            let url = URL(string: "https://huggingface.co/openai/whisper-small/resolve/main/\(name)")!
            let (data, response) = try await session.data(from: url)
            guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
                throw LocalError.message("Das Sprachmodell konnte nicht vollständig geladen werden.")
            }
            _ = try JSONSerialization.jsonObject(with: data)
            try data.write(to: staging.appendingPathComponent(name), options: .atomic)
        }
        _ = try await LocalTokenizer(folder: staging)
        for component in ["MelSpectrogram", "AudioEncoder", "TextDecoder"] {
            guard fm.fileExists(atPath: staging.appendingPathComponent(component + ".mlmodelc").path) ||
                  fm.fileExists(atPath: staging.appendingPathComponent(component + ".mlpackage").path) else {
                throw LocalError.message("Unvollständiges Sprachmodell: \(component).")
            }
        }
        try Data("{\"model\":\"small\",\"language\":\"de\"}".utf8)
            .write(to: staging.appendingPathComponent("ready.json"), options: .atomic)
        if fm.fileExists(atPath: modelFolder.path) {
            _ = try fm.replaceItemAt(modelFolder, withItemAt: staging)
        } else { try fm.moveItem(at: staging, to: modelFolder) }
        pipeline = nil
        try? fm.removeItem(at: downloadRoot)
        progress(1)
    }
    static var germanOptions: DecodingOptions {
        DecodingOptions(task: .transcribe, language: "de", temperature: 0,
                        detectLanguage: false, skipSpecialTokens: true,
                        wordTimestamps: false, concurrentWorkerCount: 1, chunkingStrategy: .vad)
    }
    func transcribe(_ audio: URL) async throws -> String {
        guard isInstalled() else { throw LocalError.message("Bitte zuerst das deutsche Sprachmodell laden.") }
        if pipeline == nil {
            pipeline = try await OfflineWhisperKit(WhisperKitConfig(
                modelFolder: modelFolder.path, tokenizerFolder: modelFolder,
                verbose: false, prewarm: false, load: true, download: false))
        }
        guard let pipeline else { throw LocalError.message("Sprachmodell konnte nicht geladen werden.") }
        let duration = try await AVURLAsset(url: audio).load(.duration).seconds
        // Short clips use the direct decoder; long recordings are streamed in bounded buffers.
        let inputOptions = AudioInputOptions(audioLoadingMode: duration > 300 ? .incremental : .fullFile)
        let results = try await pipeline.transcribe(audioPath: audio.path,
            audioInputOptions: inputOptions,
            decodeOptions: Self.germanOptions)
        try Task.checkCancellation()
        return results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
