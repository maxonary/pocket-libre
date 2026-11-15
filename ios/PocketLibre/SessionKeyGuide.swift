import SwiftUI

struct SessionKeyGuide: View {
    var body: some View {
        List {
            Section {
                Text("Den bestehenden Schlüssel übernehmen")
                    .font(.title2.weight(.regular))
                Text("Der Schlüssel steht nicht in den Bluetooth-Einstellungen. Wir versuchen ihn aus einer normalen Verbindung deiner bereits gekoppelten Pocket-App zu lesen. Kein Reset und keine neue Kopplung.")
                Text("Dieser iPhone-/Mac-Weg ist noch nicht am Pocket bestätigt. iOS kann die benötigten Daten ausblenden.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("1 · Diagnose vorbereiten") {
                Text("Hersteller-App schließen. Apples Bluetooth-Profil in Safari auf dem iPhone laden und unter Einstellungen → Allgemein → VPN & Geräteverwaltung installieren. Danach das iPhone neu starten.")
                Link("Apple-Diagnoseprofil öffnen", destination: URL(string: "https://developer.apple.com/services-account/download?path=%2FiOS%2FiOS_Logs%2FiOSBluetoothLogging.mobileconfig")!)
                Text("Bereits installiert? Nicht erneut installieren. Nach der Installation genügt zunächst der Neustart.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("2 · Ohne Internet verbinden") {
                Text("Nach dem Neustart Flugmodus einschalten. In Einstellungen WLAN ausdrücklich ausschalten und Bluetooth einschalten. Kein Ethernet oder anderes Internet teilen. So kann die Hersteller-App beim Test keine Aufnahmen hochladen.")
                Text("Pocket Libre schließen, Pocket aufwecken und die Hersteller-App öffnen. Nur die bestehende Verbindung herstellen. Nicht entkoppeln, zurücksetzen oder neu anmelden. Falls die App Internet verlangt, hier stoppen.")
            }
            Section("3 · Kurzen Mitschnitt sichern") {
                Text("Direkt nach der Verbindung beide Lautstärketasten und die Seitentaste gleichzeitig kurz drücken und wieder loslassen. Nicht gedrückt halten. Eine kurze Vibration bestätigt laut Apple die sysdiagnose. Anschließend etwa zehn Minuten warten.")
                Text("Die Hersteller-App wieder vollständig schließen. Unter Einstellungen → Datenschutz & Sicherheit → Analyse & Verbesserungen → Analysedaten die neue sysdiagnose-Datei finden und lokal auf den Mac übertragen. Für AirDrop WLAN erst nach dem Schließen der Hersteller-App wieder einschalten.")
                Text("Die Diagnose enthält weitere Gerätedaten. Nicht im Chat hochladen, nicht per E-Mail senden und nicht an Apple übermitteln. Auf dem Mac nur lokal aufbewahren.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("4 · Lokal auslesen und importieren") {
                Text("Auf dem Mac zunächst die Bluetooth-Mitschnitte aus der Diagnose identifizieren. Der Helfer im Projekt liest einen unkomprimierten HCI-/PacketLogger-Mitschnitt – nicht direkt das ganze sysdiagnose-Archiv.")
                Text("uv run python scripts/extract_pocket_key.py /pfad/capture.pklg")
                    .font(.system(.footnote, design: .monospaced)).textSelection(.enabled)
                Text("Bei genau einem eindeutigen Treffer entsteht ~/PocketLocalSetup/pocket-key.json. Der Schlüssel wird nicht im Terminal angezeigt. Übertrage diese Datei lokal auf dein iPhone und wähle hier „Lokale Schlüsseldatei importieren“.")
                Text("Kein Treffer ist kein Grund für einen Reset. Der Mitschnitt kann unvollständig oder redigiert sein.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("5 · Diagnose beenden") {
                Text("Das Bluetooth-Diagnoseprofil unter Allgemein → VPN & Geräteverwaltung entfernen und das iPhone erneut starten. Nach erfolgreichem Schlüsselimport die temporäre JSON-Datei und Diagnosekopien entfernen. Die App bewahrt den Schlüssel im gerätegebundenen iPhone-Schlüsselbund auf.")
                Link("Apples vollständige Anleitung", destination: URL(string: "https://developer.apple.com/services-account/download?path=%2FiOS%2FiOS_Logs%2FBluetooth_Logging_Instructions.pdf")!)
            }
        }
        .navigationTitle("Wo finde ich den Schlüssel?")
        .navigationBarTitleDisplayMode(.inline)
        .tint(OntoraStyle.blue)
    }
}
