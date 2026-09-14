import Foundation
import SwiftData

enum WordBookStore {
    enum RenameError: LocalizedError {
        case invalidName
        var errorDescription: String? { "空の名前や、使用中の単語帳名には変更できません。" }
    }
    @MainActor static func rename(from oldName: String, to newName: String, in container: ModelContainer) throws {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let books = try context.fetch(FetchDescriptor<WordBook>())
        let words = try context.fetch(FetchDescriptor<Word>())
        let results = try context.fetch(FetchDescriptor<TestResult>())
        guard !newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              oldName != newName,
              !books.contains(where: { $0.name == newName }),
              !words.contains(where: { $0.category == newName }) else {
            throw RenameError.invalidName
        }
        let matchingBooks = books.filter { $0.name == oldName }
        if matchingBooks.isEmpty {
            context.insert(WordBook(name: newName))
        } else {
            for book in matchingBooks { book.name = newName }
        }
        for word in words where word.category == oldName { word.category = newName }
        for result in results where result.category == oldName { result.category = newName }
        try context.save()
    }
}
