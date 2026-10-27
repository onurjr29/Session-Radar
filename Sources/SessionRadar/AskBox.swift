import RadarCore
import SwiftUI

/// Soru, cevap ve bekleme durumu store'da session başına tutulur; popover kapanıp açılınca kaybolmaz.
struct AskBox: View {
    let sessionId: String
    let store: RadarStore
    /// tuvalde seçili konu; soru ona odaklanır
    let topic: Topic?

    var body: some View {
        let state = store.asks[sessionId] ?? AskState()
        let question = Binding(get: { store.asks[sessionId]?.question ?? "" },
                               set: { store.asks[sessionId, default: AskState()].question = $0 })
        VStack(alignment: .leading, spacing: 4) {
            if let topic {
                Text("Konu: \(topic.title)").font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            HStack {
                TextField(topic == nil ? "Bu session'a soru sor…" : "Bu konuya soru sor…", text: question)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { store.sendAsk(sessionId, topicId: topic?.id) }
                Button("Sor") { store.sendAsk(sessionId, topicId: topic?.id) }
                    .disabled(state.busy || state.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if state.busy {
                ProgressView().controlSize(.small)
            } else if let answer = state.answer {
                if let t = state.answerTopic, t != topic?.title {
                    Text("\"\(t)\" için cevap").font(.caption).foregroundStyle(.secondary)
                }
                Text(answer).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
