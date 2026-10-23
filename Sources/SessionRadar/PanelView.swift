import AppKit
import RadarCore
import SwiftUI

extension SessionState {
    var label: String {
        switch self {
        case .working: "Çalışıyor"
        case .waiting: "Seni bekliyor"
        case .turnDone: "Tur bitti"
        case .problem: "Sorun var"
        case .closed: "Kapandı"
        }
    }

    var color: Color {
        switch self {
        case .working: .green
        case .waiting: .orange
        case .turnDone: .blue
        case .problem: .red
        case .closed: .gray
        }
    }
}

@MainActor private let relativeFormatter: RelativeDateTimeFormatter = {
    let f = RelativeDateTimeFormatter()
    f.locale = Locale(identifier: "tr_TR")
    f.unitsStyle = .short
    return f
}()

struct PanelView: View {
    let store: RadarStore
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Session Radar").font(.headline)
            ForEach(store.conflicts, id: \.pairKey) { c in
                Text("Çakışma: " + name(c.a) + " ↔ " + name(c.b) + " · " + c.files.joined(separator: ", "))
                    .font(.caption)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                    .background(.orange.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
            }
            if store.sessions.isEmpty {
                Text("Açık session yok").foregroundStyle(.secondary).padding(.vertical, 12)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(store.sessions) { SessionRow(session: $0, store: store) }
                    }
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
                }
                // MenuBarExtra penceresi ideal boyuta göre açılır; ScrollView'ın ideal yüksekliği 0
                .frame(height: min(contentHeight, 520))
            }
            if let error = store.lastError {
                Text(error).font(.caption2).foregroundStyle(.red).lineLimit(2)
            }
            HStack {
                Spacer()
                Button("Çık") { NSApplication.shared.terminate(nil) }
            }
        }
        .padding(12)
        .frame(width: 380)
    }

    private func name(_ id: String) -> String {
        store.sessions.first { $0.id == id }?.name ?? String(id.prefix(8))
    }
}

private struct SessionRow: View {
    let session: SessionSnapshot
    let store: RadarStore
    @State private var expanded = false

    var body: some View {
        let s = session
        VStack(alignment: .leading, spacing: 3) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Circle().fill(s.state.color).frame(width: 8, height: 8)
                    Text(s.state.label).font(.caption.weight(.semibold)).foregroundStyle(s.state.color)
                    Text(s.name).fontWeight(.medium).lineLimit(1)
                    Spacer(minLength: 4)
                    if let p = s.progress {
                        Text("\(p.done)/\(p.total)").font(.caption.monospacedDigit())
                    }
                    Text(relativeFormatter.localizedString(for: s.updatedAt, relativeTo: Date()))
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let repo = s.repoName {
                    Text([repo, s.branch].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                if let task = s.task { Text(task).font(.callout).lineLimit(1) }
                // Bash eylemi uzun ya da çok satırlı olabilir
                if let action = s.action { Text(action).font(.caption.monospaced()).lineLimit(1) }
                if let current = s.currentTopic {
                    Text("Konu: " + current + (s.openTopics > 0 ? " · \(s.openTopics) açık konu" : ""))
                        .font(.caption).lineLimit(1)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { expanded.toggle() }
            if expanded { SessionDetail(session: s, store: store) }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct SessionDetail: View {
    let session: SessionSnapshot
    let store: RadarStore

    var body: some View {
        let st = session.status
        VStack(alignment: .leading, spacing: 4) {
            if let v = st?.why { Text("Neden: " + v) }
            if let v = st?.phase { Text("Aşama: " + v) }
            if let v = st?.next { Text("Sıradaki adım: " + v) }
            ForEach(Array((st?.todo ?? []).enumerated()), id: \.offset) { _, item in
                Text((item.done ? "✓ " : "○ ") + item.text)
                    .foregroundStyle(item.done ? Color.secondary : Color.primary)
            }
            if let note = session.note {
                Text((session.state == .problem ? "Sorun: " : "Not: ") + note)
            }
            if !session.pendingFiles.isEmpty {
                Text("Bekleyen dosyalar: " + session.pendingFiles.sorted().joined(separator: ", "))
            }
            AskBox(sessionId: session.id, store: store).padding(.top, 4)
        }
        .font(.caption)
        .padding(.top, 4)
    }
}

private struct AskBox: View {
    let sessionId: String
    let store: RadarStore
    @State private var question = ""
    @State private var answer: String?
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                TextField("Bu session'a soru sor…", text: $question)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(send)
                Button("Sor", action: send).disabled(busy || question.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if busy {
                ProgressView().controlSize(.small)
            } else if let answer {
                Text(answer).textSelection(.enabled)
            }
        }
    }

    private func send() {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !busy else { return }
        busy = true
        answer = nil
        Task {
            answer = await store.ask(q, about: sessionId)
            busy = false
        }
    }
}
