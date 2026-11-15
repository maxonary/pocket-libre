import Foundation
import Network
import NetworkExtension

/// Fixed device-local TCP endpoint; never routes recordings to an Internet service.
@MainActor
class PocketWiFi {
    private var socket: NWConnection?
    private var ready = false
    private var socketError: String?
    private var heartbeat: Task<Void, Never>?
    private var ssid: String?
    private var raised = false
    private var generation = UUID()

    func download(_ file: PocketFile, bluetooth: any PocketCommanding, to url: URL,
                  progress: (Double) -> Void) async throws {
        let firmware = try await bluetooth.request("FW", answer: "FW")
        guard PocketProtocol.supportsWiFi(firmware) else {
            throw LocalError.message("WLAN ist nur für Pocket-Firmware 1.7/1.8 freigegeben. Bitte Bluetooth verwenden.")
        }
        let batteryText = try await bluetooth.request("BAT", answer: "BAT")
        guard let battery = Int(batteryText), battery > 10 else { throw LocalError.message("Für WLAN muss der Pocket-Akku über 10 % liegen.") }
        // Do not interrupt a Pocket AP session established by the manufacturer's app.
        guard try await bluetooth.request("WIFIS", answer: "WIFIS") == "0" else {
            throw LocalError.message("Pocket-WLAN ist bereits aktiv. Bitte den anderen Transfer beenden und erneut versuchen.")
        }
        do {
            raised = true
            _ = try await bluetooth.request("WIFIO", answer: "WIFIO")
            heartbeat = Task { @MainActor in
                while !Task.isCancelled {
                    do {
                        _ = try await bluetooth.send("WPING")
                        _ = try await bluetooth.send("WIFIS")
                        try await Task.sleep(nanoseconds: 2_000_000_000)
                    } catch { return }
                }
            }
            let credentials = try await bluetooth.request("WIFI", answer: "WIFI", accept: { $0.contains("&") })
            let parts = credentials.split(separator: "&", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2, parts[0].hasPrefix("PKT01"), (8...63).contains(parts[1].utf8.count) else {
                throw LocalError.message("Pocket meldet keine gültigen WLAN-Zugangsdaten.")
            }
            let name = String(parts[0]); ssid = name
            let configuration = NEHotspotConfiguration(ssid: name, passphrase: String(parts[1]), isWEP: false)
            configuration.hidden = true; configuration.joinOnce = true
            try await join(configuration)
            var joined = false
            for _ in 0..<45 {
                if try await bluetooth.request("WIFIS", answer: "WIFIS", timeout: 5) == "1" { joined = true; break }
                try await Task.sleep(nanoseconds: 1_000_000_000)
            }
            guard joined else { throw LocalError.message("Pocket hat den WLAN-Beitritt nicht bestätigt.") }
            try await openSocket()
            // Critical protocol invariant: TCP connection is ready BEFORE U&WIFI.
            let value = try await bluetooth.request("U&\(file.date)&\(file.name)", answer: "U", accept: { Int($0) != nil })
            let expected = try PocketProtocol.size(value)
            try await Task.sleep(nanoseconds: 300_000_000)
            let switchMark = try await bluetooth.send("U&WIFI")
            FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.protectionKey: FileProtectionType.complete])
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            var count = 0
            while count < expected {
                let data = try await read(maximum: min(65_536, expected - count))
                guard !data.isEmpty else { throw LocalError.message("WLAN-Verbindung vor Dateiende geschlossen.") }
                try handle.write(contentsOf: data); count += data.count
                progress(Double(count) / Double(expected))
            }
            var tail = Data()
            while tail.count < PocketProtocol.marker.count {
                let next = try await read(maximum: PocketProtocol.marker.count - tail.count)
                guard !next.isEmpty else { throw LocalError.message("WLAN-Endsignal fehlt.") }
                tail.append(next)
            }
            try PocketProtocol.validateTransfer(bytes: count, expected: expected, tail: tail)
            _ = try await bluetooth.wait("OFF", since: switchMark, timeout: 10, accept: { _ in true })
            try handle.synchronize()
            guard await cleanUp(bluetooth) else {
                throw LocalError.message("Übertragung beendet, aber Pocket hat das Abschalten des Hotspots nicht bestätigt. Bitte den Gerätestatus prüfen.")
            }
        } catch {
            let cleaned = await cleanUp(bluetooth)
            if !cleaned {
                throw LocalError.message("Import unterbrochen. Pocket hat das Abschalten des Hotspots nicht bestätigt; Originale bleiben erhalten.")
            }
            throw error
        }
    }
    func join(_ configuration: NEHotspotConfiguration) async throws {
        // System dialog requires explicit user approval. Cancellation is checked after it returns.
        do { try await NEHotspotConfigurationManager.shared.apply(configuration) }
        catch let error as NSError {
            guard error.domain == NEHotspotConfigurationErrorDomain,
                  error.code == NEHotspotConfigurationError.alreadyAssociated.rawValue else { throw error }
        }
        try Task.checkCancellation()
    }
    func openSocket() async throws {
        ready = false; socketError = nil
        let token = UUID(); generation = token
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .wifi
        let connection = NWConnection(host: "192.168.200.1", port: 8475, using: parameters)
        socket = connection
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                switch state {
                case .ready: self.ready = true
                case .failed, .cancelled: self.socketError = "Verbindung zum lokalen Pocket-WLAN fehlgeschlagen."
                default: break
                }
            }
        }
        connection.start(queue: DispatchQueue(label: "PocketLibre.localTCP"))
        let deadline = Date().addingTimeInterval(20)
        while !ready {
            try Task.checkCancellation()
            if let socketError { throw LocalError.message(socketError) }
            guard Date() < deadline else { throw LocalError.message("Pocket-WLAN-Port antwortet nicht.") }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        guard case .hostPort(let host, _) = connection.currentPath?.localEndpoint,
              String(describing: host).hasPrefix("192.168.200.") else {
            throw LocalError.message("Das iPhone ist nicht im erwarteten lokalen Pocket-Netz.")
        }
    }
    func read(maximum: Int) async throws -> Data {
        guard let socket else { throw LocalError.message("Pocket-WLAN ist nicht verbunden.") }
        let timeout = Task { @MainActor in
            do { try await Task.sleep(nanoseconds: 20_000_000_000); socket.cancel() } catch { }
        }
        defer { timeout.cancel() }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                socket.receive(minimumIncompleteLength: 1, maximumLength: maximum) { data, _, _, error in
                    if error != nil { continuation.resume(throwing: LocalError.message("WLAN-Transfer unterbrochen oder abgebrochen.")) }
                    else { continuation.resume(returning: data ?? Data()) }
                }
            }
        } onCancel: { socket.cancel() }
    }
    func removeNetwork(_ ssid: String) { NEHotspotConfigurationManager.shared.removeConfiguration(forSSID: ssid) }
    private func cleanUp(_ bluetooth: any PocketCommanding) async -> Bool {
        heartbeat?.cancel(); heartbeat = nil
        socket?.cancel(); socket = nil; generation = UUID()
        // A fresh task performs bounded cleanup even when the transfer task was cancelled.
        var confirmed = true
        if raised {
            let response = await Task { @MainActor in try? await bluetooth.request("WIFIC", answer: "WIFIC", timeout: 5) }.value
            confirmed = response != nil
        }
        if let ssid { removeNetwork(ssid) }
        ssid = nil; raised = false
        return confirmed
    }
}
