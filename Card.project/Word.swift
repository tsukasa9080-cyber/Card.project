import Foundation
import SwiftData

@Model
final class Word {
    // 既存データとの互換性のため、保存プロパティ名は維持しています。
    var english: String
    var japanese: String
    var isMemorized: Bool
    var isDifficult: Bool = false
    var category: String = "未分類"
    
    var frontText: String { english }
    var backText: String { japanese }

    init(frontText: String, backText: String, isMemorized: Bool = false, isDifficult: Bool = false, category: String = "未分類") {
        self.english = frontText
        self.japanese = backText
        self.isMemorized = isMemorized
        self.isDifficult = isDifficult
        self.category = category
    }
}
