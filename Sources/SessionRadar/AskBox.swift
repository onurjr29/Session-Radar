import RadarCore
import SwiftUI

/// Soru, cevap ve bekleme durumu store'da session başına tutulur; popover kapanıp açılınca kaybolmaz.
struct AskBox: View {
    let sessionId: String
    let store: RadarStore

    var body: some View {
        let state = store.asks[sessionId] ?? AskState()
        let question = Binding(get: { store.asks[sessionId]?.question ?? "" },
                               set: { store.asks[sessionId, default: AskState()].question = $0 })
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                TextField("Bu session'a soru sor…", text: question)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { store.sendAsk(sessionId) }
                Button("Sor") { store.sendAsk(sessionId) }
                    .disabled(state.busy || state.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if state.busy {
                ProgressView().controlSize(.small)
            } else if let answer = state.answer {
                Text(answer).textSelection(.enabled)
            }
        }
    }
}
