import Foundation
import SwiftData

@Model
final class WordBook {
    var name: String

    init(name: String) {
        self.name = name
    }
}
