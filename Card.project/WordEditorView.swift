import SwiftUI
import SwiftData

struct WordEditorView: View {
    private enum EditorField: Hashable {
        case front
        case back
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var word: Word

    @State private var frontText: String
    @State private var backText: String
    @State private var isMemorized: Bool
    @State private var isDifficult: Bool
    @FocusState private var focusedField: EditorField?

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
                TextField("表面", text: $frontText)
                    .focused($focusedField, equals: .front)
                TextField("裏面", text: $backText)
                    .focused($focusedField, equals: .back)

                Toggle("学習済み", isOn: $isMemorized)
                Toggle("苦手単語", isOn: $isDifficult)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                focusedField = nil
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
