import AppKit
import RadarCore
import SwiftUI

struct FocusRequest: Equatable { var topicId: Int; var serial: Int }

// dünya koordinatında ölçüler (pt); kart konumu x = sütun * 230 + 120, y = şerit * 120
private let columnStep = 230.0
private let laneStep = 120.0
private let firstColumnX = 120.0
private let cardWidth = 190.0
private let activeCardWidth = 240.0
private let cardHeight = 62.0
/// çizgilerin kartlara bağlandığı yükseklik (kartın üstünden)
private let portY = 31.0
private let startFrame = CGRect(x: 0, y: portY - 11, width: 64, height: 22)
private let placeholderId = Int.min

private let lineColor = Color(nsColor: .tertiaryLabelColor)
private let cardTint = Color(nsColor: NSColor(name: nil) { appearance in
    appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(white: 1, alpha: 0.07) : .white
})

/// kart zemini: açık temada beyaz, koyuda pencere renginin bir ton açığı
private func cardSurface(_ shape: some Shape) -> some View {
    shape.fill(Color(nsColor: .windowBackgroundColor)).overlay(shape.fill(cardTint))
}

struct FlowCanvas: View {
    let session: SessionSnapshot
    let topics: [Topic]
    let requests: [Request]
    @Binding var selected: Int?       // konu id'si
    var focus: FocusRequest?          // değişince kamera o karta kayar ve kartı seçer

    @State private var camera = Camera(x: 0, y: 0, scale: 1)
    @State private var viewport = CGSize.zero
    /// kullanıcı kamerayı elle oynattı; "Şu ana dön"e kadar kamera şu anki konuyu takip etmez
    @State private var moved = false
    @State private var dragStart: (location: CGPoint, camera: Camera)?
    @State private var pinchStart: (location: CGPoint, camera: Camera)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let l = layout
        GeometryReader { geo in
            // boyut state'e geçmeden önceki ilk karede de kamera doğru yerde olsun
            let cam = viewport == geo.size ? camera : settled(l, geo.size)
            ZStack(alignment: .topLeading) {
                DotGrid(camera: cam).fill(Color.primary.opacity(0.16))
                FlowWorld(cards: l.cards, wires: l.wires, start: l.start, selected: $selected)
                    .equatable()
                    .id(session.id)
                    .scaleEffect(cam.scale, anchor: .topLeading)
                    .offset(x: cam.x, y: cam.y)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .clipped()
            .contentShape(Rectangle())
            .background(ScrollCatcher(onScroll: scroll))
            .simultaneousGesture(pan)
            .simultaneousGesture(pinch)
            .overlay(alignment: .bottomLeading) { nowButton.padding(12) }
            .overlay(alignment: .bottomTrailing) { zoomControls(cam.scale).padding(12) }
            .overlay(alignment: .topTrailing) {
                if !topics.isEmpty {
                    Minimap(cards: l.cards, content: l.content, camera: cam, viewport: geo.size, onCenter: center).padding(12)
                }
            }
            .onChange(of: geo.size, initial: true) {
                viewport = geo.size
                camera = settled(layout, geo.size)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: l.nodes) { follow() }
        .onChange(of: l.nowId) { follow() }
        .onChange(of: focus) { _, f in if let f { focus(on: f.topicId) } }
        .onChange(of: session.id) {
            moved = false
            camera = nowCamera(layout, viewport, scale: 1)
        }
    }

    // MARK: Kamera

    private func nowCamera(_ l: CanvasLayout, _ size: CGSize, scale: Double? = nil) -> Camera {
        clampCamera(focusCamera(on: l.nowFrame, scale: scale ?? camera.scale, viewport: size), content: l.content, viewport: size)
    }

    private func settled(_ l: CanvasLayout, _ size: CGSize) -> Camera {
        moved ? clampCamera(camera, content: l.content, viewport: size) : nowCamera(l, size)
    }

    /// elle yapılan her kamera değişikliği buradan geçer
    private func move(_ c: Camera) {
        camera = clampCamera(c, content: layout.content, viewport: viewport)
        moved = true
    }

    private func smooth(_ duration: Double = 0.5) -> Animation? { reduceMotion ? nil : .smooth(duration: duration) }

    private func follow() {
        withAnimation(smooth()) { camera = settled(layout, viewport) }
    }

    private func focus(on id: Int) {
        let l = layout
        guard let f = l.cards.first(where: { $0.id == id })?.frame else { return }
        selected = id
        moved = id != l.nowId
        withAnimation(smooth()) {
            camera = clampCamera(focusCamera(on: f, scale: camera.scale, viewport: viewport), content: l.content, viewport: viewport)
        }
    }

    private func goNow() {
        let l = layout
        moved = false
        if let id = l.nowId { selected = id }
        withAnimation(smooth()) { camera = nowCamera(l, viewport) }
    }

    private func zoomed(_ c: Camera, to scale: Double, around p: CGPoint) -> Camera {
        let s = min(max(scale, cameraScaleRange.lowerBound), cameraScaleRange.upperBound)
        return Camera(x: p.x - (p.x - c.x) * s / c.scale, y: p.y - (p.y - c.y) * s / c.scale, scale: s)
    }

    private func zoom(by f: Double) {
        let mid = CGPoint(x: viewport.width / 2, y: viewport.height / 2)
        withAnimation(smooth(0.3)) { move(zoomed(camera, to: camera.scale * f, around: mid)) }
    }

    private func center(on p: CGPoint, animated: Bool) {
        let s = camera.scale
        withAnimation(animated ? smooth(0.3) : nil) {
            move(Camera(x: viewport.width / 2 - p.x * s, y: viewport.height / 2 - p.y * s, scale: s))
        }
    }

    private func scroll(_ e: NSEvent, at p: CGPoint) {
        // fare tekerleği satır cinsinden, trackpad nokta cinsinden gelir
        let k = e.hasPreciseScrollingDeltas ? 1.0 : 10.0
        let dx = e.scrollingDeltaX * k, dy = e.scrollingDeltaY * k
        if e.modifierFlags.contains(.command) {
            move(zoomed(camera, to: camera.scale * exp(dy * 0.01), around: p))
        } else {
            move(Camera(x: camera.x + dx, y: camera.y + dy, scale: camera.scale))
        }
    }

    // başlangıç noktası değiştiyse yeni hareket; iptal edilen hareket eski başlangıcı bırakmasın
    private var pan: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { v in
                if dragStart?.location != v.startLocation { dragStart = (v.startLocation, camera) }
                guard let s = dragStart?.camera else { return }
                move(Camera(x: s.x + v.translation.width, y: s.y + v.translation.height, scale: s.scale))
            }
            .onEnded { _ in dragStart = nil }
    }

    private var pinch: some Gesture {
        MagnifyGesture()
            .onChanged { v in
                if pinchStart?.location != v.startLocation { pinchStart = (v.startLocation, camera) }
                guard let s = pinchStart?.camera else { return }
                move(zoomed(s, to: s.scale * v.magnification, around: v.startLocation))
            }
            .onEnded { _ in pinchStart = nil }
    }

    // MARK: HUD

    private var nowButton: some View {
        Button(action: goNow) {
            Label("Şu ana dön", systemImage: "scope")
                .padding(.horizontal, 11)
                .frame(height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .font(.callout)
        .foregroundStyle(.secondary)
        .glassSurface(cornerRadius: 14)
    }

    private func zoomControls(_ scale: Double) -> some View {
        HStack(spacing: 0) {
            hudButton("minus", "Uzaklaştır") { zoom(by: 1 / 1.25) }
            Button(action: fit) {
                Text(verbatim: "%\(Int((scale * 100).rounded()))")
                    .monospacedDigit()
                    .frame(minWidth: 40, minHeight: 28)
                    .contentShape(Rectangle())
            }
            .help("Bütün akışı sığdır")
            hudButton("plus", "Yakınlaştır") { zoom(by: 1.25) }
        }
        .buttonStyle(.plain)
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
        .glassSurface(cornerRadius: 14)
    }

    private func hudButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).frame(width: 28, height: 28).contentShape(Rectangle())
        }
        .accessibilityLabel(label)
        .help(label)
    }

    private func fit() {
        withAnimation(smooth()) { move(fitCamera(content: layout.content, viewport: viewport)) }
    }

    // MARK: Yerleşim

    private var layout: CanvasLayout {
        var l = CanvasLayout()
        if let first = requests.first {
            let time = first.at?.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(Locale(identifier: "tr_TR")))
            l.start = StartModel(time: time, help: String(first.text.prefix(400)))
            l.content = startFrame
        }
        var prevMain: CGPoint? = l.start == nil ? nil : CGPoint(x: startFrame.maxX, y: portY)

        if topics.isEmpty {
            let f = CGRect(x: firstColumnX, y: 0, width: cardWidth, height: cardHeight)
            let none = "Konu başlıkları henüz çıkarılmadı"
            l.cards = [CardModel(id: placeholderId, title: requests.last?.text ?? none, symbol: "ellipsis", color: .gray,
                                 label: nil, meta: requests.isEmpty ? nil : none, info: nil, active: false, selected: false,
                                 frame: f, tail: nil)]
            if let p = prevMain { l.wires = [WireModel(id: placeholderId, from: p, to: CGPoint(x: f.minX, y: portY), color: lineColor)] }
            l.content = l.content.union(f)
            l.nowFrame = f
            return l
        }

        let closed = session.state == .closed || !session.alive
        let info = activeInfo
        let byId = Dictionary(topics.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var frames: [Int: CGRect] = [:]
        l.nodes = flowLayout(topics)
        l.nowId = resolveTopicSelection(nil, topics: topics)
        for n in l.nodes {
            guard let t = byId[n.topicId] else { continue }
            let active = t.state == "active"
            let w = active ? activeCardWidth : cardWidth
            // geniş kart son sütunda sağa, değilse iki yana açılır; komşu karta taşmaz
            let grow = n.column == l.nodes.count - 1 ? 0 : (w - cardWidth) / 2
            let f = CGRect(x: Double(n.column) * columnStep + firstColumnX - grow, y: Double(n.lane) * laneStep,
                           width: w, height: cardHeight + (active ? info?.height ?? 0 : 0))
            frames[t.id] = f
            let color = topicColor(t.state, session: session.state)
            let to = CGPoint(x: f.minX, y: f.minY + portY)
            var tail: WireTail?
            if let p = n.parent, let pf = frames[p] {
                let c = color.opacity(0.7)
                l.wires.append(WireModel(id: t.id, from: CGPoint(x: pf.maxX, y: pf.minY + portY), to: to, color: c))
                tail = t.state == "open" ? .open(c) : active ? .running(c) : nil
            } else {
                if let from = prevMain { l.wires.append(WireModel(id: t.id, from: from, to: to, color: lineColor)) }
                prevMain = CGPoint(x: f.maxX, y: f.minY + portY)
            }
            l.cards.append(CardModel(id: t.id, title: t.title, symbol: symbol(t.state), color: color,
                                     label: topicStateLabel(t.state, sessionClosed: closed), meta: "\(t.requests.count) istek",
                                     info: active ? info : nil, active: active, selected: selected == t.id, frame: f, tail: tail))
            l.content = l.content.union(f)
        }
        l.nowFrame = l.nowId.flatMap { frames[$0] } ?? l.content
        return l
    }

    private var activeInfo: ActiveInfo? {
        let st = session.status
        let info = ActiveInfo(action: session.action, task: st?.task, next: st?.next, todo: st?.todo ?? [],
                              problems: st?.problems?.filter { !$0.isEmpty } ?? [],
                              note: session.state == .waiting ? session.note : nil)
        return info.rows == 0 ? nil : info
    }

    private func symbol(_ state: String) -> String {
        switch state {
        case "done": "checkmark"
        case "active": "circle.fill"
        default: "exclamationmark"
        }
    }
}

// MARK: Modeller

private struct CanvasLayout {
    var nodes: [FlowNode] = []
    var cards: [CardModel] = []
    var wires: [WireModel] = []
    var start: StartModel?
    var content = CGRect.null
    var nowId: Int?
    var nowFrame = CGRect.zero
}

private struct StartModel: Equatable { var time: String?; var help: String }

private struct WireModel: Equatable, Identifiable {
    var id: Int        // hedef kartın id'si; dal ana hatta dönünce aynı çizgi yeni yerine kayar
    var from: CGPoint
    var to: CGPoint
    var color: Color
}

private enum WireTail: Equatable { case open(Color), running(Color) }

private struct ActiveInfo: Equatable {
    var action: String?
    var task: String?
    var next: String?
    var todo: [TodoItem]
    var problems: [String]
    var note: String?

    var rows: Int { [action, task, next, note].compactMap { $0 }.count + todo.count + problems.count }
    // ponytail: satır sayısından tahmini yükseklik; yalnızca sınır, odak ve mini harita için
    var height: Double { rows == 0 ? 0 : 13 + Double(rows) * 19 }
}

private struct CardModel: Equatable, Identifiable {
    var id: Int
    var title: String
    var symbol: String
    var color: Color
    var label: String?
    var meta: String?
    var info: ActiveInfo?
    var active: Bool
    var selected: Bool
    var frame: CGRect
    var tail: WireTail?
}

// MARK: Dünya

/// kartlar ve çizgiler; kamera değişince yeniden kurulmaz, yalnızca dışarıdan ölçeklenip kaydırılır
private struct FlowWorld: View, Equatable {
    let cards: [CardModel]
    let wires: [WireModel]
    let start: StartModel?
    @Binding var selected: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    nonisolated static func == (a: Self, b: Self) -> Bool { a.cards == b.cards && a.wires == b.wires && a.start == b.start }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(wires) { w in WireView(from: w.from, to: w.to, color: w.color) }
            if let start {
                StartCapsule(model: start).offset(x: startFrame.minX, y: startFrame.minY)
            }
            ForEach(cards) { c in
                FlowCard(card: c).equatable()
                    .onTapGesture { if c.id != placeholderId { selected = c.id } }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(c.selected ? [.isButton, .isSelected] : .isButton)
                    .overlay(alignment: .topLeading) {
                        if let tail = c.tail { TailMark(tail: tail).offset(x: c.frame.width, y: portY - 4) }
                    }
                    // yalnızca konum kayar; renk ve içerik ara tonlardan geçmeden değişir
                    .transaction { $0.animation = nil }
                    .modifier(Shift(x: c.frame.minX, y: c.frame.minY))
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.5), value: cards)
    }
}

/// kendi ara değerini kendisi hesaplayan kaydırma; içerideki animasyonsuz işlem konumu durdurmaz
private struct Shift: GeometryEffect {
    var x: Double
    var y: Double

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(x, y) }
        set { x = newValue.first; y = newValue.second }
    }

    func effectValue(size: CGSize) -> ProjectionTransform { ProjectionTransform(CGAffineTransform(translationX: x, y: y)) }
}

/// iki kart arasındaki eğri; uçlar kayarken renk ara tonlardan geçmez
private struct WireView: View, Animatable {
    var from: CGPoint
    var to: CGPoint
    let color: Color

    nonisolated var animatableData: AnimatablePair<CGPoint.AnimatableData, CGPoint.AnimatableData> {
        get { AnimatablePair(from.animatableData, to.animatableData) }
        set { from.animatableData = newValue.first; to.animatableData = newValue.second }
    }

    var body: some View {
        let m = (from.x + to.x) / 2
        Path { p in
            p.move(to: from)
            p.addCurve(to: to, control1: CGPoint(x: m, y: from.y), control2: CGPoint(x: m, y: to.y))
        }
        .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
        .transaction { $0.animation = nil }
    }
}

/// dalın ucu: açık kaldıysa kısa kesik çizgi ve boş halka, sürüyorsa uzun kesik çizgi
private struct TailMark: View {
    let tail: WireTail

    var body: some View {
        switch tail {
        case .open(let c):
            ZStack(alignment: .leading) {
                dash(10, c, [3, 3])
                Circle().stroke(c, lineWidth: 1.5).frame(width: 7, height: 7).offset(x: 10.5)
            }
            .frame(width: 18, height: 8, alignment: .leading)
        case .running(let c):
            dash(40, c, [4, 4]).frame(width: 40, height: 8)
        }
    }

    private func dash(_ length: Double, _ c: Color, _ pattern: [CGFloat]) -> some View {
        Path { p in p.move(to: CGPoint(x: 0, y: 4)); p.addLine(to: CGPoint(x: length, y: 4)) }
            .stroke(c, style: StrokeStyle(lineWidth: 2, dash: pattern))
    }
}

private struct StartCapsule: View {
    let model: StartModel

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "flag.fill").imageScale(.small)
            if let time = model.time { Text(time).monospacedDigit() }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .frame(width: startFrame.width, height: startFrame.height)
        .background { cardSurface(Capsule()) }
        .overlay(Capsule().strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
        .help(model.help)
    }
}

private struct FlowCard: View, Equatable {
    let card: CardModel

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: card.symbol)
                    .font(.system(size: card.active ? 8 : 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(card.color, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                Text(card.title)
                    .font(.callout.weight(card.label == nil ? .regular : .semibold))
                    .lineLimit(2)
                    .padding(.top, 2)
            }
            HStack(spacing: 6) {
                if let label = card.label {
                    Text(label)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(card.color)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 1.5)
                        .background(card.color.opacity(0.15), in: Capsule())
                }
                if let meta = card.meta { Text(meta).font(.subheadline).foregroundStyle(.secondary).lineLimit(2) }
            }
            if let info = card.info {
                Divider().padding(.vertical, 2)
                InfoRows(info: info)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: card.frame.width, alignment: .leading)
        .background { cardSurface(shape).shadow(color: .black.opacity(0.08), radius: 4, y: 2) }
        .overlay { shape.strokeBorder(card.active ? card.color : Color(nsColor: .separatorColor), lineWidth: card.active ? 1.5 : 0.5) }
        .overlay {
            if card.selected {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .strokeBorder(card.active ? card.color.opacity(0.35) : Color.primary.opacity(0.22), lineWidth: 2)
                    .padding(-3.5)
            }
        }
        .contentShape(shape)
    }
}

private struct InfoRows: View {
    let info: ActiveInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let v = info.action { row("hammer", v, .secondary, lines: 1) }
            if let v = info.task { row("target", v, .primary) }
            if let v = info.next { row("arrow.turn.down.right", v, .primary) }
            ForEach(Array(info.todo.enumerated()), id: \.offset) { _, item in
                row(item.done ? "checkmark.circle.fill" : "circle", item.text, item.done ? .secondary : .primary, lines: 1)
            }
            ForEach(Array(info.problems.enumerated()), id: \.offset) { _, p in
                row("exclamationmark.triangle.fill", p, .red)
            }
            if let v = info.note { row("hand.raised.fill", v, .orange, lines: 3) }
        }
        .font(.subheadline)
    }

    private func row(_ symbol: String, _ text: String, _ color: Color, lines: Int = 2) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: symbol).frame(width: 13).foregroundStyle(color == .primary ? .secondary : color)
            Text(text).foregroundStyle(color).lineLimit(lines).truncationMode(.middle)
        }
    }
}

// MARK: Zemin

/// yalnızca görünen alan için noktalar; kamera animasyonunda kartlarla aynı karede kayar
private struct DotGrid: Shape {
    var camera: Camera

    var animatableData: AnimatablePair<AnimatablePair<Double, Double>, Double> {
        get { AnimatablePair(AnimatablePair(camera.x, camera.y), camera.scale) }
        set { camera = Camera(x: newValue.first.first, y: newValue.first.second, scale: newValue.second) }
    }

    func path(in rect: CGRect) -> Path {
        var step = 18 * camera.scale
        // ponytail: %56'nın altında her ikinci nokta; çok sık ızgara hem gürültü hem iş
        if step < 10 { step *= 2 }
        let r = 1.0
        var x0 = camera.x.truncatingRemainder(dividingBy: step), y0 = camera.y.truncatingRemainder(dividingBy: step)
        if x0 < 0 { x0 += step }
        if y0 < 0 { y0 += step }
        var p = Path()
        var x = x0
        while x <= rect.maxX + r {
            var y = y0
            while y <= rect.maxY + r {
                p.addEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
                y += step
            }
            x += step
        }
        return p
    }
}

// MARK: Mini harita

private struct Minimap: View {
    let cards: [CardModel]
    let content: CGRect
    let camera: Camera
    let viewport: CGSize
    let onCenter: (CGPoint, Bool) -> Void
    /// çerçeve tutulduysa imleçle çerçeve merkezi arasındaki fark; dışına basılınca sıfır
    @State private var grab: (location: CGPoint, offset: CGSize)?

    private let size = CGSize(width: 160, height: 70)

    var body: some View {
        let box = content.insetBy(dx: -30, dy: -30)
        let k = min((size.width - 12) / box.width, (size.height - 12) / box.height)
        let ox = (size.width - box.width * k) / 2 - box.minX * k, oy = (size.height - box.height * k) / 2 - box.minY * k
        let map = { (r: CGRect) in CGRect(x: r.minX * k + ox, y: r.minY * k + oy, width: r.width * k, height: r.height * k) }
        let s = camera.scale
        let view = map(CGRect(x: -camera.x / s, y: -camera.y / s, width: viewport.width / s, height: viewport.height / s))
        ZStack(alignment: .topLeading) {
            Canvas { ctx, _ in
                for c in cards {
                    ctx.fill(Path(roundedRect: map(c.frame), cornerRadius: 1.5), with: .color(c.color.opacity(0.75)))
                }
            }
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.primary.opacity(0.06))
                .stroke(Color.primary.opacity(0.45), lineWidth: 1)
                .frame(width: view.width, height: view.height)
                .offset(x: view.minX, y: view.minY)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { v in
                    let first = grab?.location != v.startLocation
                    if first {
                        let inside = view.contains(v.startLocation)
                        grab = (v.startLocation, inside ? CGSize(width: v.startLocation.x - view.midX, height: v.startLocation.y - view.midY) : .zero)
                    }
                    let g = grab?.offset ?? .zero
                    onCenter(CGPoint(x: (v.location.x - g.width - ox) / k, y: (v.location.y - g.height - oy) / k), first && g == .zero)
                }
                .onEnded { _ in grab = nil }
        )
        .glassSurface(cornerRadius: 10)
        .accessibilityHidden(true)
    }
}

// MARK: Tekerlek köprüsü

/// SwiftUI macOS'ta tekerlek ve iki parmak kaydırmayı vermiyor; pencereye gelen olaylar yerel izleyiciyle yakalanır
private struct ScrollCatcher: NSViewRepresentable {
    let onScroll: (NSEvent, CGPoint) -> Void

    func makeNSView(context: Context) -> CatcherView { CatcherView() }
    func updateNSView(_ view: CatcherView, context: Context) { view.onScroll = onScroll }

    final class CatcherView: NSView {
        var onScroll: ((NSEvent, CGPoint) -> Void)?
        private var monitor: Any?

        override var isFlipped: Bool { true }
        // fare tıklamaları SwiftUI'da kalsın
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] e in
                guard let self, e.window === self.window, let onScroll = self.onScroll else { return e }
                let p = self.convert(e.locationInWindow, from: nil)
                guard self.bounds.contains(p) else { return e }
                onScroll(e, p)
                return nil
            }
        }
    }
}
