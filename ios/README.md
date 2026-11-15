# Pocket Libre für iPhone

SwiftUI-App für iOS 17+, lokale deutsche Transkription mit WhisperKit.
Aktueller Entwicklungsstand: **0.3.2**.

## Einrichtung

1. `PocketLibre.xcodeproj` in Xcode öffnen und ein eigenes Signing-Team wählen.
2. Für WLAN ein Provisioning-Profil mit Hotspot-Configuration-Capability verwenden.
3. Auf dem iPhone installieren, Sprachmodell ausdrücklich herunterladen.
4. [Bestehenden Pocket-Schlüssel übernehmen](SESSION_KEY.md) und Bluetooth-Import starten.

App während Import und Transkription geöffnet und iPhone entsperrt lassen.
Mehrere Transkriptionen können eingereiht werden; das Modell verarbeitet sie einzeln.
Autotranskription lässt sich unter Einrichtung abschalten.

## Bedienung

Aufnahme antippen: Player mit Zeitleiste, Play/Pause und ±15 Sekunden.
Über **Transkript → Stift** einen Titel vergeben. Ohne eigenen Titel dient der
Textanfang als Kurzbezeichnung, nicht als KI-Zusammenfassung.
Unsichere Ergebnisse werden markiert und können erneut transkribiert werden.

## Grenzen

Bluetooth-Import ist am iPhone 15 Pro Max bestätigt. WLAN, direkte USB-Erkennung
und automatisches Wiederverbinden benötigen noch Hardware-Tests.
Kein Hintergrunddienst, RAG-Chat oder separater verschlüsselter Journal-Vault.
Lokale Daten sind von Backups ausgeschlossen; Originale auf dem Pocket behalten.

## Entwicklung

Projekt regenerieren: `ruby ios/generate_project.rb` (xcodeproj 1.27.0).

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project ios/PocketLibre.xcodeproj -scheme PocketLibre \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO test
```

Zuletzt bestanden 21 reguläre Tests. Modell- und Player-UI-Tests benötigen ihre
jeweiligen Testdateien. [Technische Details und Entwicklungsverlauf](DEVELOPMENT.md).

## Abhängigkeiten

- [WhisperKit / Argmax OSS Swift 1.1.1](https://github.com/argmaxinc/argmax-oss-swift/tree/v1.1.1), MIT.
- [Whisper-small Core ML](https://huggingface.co/argmaxinc/whisperkit-coreml/tree/main/openai_whisper-small).
- [OpenAI Whisper Tokenizer](https://huggingface.co/openai/whisper-small), MIT.

Lizenztexte sind auch in der App enthalten. Kein Code aus `osbock/pocket-sync` übernommen.
