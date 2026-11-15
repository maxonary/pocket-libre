# Pocket Libre für iPhone

Native SwiftUI-App (iOS 17+) für lokalen Audioimport und deutsche Transkription.
Die Python-App und ein laufender Mac sind zur Nutzung nicht nötig.

## Öffnen und installieren

1. `ios/PocketLibre.xcodeproj` in Xcode öffnen.
2. Scheme **PocketLibre**, dein iPhone und unter **Signing & Capabilities** dein
   eigenes Development Team wählen. Bundle-ID: `com.maxonary.pocketlibre`.
3. iPhone verbinden/entsperren, ggf. Developer Mode aktivieren, dann **Run**.
4. In der App **Sprachmodell laden** wählen und den Download bestätigen.
   Das mehrsprachige Core-ML-Modell `openai_whisper-small` samt Tokenizer wird
   auf dem iPhone gespeichert (etwa 470 MB; zusätzlicher Platz für Download,
   Installation und Core-ML-Caches erforderlich).
5. **Aufnahmen importieren** → **Durchsuchen** → lokales USB-Laufwerk
   **Pocket / RECORD** oder **Auf meinem iPhone**. Mehrfachauswahl wird unterstützt.
   Keine Cloud-Dateianbieter auswählen, wenn der Import vollständig offline sein soll.
6. Neue Dateien werden kopiert und bei installiertem Modell auf Deutsch transkribiert.
   Bereits importierte Inhalte werden per SHA-256 erkannt. Ohne Modell kann man
   zunächst importieren und später pro Aufnahme transkribieren.

USB-Erkennung des Pocket am iPhone ist noch nicht auf echter Hardware bestätigt.
Falls das Laufwerk in der Dateien-App nicht erscheint, ist der direkte USB-Import
noch nicht verfügbar; die App kann es nicht selbst einbinden. Eine Watch-App ist nicht enthalten.

## Drahtloser Import (0.2.0, Hardware-Abnahme offen)

Unter **Pocket drahtlos verbinden** den bestehenden Schlüssel lokal importieren,
den bereits gekoppelten Pocket suchen und ausgewählte Aufnahmen per Bluetooth oder
WLAN übernehmen. [Schlüsselübernahme nur mit iPhone und Mac](SESSION_KEY.md).
Der Schlüssel bleibt im gerätegebundenen, nicht synchronisierten iOS-Schlüsselbund.
Es gibt keine Reset-, Pairing- oder Löschfunktion.

WLAN benötigt die Hotspot-Configuration-Capability im Apple-Profil, Firmware 1.7/1.8,
mehr als 10 % Pocket-Akku und die Zustimmung zum temporären WLAN-Wechsel.
Bluetooth steuert den Transfer; Audio kommt direkt vom lokalen Pocket-Hotspot über
TCP. Die App prüft Dateilänge und Endmarker, beendet ihren Hotspot-Transfer und
übernimmt erst vollständige Dateien. Originale bleiben erhalten. App und iPhone
währenddessen geöffnet/entsperrt lassen. Kein automatischer Hintergrundimport.

Version 0.2.0 wurde nach Annahme der Apple-Programmvereinbarung am 15. November
2026 erfolgreich mit Hotspot-Entitlement signiert und als Update auf dem iPhone
installiert. Die drahtlose Hardware-Abnahme wartet weiterhin auf den bestehenden
Sitzungsschlüssel.

## Datenschutz und Offline-Verhalten

- Keine Accounts, Analytics, Cloud-Transkription, Remote-Zusammenfassung oder Server.
- Nur der ausdrücklich gestartete Modell-Setup lädt Daten von Hugging Face.
- Inferenz lädt ausschließlich lokale Modelle (`download: false`). Der normale
  WhisperKit-Tokenizer-Loader besitzt einen Download-Fallback; `OfflineWhisperKit`
  ersetzt ihn durch `LocalTokenizer`. Fehlende/beschädigte Dateien führen zu Fehlern.
- Deutsch wird ausdrücklich gesetzt: `language: de`, `detectLanguage: false`,
  `task: transcribe`. Das Modell bekommt keinen erwarteten Text als Prompt.
- Importierte Audiodateien und Transkripte liegen in Application Support,
  ausgeschlossen von Backups, mit iOS-Dateischutz `complete`.
  Keine iCloud-Entitlements und keine automatische Synchronisation.
- Das ist noch **kein separater verschlüsselter Journal-Vault**. Der Schutz beruht
  auf iOS Data Protection und dem Gerätecode. Beim Löschen der App gehen ihre Daten
  verloren. Originale auf dem Pocket bleiben unverändert erhalten.
- Nur **Text exportieren** öffnet bewusst die iOS-Teilen-Funktion.
- Während der Verarbeitung App geöffnet und Gerät entsperrt lassen. Es gibt keinen
  dauerhaften Hintergrunddienst. „Stoppen“ wirkt kooperativ; ein laufender Modellschritt
  kann noch fertig werden. Die App verdeckt Inhalte beim Wechsel in den Hintergrund.

## Entwicklung und Tests

Xcode-Projekt ist eingecheckt; Ruby/Xcodeproj ist nur zur Regeneration nötig:
`ruby ios/generate_project.rb` (gem `xcodeproj` 1.27.0).
WhisperKit ist auf Version 1.1.1 festgelegt; Package.resolved pinnt die Revisionen.

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project ios/PocketLibre.xcodeproj -scheme PocketLibre \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO test
```

Die sechs normalen Tests prüfen Import/Deduplizierung/Quellerhalt, Persistenz und
Backup-Ausschluss, ungültiges Audio, beschädigten Index, deutsche Optionen sowie
fehlende Modelle/Tokenizer. Lange Aufnahmen (über fünf Minuten) werden in begrenzten Audiopuffern gelesen.
Ein zusätzlicher Integrationstest ist standardmäßig
übersprungen. Explizit mit einer harmlosen deutschen Testdatei, die „Hallo“ enthält:

```sh
# Lädt das Core-ML-Modell in einen wiederverwendbaren Simulator-Testcache.
# Nach dem Setup blockiert ein URLProtocol HTTP-Zugriffe für die Inferenz.
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project ios/PocketLibre.xcodeproj -scheme PocketLibre \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO POCKET_TEST_AUDIO=/absoluter/pfad/test.mp3 test
```

Der Netzwerktest ist ein HTTP-Test im Simulator, kein Ersatz für den Flugmodus-Test
auf einem echten iPhone. Core ML kann auf einem Gerät andere Laufzeit/Ergebnisse
liefern als Python Whisper oder der Simulator.

## Abnahme auf dem iPhone

- Modell laden, App komplett beenden, Flugmodus einschalten, App neu öffnen.
- Pocket anschließen; erscheint das Laufwerk in der Dateien-App?
- Harmlose Testdatei importieren und Transkript mit dem Gesprochenen vergleichen.
- Dieselbe Datei erneut importieren: genau ein Eintrag, Original weiterhin vorhanden.
- App neu starten: Aufnahme und Text vorhanden, Wiedergabe funktioniert.
- Größere Aufnahme testen: Dauer, Wärmeentwicklung und Akkuverbrauch dokumentieren.

## Abhängigkeiten

- [WhisperKit / Argmax OSS Swift 1.1.1](https://github.com/argmaxinc/argmax-oss-swift/tree/v1.1.1), MIT.
- [Whisper-small Core ML](https://huggingface.co/argmaxinc/whisperkit-coreml/tree/main/openai_whisper-small).
- [OpenAI Whisper small Tokenizer](https://huggingface.co/openai/whisper-small), MIT.

Es wurde kein Code aus `osbock/pocket-sync` verwendet.

## Verifizierter Stand

Simulator- und signierter Gerätebuild wurden mit Xcode 27.2 erstellt.
Für Version 0.1.0 bestanden alle sieben Tests inklusive des optionalen Offline-Integrationstests.
Ein klarer deutscher, lokal synthetisierter Testsatz wurde im Simulator vollständig
korrekt erkannt; während der Inferenz registrierte der HTTP-Blocker keine Requests.
Auch eine 310 Sekunden lange Wiederholung dieses Satzes bestand den Streaming-Test
mit null registrierten HTTP-Requests (245 Sekunden Testlaufzeit im Simulator;
kein Maßstab für die Geschwindigkeit auf dem iPhone).
Die kurze, dumpfe Pocket-Testaufnahme lieferte dagegen mit dem Core-ML-Modell
„[Unverständlich]“, obwohl Python Whisper sie zuvor erkannt hatte. Die Genauigkeit
auf echten Pocket-Aufnahmen und die Laufzeit am iPhone bleiben daher Abnahmepunkte.

Die App wurde am 15. November 2026 auf dem iPhone 15 Pro Max installiert und
erfolgreich gestartet. Modellinstallation, Transkription und Pocket-USB-Import auf
diesem physischen Gerät sind noch nicht verifiziert. Ein signierter Entwicklungsbuild
liegt lokal unter `dist/ios/PocketLibre-0.1.0.ipa` (nicht im Git-Repository).

Der aktuelle 0.2.0-Simulatorlauf bestand 14 Tests; der optionale Modelltest wurde
in diesem Lauf übersprungen. Acht Wireless-Tests prüfen Protokollvalidierung,
Kommando-Allowlist, Firmware-Grenzen, TCP-vor-U&WIFI, fragmentierte Endmarker
und das Aufräumen nach fehlgeschlagener TCP-Verbindung. Drei Python-Tests prüfen
den lokalen Schlüssel-Extraktor. Es fand noch kein drahtloser Hardware-Transfer statt.

## Oberfläche 0.2.1

Ontora-Farben und reduzierte Bedienung nach Rainbrand, Brand-Version
`454dc1c9-4c6c-50ec-8ac5-6d2978d867e5`: Blau #002FA7, weißer Hintergrund,
kontrastreiche neutrale Texte, native iOS-Schrift. Startseite mit Pocket-Import,
sekundärem Datei-Import und Aufnahmen. Sprachmodell, Datenschutz und Lizenzen
liegen gemeinsam unter Einrichtung. WLAN/Bluetooth sind eine Auswahl mit einem
Import-Button; bestehende Sicherheitsabfragen bleiben erhalten.

## Wiedergabe und Transkription (0.3.0)

- Aufnahmen klappen in der Liste auf: Play/Pause, verschiebbare Zeitleiste,
  vergangene/verbleibende Zeit und ±15 Sekunden. Ein gemeinsamer Player verhindert
  übereinanderliegende Wiedergabe. Audio-Unterbrechungen und das Entfernen von
  Kopfhörern pausieren die Wiedergabe.
- Automatische Transkription ist standardmäßig aktiv und unter Einrichtung abschaltbar.
  Nach Modellinstallation werden offene Aufnahmen eingereiht. Beim nächsten App-Start
  werden offene, nicht markierte Aufnahmen bei aktivierter Automatik wieder eingereiht.
- Mehrere Aufträge können gestartet werden. Eine lokale Warteschlange verarbeitet
  sie einzeln; es laufen nicht mehrere Whisper-Instanzen gleichzeitig. Pro Aufnahme
  erscheinen ein Aktivitätsindikator oder die Warteposition. „Alle offenen transkribieren“
  reiht noch nicht bearbeitete Aufnahmen ein. App geöffnet/entsperrt lassen.
- Leeres Ergebnis oder ein reiner Unverständlich-Marker setzt ein dauerhaftes
  „Keine verständliche Sprache erkannt“-Flag statt eines Fehlerdialogs. Das ist keine
  Garantie für die Erkennung aller Stille-/Halluzinationsfälle. Anhören und manuelles
  Wiederholen bleiben möglich. Ein erfolgreicher Versuch entfernt das Flag.
- Technische Transkriptionsfehler stehen am jeweiligen Eintrag und stoppen andere
  Aufträge nicht. Bestehende Transkripte werden bei erfolglosen Wiederholungen erhalten.
- Neues Kassetten-Icon auf hellblauem Hintergrund; mit Bildgenerierung erstellt.

Validierung: 19 reguläre Tests bestanden, ein opt-in Modelltest übersprungen.
Ein zusätzlicher Simulator-UI-Test prüfte Aufklappen, Play/Pause, ±15 Sekunden
und Scrubbing mit einem synthetischen Ton. Der UI-Test setzt einen lokalen
Simulator-Eintrag „Player-Test · synthetischer Ton“ (35 Sekunden) voraus und wird
ohne diese Fixture übersprungen. Wiedergabe und Warteschlange auf dem physischen
iPhone sind noch zu bestätigen. Das Update während eines laufenden Modelldownloads
nicht installieren.

## Titel und unsichere Musikmarker (0.3.1)

Aufnahmen können im Transkript über das Stift-Symbol benannt werden. Der optionale
Titel wird getrennt vom Original-Dateinamen gespeichert und bleibt bei erneuter
Transkription erhalten. Ohne eigenen Titel wird ein kurzer Ausschnitt aus dem ersten
Satz verwendet (maximal neun Wörter/80 Zeichen); das ist ausdrücklich keine semantische
KI-Zusammenfassung. Leere Titel setzen diese automatische Anzeige wieder ein.

Ein alleinstehendes „Musik“/„[Musik]“/„(music)“ wird als unsichere Erkennung markiert,
nicht als bestätigtes Transkript oder automatischer Titel behandelt. Vorhandene
Modellausgaben bleiben in der Detailansicht sichtbar und werden nicht gelöscht.
Das behebt die Darstellung, nicht die Ursache einer falschen Audioerkennung.
Zwei zusätzliche Tests prüfen Marker/Altbestände und die Titel-Persistenz bei
unverändertem Audio-Dateinamen. 21 reguläre Tests bestanden; Modelltest übersprungen.

## Verbindung 0.3.2

Eine animierte, stilisierte Gerätekarte zeigt Suche/Verbindung. Kein systemweites
AirPods-Popup und kein maßgetreues Hardwaremodell. Reduce Motion wird respektiert.
Nach erfolgreicher Authentifizierung und Dateiliste wird die BLE-Geräte-ID gespeichert.
Der nächste ausdrücklich gestartete Scan verbindet nur dieses wiedererkannte Gerät
automatisch; andere Geräte werden zur Auswahl angezeigt. Schlüsselverwaltung ist
nach Einrichtung eingeklappt. Entfernen des Schlüssels entfernt auch Geräte-ID und
Bestätigung. Nach Hardware-Reset muss die Bestätigung vom Nutzer deaktiviert werden.
