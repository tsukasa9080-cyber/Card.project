import Foundation
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
