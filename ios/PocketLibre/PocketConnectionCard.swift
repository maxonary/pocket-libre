import SwiftUI

/// Stylized recorder illustration, not a claim of exact hardware geometry.
struct PocketConnectionCard: View {
    let connected: Bool
    let searching: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle().fill(OntoraStyle.blue.opacity(0.05)).frame(width: 210, height: 210)
                RoundedRectangle(cornerRadius: 28)
                    .fill(LinearGradient(colors: [Color(white: 0.5), Color(white: 0.16), Color(white: 0.32)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay {
                        RoundedRectangle(cornerRadius: 28).strokeBorder(.white.opacity(0.4), lineWidth: 1)
                    }
                    .overlay {
                        VStack(spacing: 14) {
                            Capsule().fill(.black.opacity(0.65)).frame(width: 34, height: 5)
                            Spacer()
                            Image(systemName: "waveform").font(.title2).foregroundStyle(.white.opacity(0.8))
                            Spacer()
                            Circle().fill(connected ? OntoraStyle.blue : .gray).frame(width: 28, height: 28)
                                .overlay(Circle().stroke(.white.opacity(0.5), lineWidth: 2))
                        }.padding(22)
                    }
                    .frame(width: 112, height: 176)
                    .rotation3DEffect(.degrees(reduceMotion ? 0 : (appeared ? -12 : 12)), axis: (x: 0.3, y: 1, z: 0))
                    .shadow(color: .black.opacity(0.18), radius: 14, x: 8, y: 14)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.7), value: appeared)
                    .accessibilityHidden(true)
            }
            VStack(spacing: 6) {
                Text(connected ? "Pocket ist verbunden" : "Dein Pocket").font(.title2.weight(.medium))
                if connected {
                    Label("Bereit zum Importieren", systemImage: "checkmark.circle.fill").foregroundStyle(OntoraStyle.blue)
                } else if searching {
                    HStack { ProgressView(); Text("Einen Moment …") }.foregroundStyle(.secondary)
                } else {
                    Text("Deine Aufnahmen. Direkt auf dein iPhone.").foregroundStyle(.secondary)
                }
            }.font(.subheadline)
        }.padding(.vertical, 20)
            .onAppear { appeared = true }
            .onChange(of: connected) { _, _ in appeared.toggle() }
    }
}
