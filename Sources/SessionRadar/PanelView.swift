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
                }
                .frame(maxHeight: 520)
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
        let topic = topicSummary(s.status?.topics)
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
                if let current = topic.current {
                    Text("Konu: " + current + (topic.open > 0 ? " · \(topic.open) açık konu" : ""))
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
            if let topics = st?.topics, !topics.isEmpty {
                TopicFlow(topics: topics).padding(.top, 4)
            }
            AskBox(sessionId: session.id, store: store).padding(.top, 4)
        }
        .font(.caption)
        .padding(.top, 4)
    }
}

private struct TopicFlow: View {
    let topics: [TopicItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Konu akışı").font(.caption.bold()).padding(.bottom, 4)
            ForEach(Array(topics.enumerated()), id: \.offset) { i, t in
                let last = i == topics.count - 1
                HStack(alignment: .top, spacing: 6) {
                    marker(t.state).frame(width: 10, height: 14)
                    title(t)
                }
                .padding(.bottom, last ? 0 : 6)
                // konuları birbirine bağlayan ince dikey çizgi
                .background(alignment: .topLeading) {
                    if !last {
                        Rectangle().fill(.tertiary).frame(width: 1).padding(.top, 12).padding(.leading, 4.5)
                    }
                }
            }
        }
    }

    @ViewBuilder private func marker(_ state: String) -> some View {
        switch state {
        case "active": Circle().fill(Color.accentColor).frame(width: 8, height: 8)
        case "done": Text("✓").font(.caption2).foregroundStyle(.secondary)
        default: Circle().strokeBorder(.secondary, lineWidth: 1).frame(width: 8, height: 8)
        }
    }

    @ViewBuilder private func title(_ t: TopicItem) -> some View {
        switch t.state {
        case "active": Text(t.title).font(.caption.bold()).foregroundStyle(Color.accentColor)
        case "done": Text(t.title).font(.caption).foregroundStyle(.secondary)
        default:
            HStack(spacing: 4) {
                Text(t.title).font(.caption)
                Text("açık").font(.caption2).padding(.horizontal, 4).background(.orange.opacity(0.2), in: Capsule())
            }
        }
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
