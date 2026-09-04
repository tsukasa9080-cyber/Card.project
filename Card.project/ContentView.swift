import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Word.english) private var words: [Word]
    @Query(sort: \WordBook.name) private var wordBooks: [WordBook]
    @Query(sort: \TestResult.takenAt, order: .reverse) private var testResults: [TestResult]

    @State private var selectedCategory = "未分類"
    @State private var studyMode: StudyMode = .unmemorized
    @State private var testMode: TestMode = .multipleChoice
    @State private var testDirection: TestDirection = .frontToBack
    @State private var newEnglish = ""
    @State private var newJapanese = ""
    @State private var newWordBookName = ""
    @State private var isAddingWordBook = false
    @State private var searchText = ""
    @State private var editingWord: Word?
    @State private var isImportingCSV = false
    @State private var isExportingCSV = false
    @State private var importMessage = ""
    @State private var isShowingImportResult = false

    private var categories: [String] {
        Array(Set(["未分類"] + wordBooks.map(\.name) + words.map(\.category))).sorted()
    }

    private var displayedWords: [Word] {
        words.filter { $0.category == selectedCategory }
    }

    private var wordsToStudy: [Word] {
        displayedWords.filter { !$0.isMemorized }
    }

    private var difficultWords: [Word] {
        displayedWords.filter(\.isDifficult)
    }

    private var filteredWords: [Word] {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return displayedWords }

        return displayedWords.filter {
            $0.frontText.localizedCaseInsensitiveContains(keyword)
                || $0.backText.localizedCaseInsensitiveContains(keyword)
        }
    }

    private var csvDocument: CSVDocument {
        let header = ["表面", "裏面"].map(csvEscaped).joined(separator: ",")
        let rows = displayedWords.map {
            [csvEscaped($0.frontText), csvEscaped($0.backText)].joined(separator: ",")
        }
        return CSVDocument(text: ([header] + rows).joined(separator: "\n"))
    }

    private var selectedStudyWords: [Word] {
        switch studyMode {
        case .unmemorized: wordsToStudy
        case .difficult: difficultWords
        }
    }

    private var categoryTestResults: [TestResult] {
        testResults.filter { $0.category == selectedCategory }
    }

    private var latestTestResult: TestResult? {
        categoryTestResults.first
    }

    private var bestTestResult: TestResult? {
        categoryTestResults.max { lhs, rhs in
            Double(lhs.correctAnswers) / Double(lhs.totalQuestions) < Double(rhs.correctAnswers) / Double(rhs.totalQuestions)
        }
    }

    private var canTakeTest: Bool {
        !displayedWords.isEmpty && wordsToStudy.isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Menu {
                        ForEach(categories, id: \.self) { category in
                            Button(category) {
                                selectedCategory = category
                            }
                        }

                        Divider()

                        Button {
                            isAddingWordBook = true
                        } label: {
                            Label("単語帳を作成", systemImage: "plus")
                        }
                    } label: {
                        Label(selectedCategory, systemImage: "books.vertical.fill")
                            .font(.headline)
                    }

                    Spacer()

                    Text("\(displayedWords.count)語")
                        .foregroundStyle(.secondary)
                }
                .padding()

                if !displayedWords.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label("学習進捗", systemImage: "chart.bar.fill")
                            Spacer()
                            Text("\(displayedWords.count - wordsToStudy.count) / \(displayedWords.count)語")
                        }
                        .font(.subheadline)

                        ProgressView(
                            value: Double(displayedWords.count - wordsToStudy.count),
                            total: Double(displayedWords.count)
                        )
                        .tint(.green)
                    }
                    .padding(.horizontal)
                    .padding(.bottom)
                }

                HStack {
                    Text("出題対象")
                        .foregroundStyle(.secondary)
                    Picker("出題対象", selection: $studyMode) {
                        ForEach(StudyMode.allCases) { mode in
                            Label(mode.rawValue, systemImage: mode.iconName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.horizontal)
                .padding(.bottom)

                NavigationLink(destination: StudyView(category: selectedCategory, studyMode: studyMode)) {
                    HStack {
                        Image(systemName: studyMode.iconName)
                            .font(.title2)
                        Text("\(studyMode.rawValue)単語を学習 (\(selectedStudyWords.count)語)")
                            .font(.headline)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(selectedStudyWords.isEmpty ? Color.gray : Color.blue)
                    .cornerRadius(12)
                }
                .disabled(selectedStudyWords.isEmpty)
                .padding(.horizontal)
                .padding(.bottom)

                if let latestTestResult {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("テスト結果", systemImage: "checkmark.seal.fill")
                            .font(.headline)
                        Text("最新: \(latestTestResult.correctAnswers) / \(latestTestResult.totalQuestions)問正解（\(latestTestResult.takenAt.formatted(date: .abbreviated, time: .omitted))）")
                        if let bestTestResult {
                            Text("最高: \(bestTestResult.correctAnswers) / \(bestTestResult.totalQuestions)問正解")
                        }
                    }
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                    .padding(.bottom)
                }

                HStack {
                    Text("テスト形式")
                        .foregroundStyle(.secondary)
                    Picker("テスト形式", selection: $testMode) {
                        ForEach(TestMode.allCases) { mode in
                            Label(mode.rawValue, systemImage: mode.iconName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.horizontal)
                .padding(.bottom)

                HStack {
                    Text("出題方向")
                        .foregroundStyle(.secondary)
                    Picker("出題方向", selection: $testDirection) {
                        ForEach(TestDirection.allCases) { direction in
                            Text(direction.rawValue).tag(direction)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.horizontal)
                .padding(.bottom)

                NavigationLink(destination: TestView(category: selectedCategory, testMode: testMode, testDirection: testDirection)) {
                    Label("\(testDirection.rawValue)・\(testMode.rawValue)テストを受ける", systemImage: testMode.iconName)
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(canTakeTest ? Color.orange : Color.gray)
                        .cornerRadius(12)
                }
                .disabled(!canTakeTest)
                .padding(.horizontal)
                .padding(.bottom)

                Divider()

                HStack {
                    TextField("表面（問題）", text: $newEnglish)
                        .textFieldStyle(.roundedBorder)
                    TextField("裏面（答え）", text: $newJapanese)
                        .textFieldStyle(.roundedBorder)
                    Button("追加") {
                        addWord()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()

                List {
                    ForEach(filteredWords) { word in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(word.frontText)
                                    .font(.headline)
                                Text(word.backText)
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                            }

                            Spacer()

                            Button {
                                word.isMemorized.toggle()
                                try? modelContext.save()
                            } label: {
                                Image(systemName: word.isMemorized ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(word.isMemorized ? .green : .secondary)
                            }
                            .accessibilityLabel(word.isMemorized ? "学習済みを取り消す" : "学習済みにする")

                            Button {
                                word.isDifficult.toggle()
                                try? modelContext.save()
                            } label: {
                                Image(systemName: word.isDifficult ? "exclamationmark.triangle.fill" : "exclamationmark.triangle")
                                    .foregroundColor(word.isDifficult ? .orange : .secondary)
                            }
                            .accessibilityLabel(word.isDifficult ? "苦手登録を取り消す" : "苦手単語に登録する")

                            Button {
                                editingWord = word
                            } label: {
                                Image(systemName: "pencil")
                            }
                            .accessibilityLabel("単語を編集する")
                        }
                    }
                    .onDelete(perform: deleteWords)
                }
            }
            .navigationTitle("単語帳")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button {
                            isImportingCSV = true
                        } label: {
                            Label("CSVから一括登録", systemImage: "square.and.arrow.down")
                        }

                        Button {
                            isExportingCSV = true
                        } label: {
                            Label("この単語帳をCSVで保存", systemImage: "square.and.arrow.up")
                        }
                        .disabled(displayedWords.isEmpty)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                }
            }
            .alert("新しい単語帳", isPresented: $isAddingWordBook) {
                TextField("例: 英検2級", text: $newWordBookName)
                Button("キャンセル", role: .cancel) {
                    newWordBookName = ""
                }
                Button("作成") {
                    addWordBook()
                }
            } message: {
                Text("単語帳の名前を入力してください。")
            }
            .alert("CSVの読み込み", isPresented: $isShowingImportResult) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(importMessage)
            }
            .sheet(item: $editingWord) { word in
                WordEditorView(word: word)
            }
            .fileImporter(
                isPresented: $isImportingCSV,
                allowedContentTypes: [.commaSeparatedText, .plainText]
            ) { result in
                switch result {
                case .success(let url):
                    importCSV(from: url)
                case .failure(let error):
                    importMessage = "CSVを開けませんでした。\n\(error.localizedDescription)"
                    isShowingImportResult = true
                }
            }
            .fileExporter(
                isPresented: $isExportingCSV,
                document: csvDocument,
                contentType: .commaSeparatedText,
                defaultFilename: "\(selectedCategory)_単語帳"
            ) { result in
                if case .failure(let error) = result {
                    importMessage = "CSVを保存できませんでした。\n\(error.localizedDescription)"
                    isShowingImportResult = true
                }
            }
            .searchable(text: $searchText, prompt: "表面・裏面を検索")
        }
    }

    private func addWord() {
        let trimmedEnglish = newEnglish.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedJapanese = newJapanese.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedEnglish.isEmpty, !trimmedJapanese.isEmpty else { return }

        withAnimation {
            modelContext.insert(Word(frontText: trimmedEnglish, backText: trimmedJapanese, category: selectedCategory))
            try? modelContext.save()
            newEnglish = ""
            newJapanese = ""
        }
    }

    private func addWordBook() {
        let name = newWordBookName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        if !categories.contains(name) {
            modelContext.insert(WordBook(name: name))
            try? modelContext.save()
        }
        selectedCategory = name
        newWordBookName = ""
    }

    private func deleteWords(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(filteredWords[index])
            }
            try? modelContext.save()
        }
    }

    private func importCSV(from url: URL) {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try Data(contentsOf: url)
            guard let decodedText = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .shiftJIS) else {
                throw CocoaError(.fileReadInapplicableStringEncoding)
            }
            let text = decodedText.replacingOccurrences(of: "\u{FEFF}", with: "")
            var rows = parseCSV(text)

            if let firstRow = rows.first, firstRow.count >= 2,
               ["表面", "front", "question"].contains(firstRow[0].lowercased()),
               ["裏面", "back", "answer"].contains(firstRow[1].lowercased()) {
                rows.removeFirst()
            }

            var importedCount = 0
            for row in rows where row.count >= 2 {
                let front = row[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let back = row[1].trimmingCharacters(in: .whitespacesAndNewlines)
                guard !front.isEmpty, !back.isEmpty else { continue }

                modelContext.insert(Word(frontText: front, backText: back, category: selectedCategory))
                importedCount += 1
            }
            try modelContext.save()

            importMessage = importedCount > 0
                ? "\(importedCount)語を「\(selectedCategory)」に追加しました。"
                : "追加できる行が見つかりませんでした。表面・裏面の2列を確認してください。"
        } catch {
            importMessage = "CSVを読み込めませんでした。\n\(error.localizedDescription)"
        }
        isShowingImportResult = true
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Word.self, WordBook.self, TestResult.self], inMemory: true)
}
