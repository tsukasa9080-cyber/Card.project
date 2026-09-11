import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct CSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText, .plainText] }

    var text: String

    init(text: String = "") {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.text = text
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

func parseCSV(_ text: String) -> [[String]] {
    var rows: [[String]] = []
    var row: [String] = []
    var field = ""
    var isInsideQuotes = false
    var index = text.startIndex

    while index < text.endIndex {
        let character = text[index]

        if character == "\"" {
            let nextIndex = text.index(after: index)
            if isInsideQuotes, nextIndex < text.endIndex, text[nextIndex] == "\"" {
                field.append("\"")
                index = nextIndex
            } else {
                isInsideQuotes.toggle()
            }
        } else if character == ",", !isInsideQuotes {
            row.append(field)
            field = ""
        } else if (character == "\n" || character == "\r"), !isInsideQuotes {
            if character == "\r" {
                let nextIndex = text.index(after: index)
                if nextIndex < text.endIndex, text[nextIndex] == "\n" {
                    index = nextIndex
                }
            }
            row.append(field)
            if !row.allSatisfy({ $0.isEmpty }) {
                rows.append(row)
            }
            row = []
            field = ""
        } else {
            field.append(character)
        }

        index = text.index(after: index)
    }

    row.append(field)
    if !row.allSatisfy({ $0.isEmpty }) {
        rows.append(row)
    }
    return rows
}

func csvEscaped(_ value: String) -> String {
    "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
}

extension UTType {
    static let cardBook = UTType(exportedAs: "com.cardproject.wordbook", conformingTo: .json)
}

struct SharedWordBook: Codable, Transferable, Identifiable {
    struct Card: Codable {
        let front: String
        let back: String
    }
    var id: String { name }
    let version: Int
    let name: String
    let cards: [Card]

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .cardBook) { book in
            try JSONEncoder().encode(book)
        }.suggestedFileName { book in
            let safe = book.name.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: "_")
            return String((safe.isEmpty ? "単語帳" : safe).prefix(80)) + ".cardbook"
        }
    }

    static func read(_ url: URL) throws -> SharedWordBook {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 5_000_000 else { throw SharingError.invalid("ファイルは5MB以下にしてください。") }
        let data = try Data(contentsOf: url)
        return try decode(data)
    }

    static func decode(_ data: Data) throws -> SharedWordBook {
        guard data.count <= 5_000_000 else { throw SharingError.invalid("ファイルは5MB以下にしてください。") }
        let book = try JSONDecoder().decode(Self.self, from: data)
        guard book.version == 1 else { throw SharingError.invalid("この単語帳の形式には対応していません。") }
        guard !book.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, book.name.count <= 100,
              !book.cards.isEmpty, book.cards.count <= 5000,
              book.cards.allSatisfy({ !$0.front.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !$0.back.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.front.count <= 2000 && $0.back.count <= 2000 }) else {
            throw SharingError.invalid("単語帳名やカードの内容が不正、または件数・文字数が上限を超えています。")
        }
        return book
    }
}

enum SharingError: LocalizedError {
    case invalid(String)
    var errorDescription: String? {
        switch self { case .invalid(let message): message }
    }
}

struct WordBookImportView: View {
    let book: SharedWordBook
    let onImported: (String) -> Void
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage("defaultCategoryName") private var defaultCategoryName = "未登録"
    @State private var error: String?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(book.name).font(.title2.bold())
                    Text("\(book.cards.count)語を新しい単語帳として追加します。")
                    Text("同じ名前がある場合は末尾に番号を付けます。すべて未学習として登録します。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("内容のプレビュー（先頭20語）") {
                    ForEach(Array(book.cards.prefix(20).enumerated()), id: \.offset) { _, card in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(card.front).font(.headline)
                            Text(card.back).foregroundStyle(.secondary)
                        }
                    }
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("単語帳を受け取る")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }.disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("追加") { save() }.disabled(isSaving)
                }
            }
        }.interactiveDismissDisabled(isSaving)
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        // インポートだけを専用コンテキストで保存し、失敗時は部分追加を残さない。
        let context = ModelContext(modelContext.container)
        context.autosaveEnabled = false
        do {
            let books = try context.fetch(FetchDescriptor<WordBook>())
            let words = try context.fetch(FetchDescriptor<Word>())
            let existing = Set(books.map(\.name) + words.map(\.category) + [defaultCategoryName])
            let base = book.name.trimmingCharacters(in: .whitespacesAndNewlines)
            var name = base
            var suffix = 2
            while existing.contains(name) {
                name = "\(base) (\(suffix))"
                suffix += 1
            }
            context.insert(WordBook(name: name))
            for card in book.cards {
                context.insert(Word(frontText: card.front, backText: card.back, category: name))
            }
            try context.save()
            onImported(name)
            dismiss()
        } catch {
            context.rollback()
            self.error = "保存できませんでした。\(error.localizedDescription)"
            isSaving = false
        }
    }
}
