import Foundation
import SwiftData

@Model
final class Word {
    // 既存データとの互換性のため、保存プロパティ名は維持しています。
    var english: String
    var japanese: String
    var isMemorized: Bool
    var isDifficult: Bool = false
    var category: String = "未登録"
    var testAttempts: Int = 0
    var testCorrectAnswers: Int = 0
    var consecutiveTestCorrect: Int = 0
    var lastTestSessionID: String = ""
    
    var frontText: String { english }
    var backText: String { japanese }

    var learningProgress: LearningProgress {
        get {
            LearningProgress(attempts: testAttempts, correctAnswers: testCorrectAnswers,
                             consecutiveCorrect: consecutiveTestCorrect, lastTestID: lastTestSessionID,
                             isMemorized: isMemorized, isDifficult: isDifficult)
        }
        set {
            testAttempts = newValue.attempts
            testCorrectAnswers = newValue.correctAnswers
            consecutiveTestCorrect = newValue.consecutiveCorrect
            lastTestSessionID = newValue.lastTestID
            isMemorized = newValue.isMemorized
            isDifficult = newValue.isDifficult
        }
    }

    init(frontText: String, backText: String, isMemorized: Bool = false, isDifficult: Bool = false, category: String = "未登録") {
        self.english = frontText
        self.japanese = backText
        self.isMemorized = isMemorized
        self.isDifficult = isDifficult
        self.category = category
    }
}
