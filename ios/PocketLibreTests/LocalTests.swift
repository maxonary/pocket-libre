import XCTest
import AVFoundation
import WhisperKit
@testable import PocketLibre

final class LocalTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    private func audio() throws -> URL {
        let url = root.appendingPathComponent("test.wav")
        let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_000)!
        buffer.frameLength = 16_000
        for i in 0..<16_000 { buffer.floatChannelData![0][i] = Float(sin(Double(i) * 0.1)) * 0.1 }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        return url
    }
    func testImportPreservesOriginalDeduplicatesAndPersists() async throws {
        let source = try audio()
        let original = try Data(contentsOf: source)
        let location = root.appendingPathComponent("library")
        let library = LocalLibrary(root: location)
        let first = try await library.importFile(source)
        let second = try await library.importFile(source)
        XCTAssertEqual(first.id, second.id)
        let records = try await library.all()
        XCTAssertEqual(records.count, 1)
        let copy = await library.audioURL(first)
        XCTAssertEqual(try Data(contentsOf: copy), original)
        XCTAssertEqual(try Data(contentsOf: source), original)
        try await library.setTranscript("Hallo, hallo, alles gut?", for: first.id)
        let reopened = try await LocalLibrary(root: location).all()
        XCTAssertEqual(reopened.first?.transcript, "Hallo, hallo, alles gut?")
        XCTAssertEqual(try location.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
    }
    func testReviewFlagPersistsAndSuccessfulRetryClearsIt() async throws {
        let source = try audio()
        let library = LocalLibrary(root: root.appendingPathComponent("flag-library"))
        let record = try await library.importFile(source)
        try await library.flagForReview(record.id)
        var records = try await library.all()
        XCTAssertNotNil(records.first?.transcriptionFlag)
        XCTAssertNil(records.first?.transcript)
        try await library.setTranscript("Hallo", for: record.id)
        records = try await library.all()
        XCTAssertNil(records.first?.transcriptionFlag)
        XCTAssertEqual(records.first?.transcript, "Hallo")
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }
    func testTitleSurvivesTranscriptionAndDoesNotRenameAudio() async throws {
        let library = LocalLibrary(root: root.appendingPathComponent("titles"))
        let record = try await library.importFile(audio())
        try await library.setTitle("Meine Geschäftsidee", for: record.id)
        try await library.setTranscript("Ich möchte eine neue Idee ausprobieren.", for: record.id)
        var saved = try await library.all().first!
        XCTAssertEqual(saved.displayTitle, "Meine Geschäftsidee")
        XCTAssertEqual(saved.fileName, record.fileName)
        XCTAssertEqual(saved.name, record.name)
        try await library.setTitle("  ", for: record.id)
        saved = try await library.all().first!
        XCTAssertEqual(saved.displayTitle, "Ich möchte eine neue Idee ausprobieren")
    }
    func testInvalidAudioDoesNotEnterLibrary() async throws {
        let bad = root.appendingPathComponent("bad.mp3")
        try Data("not audio".utf8).write(to: bad)
        let library = LocalLibrary(root: root.appendingPathComponent("library"))
        do { _ = try await library.importFile(bad); XCTFail("Invalid audio accepted") } catch { }
        let records = try await library.all()
        XCTAssertTrue(records.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: bad.path))
    }
    func testCorruptIndexIsNotOverwritten() async throws {
        let location = root.appendingPathComponent("library")
        let library = LocalLibrary(root: location)
        try await library.prepare()
        let index = location.appendingPathComponent("library.json")
        let broken = Data("broken index".utf8)
        try broken.write(to: index)
        do { _ = try await library.importFile(audio()); XCTFail("Corrupt index ignored") } catch { }
        XCTAssertEqual(try Data(contentsOf: index), broken)
    }
    func testGermanIsExplicitAndTranslationDisabled() {
        let options = OfflineTranscriber.germanOptions
        XCTAssertEqual(options.language, "de")
        XCTAssertFalse(options.detectLanguage)
        XCTAssertEqual(options.task, .transcribe)
    }
    func testMissingModelFailsInsteadOfDownloading() async throws {
        let transcriber = OfflineTranscriber(root: root)
        let installed = await transcriber.isInstalled()
        XCTAssertFalse(installed)
        do { _ = try await transcriber.transcribe(root.appendingPathComponent("missing.mp3")); XCTFail("Missing model accepted") }
        catch { XCTAssertTrue(error.localizedDescription.contains("Sprachmodell")) }
    }
    func testNativeGermanTranscriptionWithoutNetwork() async throws {
        let path = ProcessInfo.processInfo.environment["POCKET_TEST_AUDIO"] ?? ""
        try XCTSkipUnless(FileManager.default.fileExists(atPath: path), "Set POCKET_TEST_AUDIO to a harmless German audio fixture to run the model-download integration test.")
        let modelCache = LocalLibrary.defaultRoot.appendingPathComponent("IntegrationTestModel")
        let transcriber = OfflineTranscriber(root: modelCache)
        if !(await transcriber.isInstalled()) { try await transcriber.install { _ in } }
        // The model setup above is explicitly online. Every request below fails the test.
        DenyNetworkProtocol.requestCount = 0
        URLProtocol.registerClass(DenyNetworkProtocol.self)
        defer { URLProtocol.unregisterClass(DenyNetworkProtocol.self) }
        let library = LocalLibrary(root: root.appendingPathComponent("library"))
        let record = try await library.importFile(URL(fileURLWithPath: path))
        let localAudio = await library.audioURL(record)
        let samples = try AudioProcessor.loadAudioAsFloatArray(fromPath: localAudio.path)
        print("Native audio samples: \(samples.count), peak: \(samples.map { abs($0) }.max() ?? 0)")
        let text = try await transcriber.transcribe(localAudio)
        XCTAssertFalse(text.isEmpty)
        XCTAssertTrue(text.lowercased().contains("hallo"), "Unexpected German transcript: \(text)")
        XCTAssertEqual(DenyNetworkProtocol.requestCount, 0, "Offline transcription attempted a network request")
        print("Native offline German result: \(text)")
    }
    func testMissingAndCorruptTokenizerFailLocally() async throws {
        do { _ = try await LocalTokenizer(folder: root); XCTFail("Missing tokenizer accepted") } catch { }
        try Data("invalid json".utf8).write(to: root.appendingPathComponent("tokenizer.json"))
        try Data("{}".utf8).write(to: root.appendingPathComponent("tokenizer_config.json"))
        do { _ = try await LocalTokenizer(folder: root); XCTFail("Corrupt tokenizer accepted") } catch { }
    }
}


final class DenyNetworkProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var count = 0
    static var requestCount: Int {
        get { lock.lock(); defer { lock.unlock() }; return count }
        set { lock.lock(); defer { lock.unlock() }; count = newValue }
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock(); Self.count += 1; Self.lock.unlock()
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }
    override func stopLoading() { }
}
