import SwiftUI

struct InsightChatView: View {
    @EnvironmentObject private var store: WeightStore
    @StateObject private var chat = InsightChatController()
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(chat.turns) { turn in
                            HStack {
                                if turn.fromUser { Spacer(minLength: 40) }
                                Text(turn.text)
                                    .padding(12)
                                    .background(turn.fromUser
                                                ? Color.accentColor
                                                : Color(.secondarySystemGroupedBackground),
                                                in: RoundedRectangle(cornerRadius: 16))
                                    .foregroundStyle(turn.fromUser ? Color.white : Color.primary)
                                if !turn.fromUser { Spacer(minLength: 40) }
                            }
                            .id(turn.id)
                        }
                        if chat.busy {
                            ProgressView()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id("busy")
                        }
                    }
                    .padding()
                }
                .onChange(of: chat.turns.count) { _, _ in
                    if let last = chat.turns.last?.id {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }

            HStack(spacing: 10) {
                TextField("Message", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
                    .focused($focused)
                Button {
                    send()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title)
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || chat.busy)
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Chat")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func send() {
        let text = draft
        draft = ""
        Task {
            await chat.send(text,
                            snapshot: Insights.snapshot(entries: store.entries,
                                                        goal: store.goalKilograms))
        }
    }
}
