# Bestehenden Pocket-Schlüssel mit iPhone und Mac übernehmen

Kein Reset, kein Entkoppeln, kein `pair` und kein neu erzeugter Schlüssel.
Der vorhandene Schlüssel ist derzeit nicht in der lokalen Pocket-Libre-Konfiguration
hinterlegt. Ein Export aus der Hersteller-App ist hier nicht nachgewiesen.

## Was wir wissen

Das im Repository dokumentierte Protokoll authentifiziert eine Verbindung mit
`APP&SK&` gefolgt von 16 alphanumerischen Zeichen. Ein Mitschnitt einer normalen
Wiederverbindung der bereits gekoppelten Hersteller-App kann diesen Wert enthalten.
Unsere App kann weder den privaten Speicher der Hersteller-App noch deren laufende
Bluetooth-Verbindung direkt auslesen. Ein normaler BLE-Scan liefert keinen Schlüssel.
Ob die aktuelle iOS-Diagnose den vollständigen Payload enthält, ist noch ungetestet;
daher ist dieser Weg ein Versuch, keine garantierte Extraktionsmethode.

## Vorbereitung – noch nicht ausgeführt

Apple stellt PacketLogger über [Additional Tools for Xcode](https://developer.apple.com/bluetooth/)
bereit. Die aktuellen [Bluetooth-Profile und Anleitungen](https://developer.apple.com/feedback-assistant/profiles-and-logs/?name=bluetooth)
liegen bei Apple; der Abruf der ausführlichen Anleitung erfordert eine Anmeldung.
PacketLogger wurde auf diesem Mac noch nicht gefunden. Das Diagnoseprofil wurde inzwischen vom Nutzer installiert; der erforderliche Neustart steht noch aus.

1. Passende Additional Tools und die aktuelle iOS-Bluetooth-Anleitung von Apple
   herunterladen. Die dort beschriebenen Schritte anhand der installierten iOS-Version
   prüfen. Keine aus älteren Anleitungen geratenen Menüschritte verwenden.
2. Erst nach Rücksprache das erforderliche Diagnoseprofil bzw. Logging aktivieren.
   Das verändert Geräteeinstellungen und benötigt eventuell einen Neustart.
3. Vor dem Öffnen der Hersteller-App deren Internetzugang unterbrechen, damit keine
   privaten Aufnahmen hochgeladen werden. Dafür nach Rücksprache am iPhone WLAN und
   Mobilfunk deaktivieren und Bluetooth eingeschaltet lassen; bestehende Kopplung behalten.
4. Mit Apples beschriebenem Verfahren die normale Wiederverbindung der Hersteller-App
   zum Pocket aufzeichnen. Nicht zurücksetzen, nicht entkoppeln, keine Testschlüssel senden.
5. Mitschnitt ausschließlich lokal auf dem Mac speichern. Hersteller-App schließen,
   bevor Internetzugang wiederhergestellt wird. Diagnoseprofil/Logging anschließend nach
   Apples Anleitung wieder entfernen/deaktivieren.

## Lokale Extraktion und Import

Der vorbereitete Helfer liest einen lokalen binären HCI-/PacketLogger-Mitschnitt.
Er sendet keine Daten und gibt den Schlüssel nicht im Terminal aus:

```sh
cd /Users/maximilianarnold/Repositories/pocket-libre
uv run python scripts/extract_pocket_key.py /absoluter/pfad/capture.pklg
```

Bei genau einem eindeutigen Schlüssel entsteht `~/PocketLocalSetup/pocket-key.json`
mit Dateirechten 0600. Bestehende Dateien werden nicht überschrieben. Fehlende,
mehrdeutige oder redigierte Werte führen zum Abbruch. Das Werkzeug rekonstruiert keine
über mehrere Pakete fragmentierten Schlüssel; ein negativer Befund beweist daher nicht,
dass die Diagnose prinzipiell ungeeignet ist.

Die Datei lokal, beispielsweise per AirDrop, auf das iPhone übertragen und in Pocket
Libre unter **Pocket drahtlos verbinden** als Schlüsseldatei importieren. Nicht in den
Chat, ein Issue oder ein Cloud-Laufwerk kopieren. Die App speichert den Schlüssel im
nicht synchronisierten, gerätegebundenen iOS-Schlüsselbund. Vor der Verbindung bestätigen,
dass der Pocket bereits gekoppelt und nicht zurückgesetzt ist: Bei einem zurückgesetzten
Pocket könnte das gleiche Protokollkommando einen neuen Schlüssel setzen.

Nach erfolgreicher Übernahme die exportierte JSON-Datei und nicht mehr benötigte
Diagnosekopien auf beiden Geräten selbst entfernen. Die Diagnose kann auch andere
Bluetooth-Daten enthalten. Der Helfer löscht nichts automatisch.

## Offene Abnahme

- Enthält die aktuelle Apple-Diagnose tatsächlich den bestehenden Schlüssel?
- Akzeptiert Pocket diesen Schlüssel ohne Änderung seiner Kopplung?
- Funktionieren BLE-Dateiliste und Import einer harmlosen Aufnahme?
- Funktioniert WLAN auf diesem Pocket/iPhone mit Firmware 1.7 oder 1.8?

Bis dahin sind Bluetooth und WLAN implementiert und simuliert getestet, aber nicht
als funktionierende Hardware-Integration bestätigt.

## Diagnose-Vorbereitung am 15. November 2026

Die Apple-PDF „Bluetooth Logs: iOS“ wurde im angemeldeten Browser gelesen
(der PDF-Fuß enthält Copyright 2023; sie ist weiterhin von Apples aktueller Seite verlinkt).
Sie beschreibt: Bluetooth-Profil auf dem iPhone installieren, iPhone neu starten,
Verbindung reproduzieren, durch kurzes gleichzeitiges Drücken und Loslassen beider
Lautstärketasten und der Seitentaste eine sysdiagnose auslösen, zehn Minuten warten,
und die Datei unter Einstellungen → Datenschutz → Analyse & Verbesserungen →
Analysedaten lokal per AirDrop auf den Mac übertragen. Nicht lange gedrückt halten.
Wir senden keinen Bericht an Apple. Das Profil läuft laut PDF nach drei Tagen ab;
zum gezielten Abschalten unter Allgemein → VPN & Geräteverwaltung entfernen und
anschließend neu starten. Die komplette sysdiagnose enthält weitere Gerätediagnosen;
wir untersuchen nur die lokal extrahierten Bluetooth-Dateien und geben keine Rohlogs
im Chat aus. Ob der benötigte SK-Payload enthalten ist, bleibt offen.

Der Nutzer hat die Profilinstallation bestätigt; der erforderliche Neustart und der Mitschnitt stehen noch aus. Der direkte
PacketLogger-DMG-Download wurde von Dia blockiert; diese Sperre wurde nicht umgangen.
Apples dokumentierter sysdiagnose-Weg kann zunächst ohne PacketLogger vorbereitet werden.

- [Apple-Profil](https://developer.apple.com/services-account/download?path=%2FiOS%2FiOS_Logs%2FiOSBluetoothLogging.mobileconfig)
- [Gelesene Apple-PDF](https://developer.apple.com/services-account/download?path=%2FiOS%2FiOS_Logs%2FBluetooth_Logging_Instructions.pdf)

Die App enthält ab Version 0.2.2 unter „Vom Pocket importieren“ → „Wo finde ich den Schlüssel?“ eine lokale Anleitung. Es wurde noch kein realer Sitzungsschlüssel extrahiert.

## Erfolgreiche Extraktion am 15. November 2026

Aus der vom Nutzer lokal übertragenen sysdiagnose wurden ausschließlich zwei
Bluetooth-PacketLogger-Dateien lokal extrahiert. Ein Mitschnitt enthielt genau einen
eindeutigen APP&SK-Schlüssel und danach MCU&SK&OK. Die lokale Importdatei wurde unter
`~/PocketLocalSetup/pocket-key.json` mit Rechten 0600 erstellt. Kein Schlüssel oder
Rohlog wurde ausgegeben oder hochgeladen. Dies bestätigt die Extraktion für dieses
Gerät; die Authentifizierung mit unserer iPhone-App und der eigentliche Import
sind noch separat zu testen. Diagnoseprofil und temporäre Dateien sind anschließend
vom Nutzer zu entfernen; bisher wurde nichts automatisch gelöscht.
