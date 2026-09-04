import SwiftUI
import SwiftData

enum StudyMode: String, CaseIterable, Identifiable {
    case unmemorized = "未学習"
    case difficult = "苦手"

    var id: Self { self }

    var iconName: String {
        switch self {
        case .unmemorized: "rectangle.portrait.on.rectangle.portrait.angled.fill"
        case .difficult: "exclamationmark.triangle.fill"
        }
    }
}

struct StudyView: View {
    private enum DisplayOrder: String, CaseIterable, Identifiable {
        case ascending = "昇順"
        case descending = "降順"
        case random = "ランダム"

        var id: Self { self }

        var iconName: String {
            switch self {
            case .random: "shuffle"
            case .ascending: "text.line.first.and.arrowtriangle.forward"
            case .descending: "text.line.last.and.arrowtriangle.forward"
            }
        }
    }

    let category: String
    let studyMode: StudyMode
    @Query private var words: [Word]

    @State private var displayOrder: DisplayOrder = .random
    @State private var randomWords: [Word] = []

    init(category: String, studyMode: StudyMode) {
        self.category = category
        self.studyMode = studyMode

        switch studyMode {
        case .unmemorized:
            _words = Query(
                filter: #Predicate<Word> { word in
                    word.category == category && !word.isMemorized
                },
                sort: \Word.english
            )
        case .difficult:
            _words = Query(
                filter: #Predicate<Word> { word in
                    word.category == category && word.isDifficult
                },
                sort: \Word.english
            )
        }
    }

    private var displayedWords: [Word] {
        switch displayOrder {
        case .random:
            randomWords.filter { randomWord in
                words.contains { $0.persistentModelID == randomWord.persistentModelID }
            }
        case .ascending:
            words
        case .descending:
            Array(words.reversed())
        }
    }
    
    var body: some View {
        // ※ ここにあった NavigationStack を削除しました
        VStack {
            if displayedWords.isEmpty {
                ContentUnavailableView(
                    studyMode == .difficult ? "苦手な単語はありません" : "学習する単語はありません",
                    systemImage: "checkmark.circle",
                    description: Text(studyMode == .difficult ? "テストで間違えた単語がここに表示されます。" : "すべての単語を覚えました。")
                )
            } else {
                TabView {
                    ForEach(displayedWords) { word in
                        CardView(word: word)
                            .padding(.vertical, 20)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))
            }
        }
        .navigationTitle("\(category)・\(studyMode.rawValue)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("出題順", selection: $displayOrder) {
                        ForEach(DisplayOrder.allCases) { order in
                            Label(order.rawValue, systemImage: order.iconName)
                                .tag(order)
                        }
                    }
                } label: {
                    Label(displayOrder.rawValue, systemImage: displayOrder.iconName)
                }
            }
        }
        .onAppear {
            shuffleWords()
        }
        .onChange(of: displayOrder) { _, _ in
            if displayOrder == .random {
                shuffleWords()
            }
        }
        .onChange(of: words.count) { _, _ in
            shuffleWords()
        }
    }

    private func shuffleWords() {
        randomWords = words.shuffled()
    }
}
