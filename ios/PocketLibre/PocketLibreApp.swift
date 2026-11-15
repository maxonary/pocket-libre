import SwiftUI
import AVFoundation
import UniformTypeIdentifiers
import Combine

@MainActor
final class AppModel: ObservableObject {
    @Published var recordings: [Recording] = []
    @Published var modelReady = false
    @Published private var exclusiveWork = false
    var busy: Bool { exclusiveWork || queue.running }
    @Published var autoTranscribe = UserDefaults.standard.object(forKey: "autoTranscribe") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(autoTranscribe, forKey: "autoTranscribe")
            if autoTranscribe { transcribeAll() }
        }
    }
    let queue = TranscriptionQueue()
    let playback = AudioPlayback()
    private var queueChanges: AnyCancellable?
    init() {
        queue.process = { [weak self] id in
            guard let self, let record = self.recordings.first(where: { $0.id == id }) else { return }
            UIApplication.shared.isIdleTimerDisabled = true
            defer { UIApplication.shared.isIdleTimerDisabled = false }
            try await self.transcribe(record)
            await self.refresh()
        }
        queueChanges = queue.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }
    @Published var status = ""
    @Published var downloadProgress: Double?
    @Published var error: String?
    private let library = LocalLibrary(root: LocalLibrary.defaultRoot)
    private let transcriber = OfflineTranscriber(root: LocalLibrary.defaultRoot)
    private var work: Task<Void, Never>?

    private var didRestoreQueue = false
    func refresh() async {
        do {
            recordings = try await library.all()
            modelReady = await transcriber.isInstalled()
            if !didRestoreQueue {
                didRestoreQueue = true
                if autoTranscribe { transcribeAll() }
            }
        } catch { self.error = "Die lokale Bibliothek konnte nicht geöffnet werden: \(error.localizedDescription)" }
    }
    func importWirelessFile(_ url: URL) async throws -> Recording {
        let record = try await library.importFile(url)
        await refresh()
        return record
    }
    func transcribeImported(ids: [String]) {
        guard autoTranscribe else { return }
        queue.blocked = !modelReady || exclusiveWork
        queue.enqueue(recordings.filter { ids.contains($0.id) && $0.transcript == nil && $0.transcriptionFlag == nil }.map(\.id))
    }
    func transcribeAll() {
        queue.blocked = !modelReady || exclusiveWork
        queue.enqueue(recordings.filter { $0.transcript == nil && $0.transcriptionFlag == nil }.map(\.id))
    }
    func preparePlayback(_ recording: Recording) async {
        await playback.load(recording, url: library.audioURL(recording))
    }
    func installModel() {
        perform("Sprachmodell wird geladen …") {
            try await self.transcriber.install { value in
                Task { @MainActor in self.downloadProgress = value }
            }
            await self.refresh()
            if self.autoTranscribe { self.transcribeAll() }
            self.status = "Sprachmodell bereit."
        }
    }
    func importFiles(_ urls: [URL]) {
        perform("Aufnahmen werden kopiert …") {
            var imported: [Recording] = []
            var failures: [String] = []
            for (index, url) in urls.enumerated() {
                try Task.checkCancellation()
                self.status = "Import \(index + 1) von \(urls.count)"
                do {
                    let recording = try await self.library.importFile(url)
                    if !imported.contains(where: { $0.id == recording.id }) { imported.append(recording) }
                } catch { failures.append("\(url.lastPathComponent): \(error.localizedDescription)") }
            }
            await self.refresh()
            self.transcribeImported(ids: imported.map(\.id))
            self.status = self.modelReady ? "Import abgeschlossen. Originale bleiben erhalten." : "Importiert. Lade das Sprachmodell für die Transkription."
            if !failures.isEmpty { self.error = failures.joined(separator: "\n\n") }
        }
    }
    func rename(_ recording: Recording, title: String) async {
        do { try await library.setTitle(title, for: recording.id); await refresh() }
        catch { self.error = error.localizedDescription }
    }
    func retry(_ recording: Recording) {
        queue.blocked = !modelReady || exclusiveWork
        queue.enqueue([recording.id])
    }
    private func transcribe(_ recording: Recording) async throws {
        let url = await library.audioURL(recording)
        let text = try await transcriber.transcribe(url)
        if let reason = SpeechResult.reviewReason(text) {
            try await library.flagForReview(recording.id, reason: reason)
            return
        }
        try await library.setTranscript(text, for: recording.id)
    }
    private func perform(_ message: String, operation: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        exclusiveWork = true; queue.blocked = true; status = message; error = nil
        UIApplication.shared.isIdleTimerDisabled = true
        work = Task {
            defer {
                exclusiveWork = false; downloadProgress = nil; work = nil
                queue.blocked = !modelReady
                UIApplication.shared.isIdleTimerDisabled = false
            }
            do { try await operation() }
            catch is CancellationError { status = "Gestoppt. Importierte Aufnahmen bleiben gespeichert." }
            catch { self.error = error.localizedDescription; status = "Bitte erneut versuchen." }
            await refresh()
        }
    }
    func stop() { queue.stop(); work?.cancel(); status = "Wird gestoppt …" }

}

@main
struct PocketLibreApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = AppModel()
    var body: some Scene {
        WindowGroup {
            LibraryView().environmentObject(model).task { await model.refresh() }
                .overlay {
                    if scenePhase != .active {
                        ZStack {
                            Color(.systemBackground).ignoresSafeArea()
                            Label("Pocket Libre", systemImage: "lock.shield").font(.title2)
                        }
                    }
                }
        }
    }
}

enum OntoraStyle {
    static let blue = Color(red: 0, green: 47.0 / 255, blue: 167.0 / 255)
    static let background = Color.white
}

struct LibraryView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showImporter = false
    @State private var showSettings = false
    @State private var showPocket = false
    @State private var expandedID: String?
    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 20) {
                        if model.recordings.isEmpty {
                        Text("Deine Stimme.\nBei dir.")
                            .font(.largeTitle.weight(.regular)).tracking(-1)
                        Text("Aufnehmen. Importieren. Auf Deutsch lesen.")
                            .foregroundStyle(.secondary)
                        }
                        Button { showPocket = true } label: {
                            Label("Vom Pocket importieren", systemImage: "waveform")
                                .frame(maxWidth: .infinity).padding(.vertical, 9)
                        }.buttonStyle(.borderedProminent).disabled(model.busy)
                        Button { showImporter = true } label: {
                            Label("Aus Dateien importieren", systemImage: "folder")
                                .frame(maxWidth: .infinity).frame(minHeight: 44)
                        }.disabled(model.busy)
                    }.padding(.vertical, 12)
                }.listRowSeparator(.hidden)
                if !model.modelReady {
                    Section {
                        Button { showSettings = true } label: {
                            Label("Deutsche Transkription einrichten", systemImage: "arrow.down.circle")
                                .frame(minHeight: 44)
                        }.disabled(model.busy)
                    }
                }
                if model.busy || !model.status.isEmpty {
                    Section {
                        HStack {
                            if model.busy { ProgressView() }
                            Text(model.queue.running ? "Transkription läuft · \(model.queue.pending.count) warten" : model.status).font(.subheadline)
                        }
                        if let value = model.downloadProgress { ProgressView(value: value) }
                        if model.busy {
                            Text("App geöffnet lassen.").font(.caption).foregroundStyle(.secondary)
                            Button("Stoppen", role: .cancel) { model.stop() }
                        }
                    }
                }
                Section {
                    if model.recordings.isEmpty {
                        ContentUnavailableView("Noch keine Aufnahmen", systemImage: "waveform",
                            description: Text("Importiere deine erste Aufnahme. Das Original bleibt auf deinem Pocket."))
                    }
                    if model.recordings.contains(where: { $0.transcript == nil && $0.transcriptionFlag == nil }) {
                        Button("Alle offenen transkribieren") { model.transcribeAll() }
                            .disabled(!model.modelReady)
                    }
                    ForEach(model.recordings) { recording in
                        VStack(alignment: .leading, spacing: 12) {
                            Button {
                                if expandedID == recording.id { expandedID = nil; model.playback.pause() }
                                else {
                                    expandedID = recording.id
                                    Task { await model.preparePlayback(recording) }
                                }
                            } label: {
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(recording.displayTitle).font(.headline).foregroundStyle(.primary)
                                        Text(recording.importedAt.formatted(date: .abbreviated, time: .shortened))
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(AudioPlayback.time(recording.duration)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            TranscriptionStatus(recording: recording)
                            if expandedID == recording.id {
                                AudioPlayerView(playback: model.playback)
                                HStack {
                                    Button("Transkribieren") { model.retry(recording) }
                                        .disabled(!model.modelReady || model.queue.contains(recording.id))
                                    Spacer()
                                    NavigationLink("Transkript") { RecordingView(id: recording.id) }
                                }.font(.subheadline).frame(minHeight: 44)
                            } else if let text = recording.transcript, recording.reviewFlag == nil {
                                Text(text).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }.padding(.vertical, 8)
                    }

                } header: {
                    HStack { Text("Aufnahmen"); Spacer(); Text("\(model.recordings.count)") }
                } footer: {
                    Label("Nur auf deinem iPhone", systemImage: "lock")
                        .font(.caption).padding(.top, 16)
                }
            }
            .listStyle(.plain).scrollContentBackground(.hidden).background(OntoraStyle.background)
            .navigationTitle("Pocket Libre").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "slider.horizontal.3") }
                        .accessibilityLabel("Einrichtung und Datenschutz")
                }
            }
            .navigationDestination(isPresented: $showPocket) { WirelessView() }
            .sheet(isPresented: $showSettings) { SetupView().environmentObject(model) }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.audio], allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls): model.importFiles(urls)
                case .failure(let error): model.error = error.localizedDescription
                }
            }
            .alert("Hinweis", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
                Button("OK") { model.error = nil }
            } message: { Text(model.error ?? "") }
        }.tint(OntoraStyle.blue).preferredColorScheme(.light)
    }
}

struct SetupView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDownload = false
    var body: some View {
        NavigationStack {
            Form {
                Section("Deutsche Transkription") {
                    Toggle("Importe automatisch transkribieren", isOn: $model.autoTranscribe)
                    Label(model.modelReady ? "Auf diesem iPhone bereit" : "Einmalig Sprachmodell laden",
                          systemImage: model.modelReady ? "checkmark.circle" : "arrow.down.circle")
                    Text("Danach wird Sprache direkt auf diesem iPhone verarbeitet. Ohne Mac oder Cloud.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if !model.modelReady {
                        Button("Sprachmodell laden") { confirmDownload = true }.disabled(model.busy)
                    } else {
                        DisclosureGroup("Modell verwalten") {
                            Button("Modell erneut laden") { confirmDownload = true }.disabled(model.busy)
                        }
                    }
                    if let value = model.downloadProgress { ProgressView(value: value) }
                }
                Section("Privat gespeichert") {
                    Text("Aufnahmen und Texte bleiben lokal und sind von Geräte-Backups ausgeschlossen. Beim Löschen der App gehen diese Kopien verloren. Die Originale auf dem Pocket bleiben erhalten.")
                    Text("Geschützt durch iOS-Dateischutz und deinen Gerätecode. Ein separater verschlüsselter Journal-Vault ist noch nicht enthalten.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    NavigationLink("Open-Source-Lizenzen") {
                        ScrollView {
                            Text((try? String(contentsOf: Bundle.main.url(forResource: "ThirdPartyNotices", withExtension: "txt")!, encoding: .utf8)) ?? "")
                                .font(.footnote).padding().textSelection(.enabled)
                        }.navigationTitle("Lizenzen")
                    }
                }
            }.navigationTitle("Einrichtung").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } } }
                .confirmationDialog("Sprachmodell herunterladen?", isPresented: $confirmDownload, titleVisibility: .visible) {
                    Button("Modell laden") { model.installModel(); dismiss() }
                } message: {
                    Text("Mehrere Hundert MB werden von Hugging Face geladen. Dabei werden keine Aufnahmen übertragen.")
                }
        }.tint(OntoraStyle.blue).preferredColorScheme(.light)
    }
}

struct RecordingView: View {
    @EnvironmentObject private var model: AppModel
    let id: String
    @State private var editingTitle = false
    @State private var draftTitle = ""
    var body: some View {
        if let recording = model.recordings.first(where: { $0.id == id }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text(recording.displayTitle).font(.title2)
                    if recording.title == nil, recording.transcript != nil, recording.reviewFlag == nil {
                        Text("Titel aus Textanfang · antippen zum Umbenennen")
                            .font(.caption).foregroundStyle(.secondary)
                            .onTapGesture { draftTitle = recording.displayTitle; editingTitle = true }
                    }
                    AudioPlayerView(playback: model.playback)
                    TranscriptionStatus(recording: recording)
                    if let transcript = recording.transcript {
                        if recording.reviewFlag != nil {
                            Text("Ungeprüfte Modellausgabe – bitte mit der Aufnahme vergleichen.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        Text(transcript).font(.title3).textSelection(.enabled)
                        ShareLink(item: transcript) { Label("Text exportieren", systemImage: "square.and.arrow.up") }
                        Text("Automatisch erkannt. Bitte wichtige Inhalte mit der Aufnahme abgleichen.")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else {
                        Text("Noch kein Transkript. Die Aufnahme ist bereits lokal gespeichert.").foregroundStyle(.secondary)
                    }
                    Button(recording.transcript == nil ? "Auf Deutsch transkribieren" : "Erneut transkribieren") {
                        model.retry(recording)
                    }.buttonStyle(.borderedProminent).disabled(model.queue.contains(recording.id) || !model.modelReady)
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            }.navigationTitle("Aufnahme").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { draftTitle = recording.displayTitle; editingTitle = true } label: { Image(systemName: "pencil") }
                            .accessibilityLabel("Titel ändern")
                    }
                }
                .alert("Titel ändern", isPresented: $editingTitle) {
                    TextField("Titel", text: $draftTitle)
                    Button("Speichern") { Task { await model.rename(recording, title: draftTitle) } }
                        .disabled(draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).count > 120)
                    Button("Abbrechen", role: .cancel) { }
                } message: { Text("Leer lassen, um wieder den Textanfang zu verwenden. Der ursprüngliche Dateiname bleibt erhalten.") }
                .task(id: recording.id) { await model.preparePlayback(recording) }
                .onDisappear { model.playback.pause() }
        }
    }
}

struct TranscriptionStatus: View {
    @EnvironmentObject private var model: AppModel
    let recording: Recording
    var body: some View {
        Group {
            if model.queue.active == recording.id {
                HStack(spacing: 8) { ProgressView(); Text("Wird auf Deutsch transkribiert …") }
            } else if let index = model.queue.pending.firstIndex(of: recording.id) {
                Label(model.modelReady ? "Wartet · Platz \(index + 1)" : "Wartet auf Sprachmodell", systemImage: "clock")
            } else if let failure = model.queue.failures[recording.id] {
                Label(failure, systemImage: "exclamationmark.circle")
            } else if let flag = recording.reviewFlag {
                Label(flag + " · Bitte anhören", systemImage: "flag")
            } else if recording.transcript != nil {
                Label("Transkribiert", systemImage: "checkmark.circle")
            }
        }.font(.footnote).foregroundStyle(.secondary).accessibilityElement(children: .combine)
    }
}
