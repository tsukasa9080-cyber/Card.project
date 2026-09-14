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
        VStack {
            if displayedWords.isEmpty {
                ContentUnavailableView(
                    studyMode == .difficult ? "苦手な単語はありません" : "学習する単語はありません",
                    systemImage: "checkmark.circle",
                    description: Text(studyMode == .difficult ? "テストで間違えた単語がここに表示されます。" : "すべての単語を覚えました。")
                )
            } else {
                LoopingStudyCards(words: displayedWords)
                    .id(displayedWords.map(\.persistentModelID))
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

private struct LoopingStudyCards: View {
    let words: [Word]
    @State private var page: Int? = 0

    private var currentIndex: Int {
        guard !words.isEmpty else { return 0 }
        return ((page ?? 0) % words.count + words.count) % words.count
    }

    var body: some View {
        VStack {
            if words.count == 1 {
                CardView(word: words[0])
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !words.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 0) {
                        // 両端に隣のカードを置き、停止してから同じカードの本来の位置へ戻す。
                        ForEach(-1..<words.count + 1, id: \.self) { position in
                            let index = (position + words.count) % words.count
                            CardView(word: words[index])
                                .id(page == position)
                                .padding(.vertical, 20)
                                .containerRelativeFrame(.horizontal)
                                .frame(maxHeight: .infinity)
                                .id(position)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $page)
                .onScrollPhaseChange { _, phase in
                    guard phase == .idle, let page,
                          page < 0 || page >= words.count else { return }
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        self.page = currentIndex
                    }
                }
            }

            if !words.isEmpty {
                Text("\(currentIndex + 1) / \(words.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 12)
                    .accessibilityLabel("全\(words.count)語中\(currentIndex + 1)語目")
            }
        }
    }
}
