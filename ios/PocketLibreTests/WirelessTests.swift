import XCTest
import NetworkExtension
@testable import PocketLibre

final class WirelessTests: XCTestCase {
    func testOnlyExistingKeyFormatAndSafeCommandsAccepted() throws {
        XCTAssertTrue(PocketProtocol.validKey("ABCDEF1234567890"))
        for value in ["short", "ABCDEFGHIJKLMNOPQ", "ABCD&F1234567890", "ÄBCDEF1234567890"] { XCTAssertFalse(PocketProtocol.validKey(value)) }
        for command in ["BLE&RESET", "OTA", "D&2026-11-15&123", "T&20261115000000", "REC&CALL", "SK&bad", "U&../&x", "U&date&x&SHUT"] {
            XCTAssertThrowsError(try PocketProtocol.command(command))
        }
        XCTAssertEqual(try PocketProtocol.command("LIST_DIRS"), Data("APP&LIST_DIRS".utf8))
        XCTAssertNoThrow(try PocketProtocol.command("U&2026-11-15&PH261115123456"))
    }
    func testCombinedResponsesAndExactPrefix() {
        let messages = PocketProtocol.messages(Data("MCU&WIFIOMCU&OFF\0".utf8))
        XCTAssertEqual(messages, ["MCU&WIFIO", "MCU&OFF"])
        XCTAssertNil(PocketProtocol.value("MCU&WIFIO", for: "WIFI"))
        XCTAssertEqual(PocketProtocol.value("MCU&U&1234", for: "U"), "1234")
    }
    func testListingRejectsTraversalMalformedAndWrongDate() throws {
        let row = try PocketProtocol.file("MCU&F&2026-11-15&PH261115123456&30", date: "2026-11-15")
        XCTAssertEqual(row.seconds, 30)
        for line in ["MCU&F&2026-11-15&../a&30", "MCU&F&2026-11-14&x&30", "MCU&F&2026-11-15&x&nope", "MCU&F&2026-11-15&x&-1"] {
            XCTAssertThrowsError(try PocketProtocol.file(line, date: "2026-11-15"))
        }
    }
    func testStrictTransferLengthAndWiFiTrailer() throws {
        XCTAssertNoThrow(try PocketProtocol.validateTransfer(bytes: 1234, expected: 1234, tail: PocketProtocol.marker))
        for bytes in [0, 1233, 1235] { XCTAssertThrowsError(try PocketProtocol.validateTransfer(bytes: bytes, expected: 1234)) }
        XCTAssertThrowsError(try PocketProtocol.validateTransfer(bytes: 1234, expected: 1234, tail: Data([0])))
        XCTAssertThrowsError(try PocketProtocol.size("999999999999"))
        XCTAssertThrowsError(try PocketProtocol.size("-1"))
        XCTAssertThrowsError(try PocketProtocol.size("WIFI"))
    }
    func testUnknownFirmwareCannotStartWiFi() {
        for version in ["1.7", "1.8", "v1.8.0"] { XCTAssertTrue(PocketProtocol.supportsWiFi(version)) }
        for version in ["1.3.3", "1.9", "1.80", "", "1.8 unknown"] { XCTAssertFalse(PocketProtocol.supportsWiFi(version)) }
    }
}

@MainActor
private final class TransferTrace { var events: [String] = [] }

@MainActor
private final class FakePocket: PocketCommanding {
    let trace: TransferTrace
    var firmware = "1.8"
    private var active = false
    init(_ trace: TransferTrace) { self.trace = trace }
    func send(_ body: String) async throws -> Int { trace.events.append(body); return trace.events.count }
    func exchange(_ body: String, answer: String, timeout: Double, accept: (String) -> Bool) async throws -> String {
        trace.events.append(body)
        switch body {
        case "FW": return firmware
        case "BAT": return "90"
        case "WIFIS": return active ? "1" : "0"
        case "WIFIO": active = true; return ""
        case "WIFIC": active = false; return ""
        case "WIFI": return "PKT01_TEST&12345678"
        default: return "4"
        }
    }
    func wait(_ answer: String, since mark: Int, timeout: Double, accept: (String) -> Bool) async throws -> String {
        trace.events.append("WAIT_" + answer); return ""
    }
}

@MainActor
private final class FakeWiFi: PocketWiFi {
    let trace: TransferTrace
    var stream = Data([0xff, 0xf3, 0x48, 0xc4]) + PocketProtocol.marker
    var failConnect = false
    init(_ trace: TransferTrace) { self.trace = trace; super.init() }
    override func join(_ configuration: NEHotspotConfiguration) async throws { trace.events.append("JOIN") }
    override func openSocket() async throws {
        trace.events.append("TCP_READY")
        if failConnect { throw LocalError.message("Fixture connection failed") }
    }
    override func read(maximum: Int) async throws -> Data {
        // Deliberately fragmented payload/trailer.
        let data = Data(stream.prefix(min(maximum, 2)))
        stream.removeFirst(data.count)
        return data
    }
    override func removeNetwork(_ ssid: String) { trace.events.append("REMOVE_NETWORK") }
}

extension WirelessTests {
    @MainActor
    func testWiFiOrderAndFragmentedTrailer() async throws {
        let trace = TransferTrace(), file = PocketFile(date: "2026-11-15", name: "20261115123408", seconds: 1)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try await FakeWiFi(trace).download(file, bluetooth: FakePocket(trace), to: url) { _ in }
        XCTAssertEqual(try Data(contentsOf: url), Data([0xff, 0xf3, 0x48, 0xc4]))
        XCTAssertLessThan(trace.events.firstIndex(of: "TCP_READY")!, trace.events.firstIndex(of: "U&WIFI")!)
        XCTAssertLessThan(trace.events.firstIndex(of: "JOIN")!, trace.events.firstIndex(of: "TCP_READY")!)
        XCTAssertTrue(trace.events.contains("WIFIC"))
        XCTAssertEqual(trace.events.last, "REMOVE_NETWORK")
    }
    @MainActor
    func testNoSwitchWithoutTCPAndCleanupOnFailure() async throws {
        let trace = TransferTrace()
        // Shared trace for the actual test instance.
        let network = FakeWiFi(trace); network.failConnect = true
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            try await network.download(PocketFile(date: "2026-11-15", name: "test", seconds: 1), bluetooth: FakePocket(trace), to: url) { _ in }
            XCTFail("Expected TCP failure")
        } catch { }
        XCTAssertFalse(trace.events.contains("U&WIFI"))
        XCTAssertTrue(trace.events.contains("WIFIC"))
        XCTAssertTrue(trace.events.contains("REMOVE_NETWORK"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
    @MainActor
    func testWrongFirmwareDoesNotActivateAP() async throws {
        let trace = TransferTrace()
        let device = FakePocket(trace); device.firmware = "1.3.3"
        do {
            try await FakeWiFi(trace).download(PocketFile(date: "2026-11-15", name: "test", seconds: 1), bluetooth: device,
                to: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)) { _ in }
            XCTFail("Unsupported firmware accepted")
        } catch { }
        XCTAssertFalse(trace.events.contains("WIFIO"))
    }
}
