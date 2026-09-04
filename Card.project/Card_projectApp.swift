import SwiftUI
import SwiftData

@main
struct Card_projectApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [Word.self, WordBook.self, TestResult.self])
    }
}
