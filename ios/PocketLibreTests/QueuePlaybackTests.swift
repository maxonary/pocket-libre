import XCTest
@testable import PocketLibre

@MainActor
final class QueuePlaybackTests: XCTestCase {
    func testQueueSerializesDeduplicatesAndContinuesAfterFailure() async throws {
        let queue = TranscriptionQueue()
        var running = 0; var peak = 0; var calls: [String] = []
        queue.blocked = true
        queue.process = { id in
            running += 1; peak = max(peak, running); calls.append(id)
            defer { running -= 1 }
            try await Task.sleep(nanoseconds: 10_000_000)
            if id == "bad" { throw LocalError.message("test failure") }
        }
        queue.enqueue(["first", "bad", "last", "first"])
        XCTAssertEqual(queue.pending, ["first", "bad", "last"])
        queue.blocked = false
        for _ in 0..<200 {
            if calls.count == 3 && !queue.running && queue.pending.isEmpty { break }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertEqual(calls, ["first", "bad", "last"])
        XCTAssertEqual(peak, 1)
        XCTAssertNotNil(queue.failures["bad"])
        XCTAssertFalse(queue.running)
    }
    func testStopCancelsActiveAndDropsWaitingWithoutStartingNext() async throws {
        let queue = TranscriptionQueue()
        var calls: [String] = []
        queue.process = { id in calls.append(id); try await Task.sleep(nanoseconds: 2_000_000_000) }
        queue.enqueue(["first", "second"])
        for _ in 0..<100 {
            if queue.active != nil { break }
            await Task.yield()
        }
        queue.stop()
        for _ in 0..<100 {
            if !queue.running { break }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTAssertEqual(calls, ["first"])
        XCTAssertTrue(queue.pending.isEmpty)
        XCTAssertTrue(queue.failures.isEmpty)
        XCTAssertFalse(queue.running)
    }
    func testLegacyRecordDecodesAndSpeechFlagIsConservative() throws {
        let old = Data(#"{"id":"a","name":"a","fileName":"a.mp3","importedAt":0,"duration":1}"#.utf8)
        XCTAssertNil(try JSONDecoder().decode(Recording.self, from: old).transcriptionFlag)
        XCTAssertTrue(SpeechResult.needsReview(" \n"))
        XCTAssertTrue(SpeechResult.needsReview("[Unverständlich]"))
        XCTAssertFalse(SpeechResult.needsReview("Das war unverständlich, aber dann sagte er Hallo."))
    }
    func testMusicMarkersAreUncertainAndNeverBecomeAutomaticTitles() {
        for marker in ["Musik", "[Musik]", "(music)", "♪ Musik ♪"] {
            XCTAssertTrue(SpeechResult.needsReview(marker))
            XCTAssertNil(SpeechResult.titleExcerpt(marker))
        }
        XCTAssertFalse(SpeechResult.needsReview("Ich möchte mehr Musik machen."))
        XCTAssertEqual(SpeechResult.titleExcerpt("Ich möchte mehr Musik machen. Morgen fange ich an."), "Ich möchte mehr Musik machen")
        let legacy = Recording(id: "a", name: "original", fileName: "a.mp3", importedAt: Date(), duration: 1, transcript: "Musik")
        XCTAssertNotNil(legacy.reviewFlag)
        XCTAssertEqual(legacy.displayTitle, "original")
        XCTAssertEqual(legacy.transcript, "Musik")
    }
    func testPlaybackTimeAndSeekBounds() {
        XCTAssertEqual(AudioPlayback.clamped(-15, duration: 10), 0)
        XCTAssertEqual(AudioPlayback.clamped(25, duration: 10), 10)
        XCTAssertEqual(AudioPlayback.clamped(.nan, duration: 10), 0)
        XCTAssertEqual(AudioPlayback.time(3661), "1:01:01")
        XCTAssertEqual(AudioPlayback.time(65), "1:05")
    }
}
