import Foundation
import SwiftData

@Model
final class Word {
    var english: String
    var japanese: String
    var isMemorized: Bool
    
    init(english: String, japanese: String, isMemorized: Bool = false) {
        self.english = english
        self.japanese = japanese
        self.isMemorized = isMemorized
    }
}
