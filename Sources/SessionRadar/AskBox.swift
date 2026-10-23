import RadarCore
import SwiftUI

struct AskBox: View {
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
