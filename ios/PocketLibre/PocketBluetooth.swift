import Foundation
@preconcurrency import CoreBluetooth

/// Single, user-initiated session. No reset, pairing, clock, delete or recording commands.
@MainActor
final class PocketBluetooth: NSObject, @preconcurrency CBCentralManagerDelegate, @preconcurrency CBPeripheralDelegate, PocketCommanding {
    struct Device: Identifiable { let peripheral: CBPeripheral; var id: UUID { peripheral.identifier }; let name: String }
    private var central: CBCentralManager!
    private(set) var devices: [Device] = []
    private var peer: CBPeripheral?
    private var command: CBCharacteristic?
    private var audio: CBCharacteristic?
    private var failure: String?
    private var replies: [String] = []
    private var sink: FileHandle?
    private(set) var received = 0
    private var off = false
    private var receiving = false
    private var lastAudio = Date()
    static let service = CBUUID(string: "001120a0-2233-4455-6677-889912345678")
    static let commandID = CBUUID(string: "001120a3-2233-4455-6677-889912345678")
    static let audioID = CBUUID(string: "001120a1-2233-4455-6677-889912345678")

    override init() { super.init(); central = CBCentralManager(delegate: self, queue: .main) }
    private func pause() async throws {
        try Task.checkCancellation()
        if let failure { throw LocalError.message(failure) }
        try await Task.sleep(nanoseconds: 50_000_000)
    }
    private func until(timeout: Double = 15, _ predicate: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !predicate() {
            guard Date() < deadline else { throw LocalError.message("Pocket antwortet nicht. Hersteller-App schließen und erneut versuchen.") }
            try await pause()
        }
    }
    func scan() async throws -> [Device] {
        failure = nil; devices = []
        try await until { self.central.state != .unknown && self.central.state != .resetting }
        guard central.state == .poweredOn else { throw LocalError.message("Bluetooth ist deaktiviert oder nicht erlaubt. Bitte in den iPhone-Einstellungen prüfen.") }
        central.scanForPeripherals(withServices: nil)
        defer { central.stopScan() }
        let end = Date().addingTimeInterval(7)
        while Date() < end { try await pause() }
        return devices
    }
    func connect(_ device: Device, key: String) async throws {
        guard PocketProtocol.validKey(key) else { throw LocalError.message("Ein gültiger bestehender Schlüssel fehlt.") }
        disconnect(); failure = nil; replies = []; command = nil; audio = nil
        try await until(timeout: 5) { device.peripheral.state == .disconnected }
        peer = device.peripheral; peer?.delegate = self
        central.connect(device.peripheral)
        do {
            try await until { self.command?.isNotifying == true && self.audio?.isNotifying == true }
            let response = try await request("SK&" + key, answer: "SK")
            guard response == "OK" else { throw LocalError.message("Der bestehende Schlüssel wurde abgelehnt. Kein Reset und keine Neu-Kopplung ausgeführt.") }
        } catch { disconnect(); throw error }
    }
    func disconnect() {
        central.stopScan()
        if let peer { central.cancelPeripheralConnection(peer) }
        peer = nil; command = nil; audio = nil; receiving = false
        try? sink?.close(); sink = nil; replies = []
    }
    func send(_ body: String) async throws -> Int {
        guard let peer, peer.state == .connected, let command else { throw LocalError.message("Pocket ist nicht verbunden.") }
        if let failure { throw LocalError.message(failure) }
        try Task.checkCancellation()
        let payload = try PocketProtocol.command(body)
        let kind: CBCharacteristicWriteType = command.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        guard payload.count <= peer.maximumWriteValueLength(for: kind) else { throw LocalError.message("BLE-Kommando ist für diese Verbindung zu lang.") }
        if kind == .withoutResponse { try await until(timeout: 5) { peer.canSendWriteWithoutResponse } }
        let mark = replies.count
        peer.writeValue(payload, for: command, type: kind)
        return mark
    }
    func wait(_ answer: String, since mark: Int, timeout: Double = 10,
              accept: (String) -> Bool = { _ in true }) async throws -> String {
        var cursor = mark
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            while cursor < replies.count {
                let message = replies[cursor]; cursor += 1
                if let value = PocketProtocol.value(message, for: answer), accept(value) { return value }
            }
            try await pause()
        }
        throw LocalError.message("Pocket-Antwort fehlt (\(answer)). Bitte erneut versuchen.")
    }
    func exchange(_ body: String, answer: String, timeout: Double = 10,
                 accept: (String) -> Bool = { _ in true }) async throws -> String {
        let mark = try await send(body)
        return try await wait(answer, since: mark, timeout: timeout, accept: accept)
    }
    func listing() async throws -> [PocketFile] {
        let start = try await send("LIST_DIRS")
        let countText = try await wait("DIRS_SUM", since: start)
        guard let count = Int(countText), count >= 0 else { throw LocalError.message("Unvollständige Verzeichnisliste.") }
        let dates = Array(Set(replies.dropFirst(start).compactMap { PocketProtocol.value($0, for: "DIRS") }))
        guard dates.count == count, dates.allSatisfy(PocketProtocol.safeID) else { throw LocalError.message("Unvollständige oder ungültige Verzeichnisliste.") }
        var result: [PocketFile] = []
        for date in dates.sorted().reversed() {
            let mark = try await send("LIST&" + date)
            let total = try await wait("LIST", since: mark, timeout: 20)
            let lines = Array(Set(replies.dropFirst(mark).filter { $0.hasPrefix("MCU&F&") }))
            guard let expected = Int(total), expected == lines.count else { throw LocalError.message("Unvollständige Dateiliste. Bitte erneut laden.") }
            result += try lines.map { try PocketProtocol.file($0, date: date) }
        }
        return result.sorted { $0.id > $1.id }
    }
    func download(_ file: PocketFile, to url: URL, progress: (Double) -> Void) async throws {
        guard PocketProtocol.safeID(file.date), PocketProtocol.safeID(file.name) else { throw LocalError.message("Ungültiger Dateiname.") }
        FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.protectionKey: FileProtectionType.complete])
        sink = try FileHandle(forWritingTo: url); received = 0; off = false; receiving = true; lastAudio = Date()
        defer { receiving = false; try? sink?.close(); sink = nil }
        let mark = try await send("U&\(file.date)&\(file.name)")
        let expected = try PocketProtocol.size(try await wait("U", since: mark, accept: { Int($0) != nil }))
        while !off || received < expected {
            if off && received < expected { throw LocalError.message("Pocket hat die Übertragung vorzeitig beendet.") }
            guard received <= expected else { throw LocalError.message("Pocket hat mehr Daten als angekündigt gesendet.") }
            guard Date().timeIntervalSince(lastAudio) < 25 else { throw LocalError.message("Bluetooth-Transfer unterbrochen. Das Original bleibt erhalten.") }
            progress(min(Double(received) / Double(expected), 1))
            try await pause()
        }
        try PocketProtocol.validateTransfer(bytes: received, expected: expected)
        try sink?.synchronize()
        progress(1)
    }
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOff || central.state == .unauthorized { failure = "Bluetooth nicht verfügbar oder nicht erlaubt." }
    }
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name ?? ""
        guard name.hasPrefix("PKT01"), !devices.contains(where: { $0.id == peripheral.identifier }) else { return }
        devices.append(Device(peripheral: peripheral, name: name))
    }
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard peripheral == peer else { return }
        peripheral.discoverServices([Self.service])
    }
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        if peripheral == peer { failure = "Pocket konnte nicht verbunden werden." }
    }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if peripheral == peer { failure = "Bluetooth-Verbindung zu Pocket verloren." }
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard peripheral == peer else { return }
        guard error == nil, let service = peripheral.services?.first(where: { $0.uuid == Self.service }) else {
            failure = "Pocket-Dienst wurde nicht gefunden."; return
        }
        peripheral.discoverCharacteristics([Self.commandID, Self.audioID], for: service)
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard peripheral == peer else { return }
        guard error == nil else { failure = "Pocket-Kanäle nicht verfügbar."; return }
        for characteristic in service.characteristics ?? [] {
            if characteristic.uuid == Self.commandID { command = characteristic; peripheral.setNotifyValue(true, for: characteristic) }
            if characteristic.uuid == Self.audioID { audio = characteristic; peripheral.setNotifyValue(true, for: characteristic) }
        }
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if peripheral == peer, error != nil { failure = "Pocket-Benachrichtigungen konnten nicht aktiviert werden." }
    }
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if peripheral == peer, error != nil { failure = "Pocket-Kommando konnte nicht übertragen werden." }
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral == peer else { return }
        guard error == nil, let data = characteristic.value else { failure = "Fehler beim Lesen von Pocket."; return }
        if characteristic.uuid == Self.commandID {
            for message in PocketProtocol.messages(data) {
                // Authentication/WiFi credentials must never be logged or persisted.
                replies.append(message)
                if message == "MCU&OFF" { off = true }
                if message.hasPrefix("MCU&STA&"), receiving { failure = "Aufnahme am Pocket gestartet. Import bitte danach erneut versuchen." }
            }
            if replies.count > 100_000 { failure = "Zu viele Pocket-Nachrichten. Bitte neu verbinden." }
        } else if characteristic.uuid == Self.audioID, receiving {
            do {
                guard received + data.count <= PocketProtocol.maxBytes else { throw LocalError.message("Datei zu groß.") }
                try sink?.write(contentsOf: data); received += data.count; lastAudio = Date()
            } catch { failure = "Die Aufnahme konnte nicht vollständig gespeichert werden." }
        }
    }
}
