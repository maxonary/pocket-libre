import Foundation
import Security

struct PocketFile: Identifiable, Equatable, Sendable {
    let date: String
    let name: String
    let seconds: Int
    var id: String { date + "/" + name }
}

enum PocketProtocol {
    static let marker = Data([0xba, 0x5a, 0x02, 0x8f, 0x04, 0xba, 0x5a, 0x02, 0x8f, 0x04])
    static let maxBytes = 512 * 1024 * 1024
    static func validKey(_ key: String) -> Bool {
        key.utf8.count == 16 && key.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) }
    }
    static func safeID(_ value: String) -> Bool {
        !value.isEmpty && value != "." && value != ".." && value.utf8.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || [45,46,95].contains($0)
        }
    }
    static func command(_ body: String) throws -> Data {
        let fields = body.components(separatedBy: "&")
        let simple: Set<String> = ["LIST_DIRS", "FW", "BAT", "WIFIS", "WIFIO", "WIFI", "WIFIC", "WPING"]
        let allowed = simple.contains(body) || body == "U&WIFI"
            || (fields.count == 2 && fields[0] == "SK" && validKey(fields[1]))
            || (fields.count == 2 && fields[0] == "LIST" && safeID(fields[1]))
            || (fields.count == 3 && fields[0] == "U" && safeID(fields[1]) && safeID(fields[2]))
        guard allowed else { throw LocalError.message("Dieses Pocket-Kommando ist in dieser App nicht erlaubt.") }
        return Data(("APP&" + body).utf8)
    }
    static func messages(_ data: Data) -> [String] {
        guard let text = String(data: data, encoding: .ascii) else { return [] }
        return text.replacingOccurrences(of: "\0", with: "").components(separatedBy: "MCU&")
            .dropFirst().map { "MCU&" + $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }
    static func value(_ message: String, for name: String) -> String? {
        if message == "MCU&" + name { return "" }
        let prefix = "MCU&" + name + "&"
        return message.hasPrefix(prefix) ? String(message.dropFirst(prefix.count)) : nil
    }
    static func file(_ message: String, date: String) throws -> PocketFile {
        let fields = message.components(separatedBy: "&")
        guard fields.count == 5, fields[0] == "MCU", fields[1] == "F", fields[2] == date,
              safeID(fields[2]), safeID(fields[3]), let seconds = Int(fields[4]), seconds >= 0 else {
            throw LocalError.message("Pocket hat einen ungültigen Dateieintrag gesendet.")
        }
        return PocketFile(date: fields[2], name: fields[3], seconds: seconds)
    }
    static func size(_ value: String) throws -> Int {
        guard let size = Int(value), size > 0, size <= maxBytes else {
            throw LocalError.message("Ungültige oder zu große Aufnahme (maximal 512 MB pro Datei).")
        }
        return size
    }
    static func supportsWiFi(_ firmware: String) -> Bool {
        firmware.range(of: #"^(?:[vV])?1\.(?:7|8)(?:\.[0-9]+)?$"#, options: .regularExpression) != nil
    }
    static func validateTransfer(bytes: Int, expected: Int, tail: Data? = nil) throws {
        guard bytes == expected, expected > 0, expected <= maxBytes else {
            throw LocalError.message("Die Übertragung ist unvollständig. Bitte erneut importieren.")
        }
        if let tail, tail != marker { throw LocalError.message("Ungültiges WLAN-Endsignal. Die Datei wurde nicht importiert.") }
    }
}

/// No synchronizable item: secret stays on this iPhone and is unavailable while locked.
enum PocketKeychain {
    private static let service = "com.maxonary.pocketlibre.pocket"
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: "existing-session-key", kSecAttrSynchronizable as String: false]
    }
    static func read() throws -> String? {
        var q = query; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            throw LocalError.message("Der Schlüssel ist gerade nicht zugänglich. Bitte iPhone entsperren.")
        }
        return value
    }
    static func save(_ key: String) throws {
        guard PocketProtocol.validKey(key) else { throw LocalError.message("Der bestehende Schlüssel muss 16 Buchstaben/Ziffern enthalten.") }
        let attributes: [String: Any] = [kSecValueData as String: Data(key.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query; item.merge(attributes) { _, new in new }
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw LocalError.message("Schlüssel konnte nicht sicher gespeichert werden.") }
        } else if status != errSecSuccess { throw LocalError.message("Schlüssel konnte nicht sicher gespeichert werden.") }
    }
    static func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw LocalError.message("Schlüssel konnte nicht entfernt werden.") }
    }
}


@MainActor
protocol PocketCommanding: AnyObject {
    func send(_ body: String) async throws -> Int
    func exchange(_ body: String, answer: String, timeout: Double, accept: (String) -> Bool) async throws -> String
    func wait(_ answer: String, since mark: Int, timeout: Double, accept: (String) -> Bool) async throws -> String
}

extension PocketCommanding {
    func request(_ body: String, answer: String, timeout: Double = 10,
                 accept: (String) -> Bool = { _ in true }) async throws -> String {
        try await exchange(body, answer: answer, timeout: timeout, accept: accept)
    }
}
