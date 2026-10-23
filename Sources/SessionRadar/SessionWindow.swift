import RadarCore
import SwiftUI

private let hourMinute = Date.FormatStyle.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
    .locale(Locale(identifier: "tr_TR"))

struct SessionWindow: View {
    let store: RadarStore

    var body: some View {
        NavigationSplitView {
            SessionSidebar(sessions: store.sessions, now: store.now, selection: Bindable(store).selectedSessionId)
                .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 320)
        } detail: {
            if let s = store.sessions.first(where: { $0.id == store.selectedSessionId }) {
                SessionDetail(session: s, history: store.histories[s.id], store: store)
            } else {
                Text("Açık session yok").foregroundStyle(.secondary)
            }
        }
        .onAppear(perform: ensureSelection)
        .onChange(of: store.sessions.map(\.id)) { ensureSelection() }
        // pencere kapalıyken seçim gruplama kuyruğunda öncelik almasın
        .onDisappear { store.selectedSessionId = nil }
    }

    // seçim yoksa ya da session kapanıp listeden düştüyse ilkini seç
    private func ensureSelection() {
        if !store.sessions.contains(where: { $0.id == store.selectedSessionId }) {
            store.selectedSessionId = store.sessions.first?.id
        }
    }
}

/// Session listesi; boş bölümler gizli, sıra sortForDisplay'den gelir.
private struct SessionSidebar: View {
    let sessions: [SessionSnapshot]
    /// bekleme süreleri bu ana göre
    let now: Date
    @Binding var selection: String?

    private static let groups: [(title: String, states: Set<SessionState>)] = [
        ("Seni bekliyor", [.waiting]), ("Sorun var", [.problem]), ("Çalışıyor", [.working]), ("Bitti", [.turnDone, .closed]),
    ]

    var body: some View {
        List(selection: $selection) {
            ForEach(Self.groups, id: \.title) { g in
                let rows = sessions.filter { g.states.contains($0.state) }
                if !rows.isEmpty {
                    Section(g.title) {
                        ForEach(rows) { s in
                            HStack(spacing: 8) {
                                Circle().fill(s.state.color).frame(width: 8, height: 8)
                                Text(s.name).lineLimit(1)
                                Spacer(minLength: 4)
                                if let t = trailingText(s, now: now) {
                                    Text(t).font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
                                }
                            }
                            .tag(s.id)
                        }
                    }
                }
            }
        }
    }
}

private struct SessionDetail: View {
    let session: SessionSnapshot
    let history: SessionHistory?
    let store: RadarStore
    @State private var selected: Int?
    @State private var focus: FocusRequest?
    @State private var asking = false

    var body: some View {
        let topics = history?.topics ?? []
        let requests = history?.requests ?? []
        let subtitle: [String?] = [session.repoName, session.branch, session.state.label]
        FlowCanvas(session: session, topics: topics, requests: requests, selected: $selected, focus: focus)
            // session değişince tuval sıfırdan kurulur ve şu anki konuyla açılır
            .id(session.id)
            .inspector(isPresented: .constant(true)) {
                StepsList(session: session, topics: topics, requests: requests, selected: selected) { id in
                    selected = id
                    focus = FocusRequest(topicId: id, serial: (focus?.serial ?? 0) + 1)
                }
                .inspectorColumnWidth(min: 220, ideal: 260, max: 340)
            }
            .navigationTitle(session.name)
            .navigationSubtitle(subtitle.compactMap { $0 }.joined(separator: " · "))
            .toolbar {
                if history?.grouping == true {
                    ToolbarItem {
                        ProgressView().controlSize(.small).help("Gruplanıyor…")
                    }
                }
                if (history?.failures ?? 0) >= 3 {
                    ToolbarItem {
                        let text = "Konu gruplama tekrar tekrar başarısız oldu, daha seyrek deneniyor."
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .help(text)
                            .accessibilityLabel(text)
                    }
                }
                ToolbarItem {
                    Button { asking.toggle() } label: { Label("Soru sor", systemImage: "bubble.left") }
                        .help("Soru sor")
                        .popover(isPresented: $asking, arrowEdge: .bottom) {
                            AskBox(sessionId: session.id, store: store).padding(14).frame(width: 360)
                        }
                }
            }
            .onChange(of: topics, initial: true) { selected = resolveTopicSelection(selected, topics: topics) }
            .onChange(of: session.id) { selected = resolveTopicSelection(nil, topics: topics) }
    }
}

/// "Adımlar": konular akış sırasıyla; seçili satır genişler.
private struct StepsList: View {
    let session: SessionSnapshot
    let topics: [Topic]
    let requests: [Request]
    let selected: Int?
    let select: (Int) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let byId = Dictionary(topics.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        ScrollViewReader { proxy in
            List {
                Section("Adımlar") {
                    if topics.isEmpty {
                        Text("Konu başlıkları henüz çıkarılmadı").foregroundStyle(.secondary).lineLimit(nil)
                    }
                    ForEach(flowLayout(topics), id: \.topicId) { n in
                        if let t = byId[n.topicId] { row(t, number: n.column + 1, branch: n.lane != 0) }
                    }
                }
            }
            .listStyle(.sidebar)
            .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: selected)
            // tuvalde seçilen kart listede görünür olsun; açılışta liste yerleştikten sonra
            .task(id: selected) {
                if let selected { withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) { proxy.scrollTo(selected) } }
            }
        }
    }

    private func row(_ t: Topic, number: Int, branch: Bool) -> some View {
        let isSelected = t.id == selected
        return Button { select(t.id) } label: {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(verbatim: "\(number)")
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 14, alignment: .trailing)
                Text(verbatim: branch ? "↳" : " ")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 9, alignment: .leading)
                    .accessibilityHidden(true)
                Circle().fill(topicColor(t.state, session: session.state)).frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 5) {
                    Text(t.title).lineLimit(2)
                    if isSelected { details(t) }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 3)
            .padding(.horizontal, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color(nsColor: .unemphasizedSelectedContentBackgroundColor) : .clear)
                .padding(.horizontal, 10)
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .id(t.id)
    }

    private func details(_ t: Topic) -> some View {
        let mine = requests.filter { t.requests.contains($0.index) }
        let times = mine.compactMap(\.at).map { $0.formatted(hourMinute) }
        let range = times.first.flatMap { a in times.last.map { a == $0 ? a : a + "–" + $0 } }
        let closed = session.state == .closed || !session.alive
        let meta: [String?] = [topicStateLabel(t.state, sessionClosed: closed), range, "\(t.requests.count) istek"]
        return VStack(alignment: .leading, spacing: 5) {
            Text(meta.compactMap { $0 }.joined(separator: " · ")).foregroundStyle(.secondary)
            if !t.summary.isEmpty { Text(t.summary).font(.callout) }
            ForEach(mine, id: \.index) { r in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(r.at?.formatted(hourMinute) ?? "--:--").monospacedDigit().foregroundStyle(.secondary)
                    Text(r.text).lineLimit(2)
                }
            }
        }
        .font(.subheadline)
        // kenar çubuğu listesi satırları tek satıra kısıyor
        .lineLimit(nil)
    }
}
