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
        case .working: .blue
        case .waiting: .orange
        case .turnDone: .green
        case .problem: .red
        case .closed: .gray
        }
    }
}

extension SessionSnapshot {
    /// session kapandı ya da süreci yok
    var isOver: Bool { state == .closed || !alive }
}

/// Bekleme süresi: "4 dk", "2 sa", "1 gün".
private func waitText(since date: Date, now: Date) -> String {
    let m = max(1, Int(now.timeIntervalSince(date) / 60))
    return m < 60 ? "\(m) dk" : m < 1440 ? "\(m / 60) sa" : "\(m / 1440) gün"
}

/// Satırın sağındaki küçük yazı: bekleyende bekleme süresi, çalışanda ve sorunluda ilerleme.
func trailingText(_ s: SessionSnapshot, now: Date) -> String? {
    switch s.state {
    case .waiting: s.waitingSince.map { waitText(since: $0, now: now) }
    case .working, .problem: s.progress.map { "\($0.done)/\($0.total)" }
    default: nil
    }
}

func topicColor(_ topicState: String, session: SessionState) -> Color {
    switch topicState {
    case "done": .green
    case "active": session.color
    default: .orange
    }
}

extension View {
    @ViewBuilder
    func glassSurface(cornerRadius: CGFloat = 12) -> some View {
        if #available(macOS 26, *) {
            glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
        }
    }
}
