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
