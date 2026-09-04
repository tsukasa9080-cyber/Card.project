import SwiftUI
import SwiftData

struct WordEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var word: Word

    @State private var frontText: String
    @State private var backText: String
    @State private var isMemorized: Bool
    @State private var isDifficult: Bool

    init(word: Word) {
        self.word = word
        _frontText = State(initialValue: word.frontText)
        _backText = State(initialValue: word.backText)
        _isMemorized = State(initialValue: word.isMemorized)
        _isDifficult = State(initialValue: word.isDifficult)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("表面（問題）", text: $frontText)
                TextField("裏面（答え）", text: $backText)

                Toggle("学習済み", isOn: $isMemorized)
                Toggle("苦手単語", isOn: $isDifficult)
            }
            .navigationTitle("単語を編集")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        word.english = frontText.trimmingCharacters(in: .whitespacesAndNewlines)
                        word.japanese = backText.trimmingCharacters(in: .whitespacesAndNewlines)
                        word.isMemorized = isMemorized
                        word.isDifficult = isDifficult
                        try? modelContext.save()
                        dismiss()
                    }
                }
            }
        }
    }
}
