import Foundation

enum AnswerComparison {
    static func normalized(_ value: String) -> String {
        value.precomposedStringWithCompatibilityMapping
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .lowercased(with: Locale(identifier: "en_US_POSIX"))
    }

    static func matches(_ answer: String, _ expected: String) -> Bool {
        let normalizedAnswer = normalized(answer)
        return !normalizedAnswer.isEmpty && normalizedAnswer == normalized(expected)
    }

    static func uniqueChoices(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter {
            let key = normalized($0)
            return !key.isEmpty && seen.insert(key).inserted
        }
    }
}
