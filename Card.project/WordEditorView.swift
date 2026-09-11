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
    @State private var saveError: String?
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
                TextField("表面", text: $frontText, axis: .vertical)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .front)
                TextField("裏面", text: $backText, axis: .vertical)
                    .lineLimit(3...6)
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
                        let previous = (word.english, word.japanese, word.isMemorized, word.isDifficult)
                        word.english = frontText.trimmingCharacters(in: .whitespacesAndNewlines)
                        word.japanese = backText.trimmingCharacters(in: .whitespacesAndNewlines)
                        word.isMemorized = isMemorized
                        word.isDifficult = isDifficult
                        do {
                            try modelContext.save()
                            dismiss()
                        } catch {
                            (word.english, word.japanese, word.isMemorized, word.isDifficult) = previous
                            saveError = "保存できませんでした。\(error.localizedDescription)"
                        }
                    }
                    .disabled(frontText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || backText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert("保存エラー", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
                Button("OK", role: .cancel) { saveError = nil }
            } message: {
                Text(saveError ?? "")
            }
        }
    }
}
