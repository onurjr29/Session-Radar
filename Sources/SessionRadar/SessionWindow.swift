import RadarCore
import SwiftUI

private let timeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "tr_TR")
    f.dateFormat = "HH:mm"
    return f
}()

private let dayTimeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "tr_TR")
    f.dateFormat = "d MMM HH:mm"
    return f
}()

struct SessionWindow: View {
    let store: RadarStore

    var body: some View {
        NavigationSplitView {
            List(store.sessions, selection: Bindable(store).selectedSessionId) { s in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Circle().fill(s.state.color).frame(width: 8, height: 8)
                        Text(s.name).fontWeight(.medium).lineLimit(1)
                    }
                    if let t = s.currentTopic { Text(t).font(.caption).lineLimit(1) }
                    Text(s.state.label).font(.caption2).foregroundStyle(s.state.color)
                }
                .tag(s.id)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 260, max: 360)
        } detail: {
            if let s = store.sessions.first(where: { $0.id == store.selectedSessionId }) {
                SessionDetailPane(session: s, history: store.histories[s.id], store: store)
                    .id(s.id)
            } else {
                Text("Açık session yok").foregroundStyle(.secondary)
            }
        }
        .onAppear(perform: ensureSelection)
        .onChange(of: store.sessions.map(\.id)) { ensureSelection() }
    }

    // seçim yoksa ya da session kapanıp listeden düştüyse ilkini seç
    private func ensureSelection() {
        if !store.sessions.contains(where: { $0.id == store.selectedSessionId }) {
            store.selectedSessionId = store.sessions.first?.id
        }
    }
}

private struct SessionDetailPane: View {
    let session: SessionSnapshot
    let history: SessionHistory?
    let store: RadarStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if let first = history?.requests.first { start(first) }
                flow
                now
                AskBox(sessionId: session.id, store: store)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.name).font(.title2.bold())
            if let repo = session.repoName {
                Text([repo, session.branch].compactMap { $0 }.joined(separator: " · "))
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                Circle().fill(session.state.color).frame(width: 8, height: 8)
                Text(session.state.label).foregroundStyle(session.state.color)
            }
        }
    }

    private func start(_ r: Request) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Başlangıç").font(.headline)
            Text(r.text).lineLimit(6).textSelection(.enabled)
            if let at = r.at { Text(dayTimeFormatter.string(from: at)).font(.caption).foregroundStyle(.secondary) }
        }
    }

    private var flow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("Konu akışı").font(.headline)
                if history?.grouping == true {
                    ProgressView().controlSize(.small)
                    Text("Gruplanıyor…").font(.caption).foregroundStyle(.secondary)
                }
            }
            if (history?.failures ?? 0) >= 3 {
                Text("Konu gruplama tekrar tekrar başarısız oldu, daha seyrek deneniyor.")
                    .font(.caption).foregroundStyle(.orange)
            }
            if let topics = history?.topics, !topics.isEmpty {
                let requests = history?.requests ?? []
                ForEach(Array(topics.enumerated()), id: \.element.id) { i, t in
                    TopicCard(topic: t, requests: requests, closed: session.state == .closed, isLast: i == topics.count - 1)
                }
            } else {
                Text("Konu başlıkları henüz çıkarılmadı").foregroundStyle(.secondary)
                RequestList(requests: history?.requests ?? [])
            }
        }
    }

    private var now: some View {
        let st = session.status
        return VStack(alignment: .leading, spacing: 4) {
            Text("Şu an").font(.headline)
            if let v = session.currentTopic { Text("Konu: " + v) }
            if let v = session.action { Text(v).font(.caption.monospaced()).lineLimit(2) }
            if let v = st?.task { Text("Görev: " + v) }
            if let v = st?.next { Text("Sıradaki adım: " + v) }
            ForEach(Array((st?.todo ?? []).enumerated()), id: \.offset) { _, item in
                Text((item.done ? "✓ " : "○ ") + item.text)
                    .foregroundStyle(item.done ? Color.secondary : Color.primary)
            }
            if let note = session.note {
                Text((session.state == .problem ? "Sorun: " : "Not: ") + note)
            }
        }
        .font(.callout)
    }
}

private struct TopicCard: View {
    let topic: Topic
    let requests: [Request]
    let closed: Bool
    let isLast: Bool
    @State private var expanded = false

    var body: some View {
        let active = topic.state == "active"
        let mine = requests.filter { topic.requests.contains($0.index) }
        HStack(alignment: .top, spacing: 10) {
            // solda nokta ve sonraki konuya uzanan dikey çizgi
            VStack(spacing: 0) {
                Circle().fill(active ? Color.accentColor : Color.secondary).frame(width: 10, height: 10).padding(.top, 5)
                if !isLast { Rectangle().fill(.quaternary).frame(width: 2).frame(maxHeight: .infinity) }
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(topic.title).fontWeight(active ? .bold : .medium)
                        .foregroundStyle(active ? Color.accentColor : Color.primary)
                    Text(topicStateLabel(topic.state, sessionClosed: closed))
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if let r = range(mine) { Text(r).font(.caption).foregroundStyle(.secondary) }
                }
                Text(topic.summary).font(.callout)
                if expanded { RequestList(requests: mine).padding(.top, 4) }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(active ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
            .onTapGesture { expanded.toggle() }
        }
    }

    private func range(_ rs: [Request]) -> String? {
        let dates = rs.compactMap(\.at)
        guard let lo = dates.min(), let hi = dates.max() else { return nil }
        let cal = Calendar.current
        let f = cal.isDate(lo, inSameDayAs: hi) ? timeFormatter : dayTimeFormatter
        let a = f.string(from: lo), b = f.string(from: hi)
        return a == b ? a : a + " – " + b
    }
}

private struct RequestList: View {
    let requests: [Request]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(requests, id: \.index) { r in
                Text("#\(r.index) · " + (r.at.map { timeFormatter.string(from: $0) } ?? "--:--") + " · " + r.text)
                    .font(.caption).lineLimit(3)
            }
        }
    }
}
