import AppKit
import RadarCore
import SwiftUI

struct PanelView: View {
    let store: RadarStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        PanelContent(sessions: store.sessions, conflicts: store.conflicts, topics: store.histories.mapValues(\.topics),
                     lastError: store.lastError, now: store.now) { id in
            // pencere açıkken seçim boş bırakılırsa ilk session'a atlar
            if let id { store.selectedSessionId = id }
            openWindow(id: "sessions")
            NSApplication.shared.activate()
        }
    }
}

/// Panelin içeriği; store'dan bağımsız, örnek veriyle de çizilebilir.
struct PanelContent: View {
    let sessions: [SessionSnapshot]
    let conflicts: [Conflict]
    let topics: [String: [Topic]]
    let lastError: String?
    /// bekleme süreleri bu ana göre
    let now: Date
    /// nil: pencereyi seçimi değiştirmeden aç
    let open: (String?) -> Void
    @State private var contentHeight: CGFloat = 0
    @State private var showDone = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if sessions.isEmpty {
                Text("Açık session yok")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
            } else {
                ScrollView {
                    list.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
                }
                .scrollBounceBehavior(.basedOnSize)
                // MenuBarExtra penceresi ideal boyuta göre açılır; ScrollView'ın ideal yüksekliği 0
                .frame(height: min(contentHeight, 520))
            }
            if let lastError {
                Label { Text(lastError) } icon: { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red) }
                    .font(.caption)
                    .lineLimit(1)
                    .help(lastError)
                    .padding(.horizontal, 21)
                    .padding(.bottom, 10)
            }
        }
        .frame(width: 360)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("Session Radar").font(.headline)
            if !sessions.isEmpty {
                Text("\(sessions.count) session").font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                Button("Tüm session'lar") { open(nil) }
                Divider()
                Button("Çık") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.leading, 21)
        .padding(.trailing, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var list: some View {
        let done = sessions.filter { $0.state == .turnDone || $0.state == .closed }
        return VStack(alignment: .leading, spacing: 4) {
            ForEach(sessions.filter { $0.state == .waiting || $0.state == .problem }) { tile($0) }
            ForEach(conflicts, id: \.pairKey) { c in
                Tile(tint: .red, action: { open(c.a) }) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.red)
                            .frame(width: 8)
                        Text(conflictText(c)).lineLimit(2)
                    }
                }
                .help(c.files.joined(separator: "\n"))
            }
            ForEach(sessions.filter { $0.state == .working }) { tile($0) }
            if !done.isEmpty {
                Button {
                    showDone.toggle()
                } label: {
                    Label("\(done.count) bitti", systemImage: "checkmark")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.quaternary.opacity(0.6), in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.leading, 5)
                .padding(.top, 4)
                if showDone {
                    ForEach(done) { SessionTile(session: $0, topics: [], now: now, open: open) }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }

    private func tile(_ s: SessionSnapshot) -> some View {
        SessionTile(session: s, topics: topics[s.id] ?? [], now: now, open: open)
    }

    private func conflictText(_ c: Conflict) -> String {
        func name(_ id: String) -> String { sessions.first { $0.id == id }?.name ?? String(id.prefix(8)) }
        let files = c.files.prefix(2).map { ($0 as NSString).lastPathComponent }.joined(separator: ", ")
        let more = c.files.count > 2 ? " +\(c.files.count - 2)" : ""
        return "Çakışma: \(name(c.a)) ↔ \(name(c.b)) · \(files)\(more)"
    }
}

/// Tıklanabilir satır; renk verilirse kart: hafif renkli zemin, solda şerit.
private struct Tile<Content: View>: View {
    var tint: Color?
    let action: () -> Void
    @ViewBuilder var content: Content
    @State private var hovered = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        content
            .padding(.leading, 13)
            .padding(.trailing, 10)
            .padding(.vertical, tint == nil ? 7 : 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                Group {
                    if let tint {
                        tint.opacity(hovered ? 0.18 : 0.12).overlay(alignment: .leading) { tint.frame(width: 3) }
                    } else if hovered {
                        Color.primary.opacity(0.06)
                    }
                }
                .clipShape(shape)
            }
            .contentShape(shape)
            .onHover { hovered = $0 }
            .onTapGesture(perform: action)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(.default, action)
    }
}

private struct SessionTile: View {
    let session: SessionSnapshot
    let topics: [Topic]
    let now: Date
    let open: (String?) -> Void

    var body: some View {
        let s = session
        Tile(tint: s.state == .waiting || s.state == .problem ? s.state.color : nil, action: { open(s.id) }) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Circle().fill(s.state.color).frame(width: 8, height: 8)
                    Text(s.name).fontWeight(.medium).lineLimit(1)
                    Spacer(minLength: 8)
                    if let trailing = trailingText(s, now: now) {
                        Text(trailing).font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                Group {
                    if let note = s.note {
                        // izin isteği session'ın sözü değil: bekleyen tool ve hedefi, tırnaksız
                        if s.waitingOnTool {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("İzin bekliyor").font(.caption).foregroundStyle(.secondary)
                                Text(note).font(.caption.monospaced()).lineLimit(2)
                            }
                        } else if s.state == .waiting {
                            Text("“\(note)”").lineLimit(3)
                        } else if s.state == .problem {
                            Text(note).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    if !topics.isEmpty { TopicStrip(topics: topics, session: s) }
                }
                .padding(.leading, 16)
            }
        }
    }
}

/// Son 8 konu, eskiden yeniye noktalar; üzerine gelinen ya da tıklanan noktanın başlığı ve durumu yazar.
struct TopicStrip: View {
    let topics: [Topic]
    let session: SessionSnapshot
    @State private var hovered: Int?
    @State private var selected: Int?

    var body: some View {
        let shown = Array(topics.suffix(8))
        let hidden = topics.count - shown.count
        HStack(spacing: 8) {
            HStack(spacing: 0) {
                if hidden > 0 {
                    Text("+\(hidden)").font(.caption).monospacedDigit().foregroundStyle(.secondary).padding(.trailing, 5)
                }
                ForEach(Array(shown.enumerated()), id: \.element.id) { i, t in
                    if i > 0 { Rectangle().fill(.tertiary).frame(width: 8, height: 1) }
                    dot(t)
                }
            }
            caption(shown)
        }
        .font(.subheadline)
    }

    /// seçili nokta şeritten taştıysa varsayılan yazıya döner
    @ViewBuilder private func caption(_ shown: [Topic]) -> some View {
        if let t = shown.first(where: { $0.id == (hovered ?? selected) }) {
            HStack(spacing: 4) {
                Text(t.title).lineLimit(1)
                Text("· " + stateLabel(t))
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
        } else if let title = topics.last(where: { $0.state == "active" })?.title ?? session.currentTopic {
            Text(title).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    private func stateLabel(_ t: Topic) -> String {
        topicStateLabel(t.state, sessionClosed: session.isOver)
    }

    private func dot(_ t: Topic) -> some View {
        let color = topicColor(t.state, session: session.state)
        let size: CGFloat = t.state == "active" ? 9 : 7
        return Group {
            // açık kalan konu içi boş halka
            if t.state == "open" { Circle().strokeBorder(color, lineWidth: 1.5) } else { Circle().fill(color) }
        }
        .frame(width: size, height: size)
        .overlay {
            if selected == t.id { Circle().stroke(.primary, lineWidth: 1).padding(-3) }
        }
        // isabet alanı noktadan geniş; yerleşim değişmez
        .padding(4)
        .contentShape(Rectangle())
        .onHover { inside in
            if inside { hovered = t.id } else if hovered == t.id { hovered = nil }
        }
        .onTapGesture { selected = selected == t.id ? nil : t.id }
        .padding(-4)
        .accessibilityLabel(t.title + ", " + stateLabel(t))
    }
}
