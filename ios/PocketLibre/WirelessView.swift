import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class WirelessModel: ObservableObject {
    @Published var devices: [PocketBluetooth.Device] = []
    @Published var files: [PocketFile] = []
    @Published var selected: Set<String> = []
    @Published var hasKey = false
    @Published var connected = false
    @Published var busy = false
    @Published var status = ""
    @Published var error: String?
    @Published var progress: Double = 0
    private var bluetooth: PocketBluetooth?
    private var work: Task<Void, Never>?
    func refreshKey() { hasKey = (try? PocketKeychain.read()) != nil }
    func saveKey(_ value: String) {
        do { try PocketKeychain.save(value.trimmingCharacters(in: .whitespacesAndNewlines)); refreshKey(); status = "Bestehender Schlüssel sicher auf diesem iPhone gespeichert." }
        catch { self.error = error.localizedDescription }
    }
    func importKey(_ url: URL) {
        let scope = url.startAccessingSecurityScopedResource()
        defer { if scope { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            guard data.count < 4096,
                  let object = try JSONSerialization.jsonObject(with: data) as? [String: String],
                  let key = object["session_key"] else { throw LocalError.message("Ungültige lokale Schlüsseldatei.") }
            saveKey(key)
        } catch { self.error = "Schlüsseldatei konnte nicht gelesen werden." }
    }
    func forgetKey() {
        guard !busy else { return }
        do { try PocketKeychain.remove(); UserDefaults.standard.removeObject(forKey: "lastPocketID"); UserDefaults.standard.set(false, forKey: "pocketExistingConfirmed"); disconnect(); refreshKey() } catch { self.error = error.localizedDescription }
    }
    private func run(_ message: String, completion: @escaping @MainActor () -> Void = {}, _ operation: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        busy = true; error = nil; status = message; progress = 0
        UIApplication.shared.isIdleTimerDisabled = true
        work = Task {
            defer { busy = false; work = nil; UIApplication.shared.isIdleTimerDisabled = false; if !Task.isCancelled { completion() } }
            do { try await operation() }
            catch is CancellationError { status = "Abgebrochen. Originale bleiben erhalten."; disconnect() }
            catch { self.error = error.localizedDescription; status = "Bitte erneut versuchen."; disconnect() }
        }
    }
    func scan() {
        run("Pocket wird gesucht …", completion: {
            if let remembered = UserDefaults.standard.string(forKey: "lastPocketID"),
               let device = self.devices.first(where: { $0.id.uuidString == remembered }) {
                self.connect(device)
            }
        }) {
            self.disconnect(); self.devices = []
            let ble = PocketBluetooth(); self.bluetooth = ble
            self.devices = try await ble.scan()
            self.status = self.devices.isEmpty ? "Kein Pocket gefunden. Hersteller-App schließen und Gerät aufwecken." : "Wähle dein bereits gekoppeltes Pocket."
        }
    }
    func connect(_ device: PocketBluetooth.Device) {
        run("Verbindung mit bestehendem Schlüssel …") {
            guard let key = try PocketKeychain.read(), let ble = self.bluetooth else { throw LocalError.message("Bestehender Schlüssel fehlt.") }
            try await ble.connect(device, key: key)
            self.connected = true
            self.files = try await ble.listing()
            UserDefaults.standard.set(device.id.uuidString, forKey: "lastPocketID")
            UserDefaults.standard.set(true, forKey: "pocketExistingConfirmed")
            self.status = "\(self.files.count) Aufnahmen gefunden. Wähle zunächst eine Testaufnahme."
        }
    }
    func disconnect() {
        bluetooth?.disconnect(); connected = false; files = []; selected = []
    }
    func stop() { work?.cancel(); status = "Transfer wird beendet …" }
    func download(wifi: Bool, app: AppModel) {
        let selection = files.filter { selected.contains($0.id) }
        guard !selection.isEmpty else { return }
        var importedIDs: [String] = []
        run(wifi ? "Lokales Pocket-WLAN wird vorbereitet …" : "Bluetooth-Import …",
            completion: { app.transcribeImported(ids: importedIDs) }) {
            guard let ble = self.bluetooth, self.connected else { throw LocalError.message("Bitte zuerst Pocket verbinden.") }
            let staging = LocalLibrary.defaultRoot.appendingPathComponent("Wireless-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.complete])
            defer { try? FileManager.default.removeItem(at: staging) }
            for (index, file) in selection.enumerated() {
                try Task.checkCancellation()
                self.status = "\(index + 1)/\(selection.count) · \(file.name)"
                self.progress = 0
                let url = staging.appendingPathComponent(file.name + ".mp3")
                if wifi {
                    // One fresh AP session per file works with both 1.7 and 1.8.
                    try await PocketWiFi().download(file, bluetooth: ble, to: url) { self.progress = $0 }
                } else {
                    try await ble.download(file, to: url) { self.progress = $0 }
                }
                let record = try await app.importWirelessFile(url)
                importedIDs.append(record.id)
                try? FileManager.default.removeItem(at: url)
            }
            self.selected = []
            self.status = "\(importedIDs.count) Aufnahmen lokal importiert. Originale bleiben auf dem Pocket."
            // Release BLE/WiFi before local inference; no Mac or server participates.
            self.disconnect()
        }
    }
}

struct WirelessView: View {
    @EnvironmentObject private var app: AppModel
    @StateObject private var wireless = WirelessModel()
    @State private var key = ""
    @State private var keyImporter = false
    @AppStorage("pocketExistingConfirmed") private var confirmedExisting = false
    @State private var confirmWiFi = false
    @State private var confirmForget = false
    @State private var useWiFi = false
    private var existingConfirmation: some View {
        Toggle("Mein Pocket ist bereits gekoppelt und wurde nicht zurückgesetzt.", isOn: $confirmedExisting)
            .disabled(wireless.busy)
    }
    var body: some View {
        List {
            Section {
                PocketConnectionCard(connected: wireless.connected, searching: wireless.busy)
                    .frame(maxWidth: .infinity)
                if !wireless.connected {
                    Button { wireless.scan() } label: {
                        Text(wireless.busy ? "Verbindung wird hergestellt …" : "Pocket verbinden")
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                    }.buttonStyle(.borderedProminent)
                        .disabled(wireless.busy || !wireless.hasKey || !confirmedExisting || app.busy)
                    Text("Pocket aufwecken und Hersteller-App schließen. Dein zuletzt verbundenes Gerät wird automatisch wiedererkannt.")
                        .font(.footnote).foregroundStyle(.secondary)
                    ForEach(wireless.devices) { device in
                        Button(device.name) { wireless.connect(device) }.disabled(wireless.busy || app.busy || !confirmedExisting || !wireless.hasKey)
                    }
                }
            }
            if !wireless.hasKey {
                Section("Einmalige Einrichtung") {
                    NavigationLink("Wo finde ich den Schlüssel?") { SessionKeyGuide() }
                    SecureField("16-stelliger Sitzungsschlüssel", text: $key)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Schlüssel speichern") { wireless.saveKey(key); key = "" }
                        .disabled(!PocketProtocol.validKey(key) || wireless.busy)
                    Button("Lokale Schlüsseldatei importieren") { keyImporter = true }.disabled(wireless.busy)
                    existingConfirmation
                }
            } else {
                Section {
                    if !confirmedExisting { existingConfirmation }
                    DisclosureGroup("Gerät verwalten") {
                        if confirmedExisting { existingConfirmation }
                        Text("Nach einem Pocket-Reset diese Bestätigung ausschalten. Die App setzt kein Gerät zurück.")
                            .font(.footnote).foregroundStyle(.secondary)
                        Button("Lokalen Schlüssel entfernen", role: .destructive) { confirmForget = true }.disabled(wireless.busy)
                    }
                }
            }
            if !wireless.status.isEmpty {
                Section {
                    Text(wireless.status)
                    if wireless.busy {
                        ProgressView(value: wireless.progress)
                        Button("Abbrechen", role: .cancel) { wireless.stop() }
                    }
                }
            }
            if wireless.connected {
                Section("Aufnahmen auswählen") {
                    ForEach(wireless.files) { file in
                        Button {
                            if wireless.selected.contains(file.id) { wireless.selected.remove(file.id) }
                            else { wireless.selected.insert(file.id) }
                        } label: {
                            HStack {
                                Image(systemName: wireless.selected.contains(file.id) ? "checkmark.circle.fill" : "circle")
                                VStack(alignment: .leading) {
                                    Text(file.name)
                                    Text("\(file.date) · \(file.seconds) Sek.").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }.disabled(wireless.busy || app.busy)
                    }
                    Picker("Übertragung", selection: $useWiFi) {
                        Text("Bluetooth").tag(false)
                        Text("WLAN").tag(true)
                    }.pickerStyle(.segmented).disabled(wireless.busy || app.busy)
                    Button {
                        if useWiFi { confirmWiFi = true }
                        else { wireless.download(wifi: false, app: app) }
                    } label: {
                        Text("Auswahl importieren (\(wireless.selected.count))")
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                    }.buttonStyle(.borderedProminent)
                        .disabled(wireless.busy || app.busy || wireless.selected.isEmpty)
                    Button("Verbindung trennen") { wireless.disconnect() }.disabled(wireless.busy)
                    Text("WLAN ist für Firmware 1.7/1.8 vorgesehen. Noch nicht mit deinem Pocket am iPhone verifiziert. Keine Aufnahmen werden vom Gerät gelöscht.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Vom Pocket importieren")
        .tint(OntoraStyle.blue)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(wireless.busy)
        .onAppear { wireless.refreshKey() }
        .onDisappear { if !wireless.busy { wireless.disconnect() } }
        .fileImporter(isPresented: $keyImporter, allowedContentTypes: [.json]) { result in
            if case .success(let url) = result { wireless.importKey(url) }
        }
        .confirmationDialog("Temporär mit Pocket-WLAN verbinden?", isPresented: $confirmWiFi, titleVisibility: .visible) {
            Button("WLAN-Import starten") { wireless.download(wifi: true, app: app) }
        } message: {
            Text("Die App aktiviert den lokalen Pocket-Hotspot und wechselt vorübergehend das iPhone-WLAN. iOS fragt nach Zustimmung. Nach jeder Datei wird der Hotspot geschlossen. Es wird keine Cloud verwendet.")
        }
        .confirmationDialog("Nur den lokalen Schlüssel entfernen?", isPresented: $confirmForget, titleVisibility: .visible) {
            Button("Auf diesem iPhone entfernen", role: .destructive) { wireless.forgetKey() }
        } message: { Text("Das Pairing der Hersteller-App und das Pocket bleiben unverändert.") }
        .alert("Pocket-Import", isPresented: Binding(get: { wireless.error != nil }, set: { if !$0 { wireless.error = nil } })) {
            Button("OK") { wireless.error = nil }
        } message: { Text(wireless.error ?? "") }
    }
}
