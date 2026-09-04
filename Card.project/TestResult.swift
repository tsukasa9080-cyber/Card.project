import Foundation
import SwiftData

@Model
final class TestResult {
    var category: String
    var correctAnswers: Int
    var totalQuestions: Int
    var takenAt: Date

    init(category: String, correctAnswers: Int, totalQuestions: Int, takenAt: Date = .now) {
        self.category = category
        self.correctAnswers = correctAnswers
        self.totalQuestions = totalQuestions
        self.takenAt = takenAt
    }
}
