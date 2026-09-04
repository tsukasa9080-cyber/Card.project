import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ContentView: View {
    private enum EntryField: Hashable {
        case front
        case back
    }

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Word.english) private var words: [Word]
    @Query(sort: \WordBook.name) private var wordBooks: [WordBook]
    @Query(sort: \TestResult.takenAt, order: .reverse) private var testResults: [TestResult]

    @AppStorage("defaultCategoryName") private var defaultCategoryName = "未分類"
    @State private var selectedCategory: String
    @State private var studyMode: StudyMode = .unmemorized
    @State private var testMode: TestMode = .multipleChoice
    @State private var testDirection: TestDirection = .frontToBack
    @State private var testScope: TestScope = .all
    @State private var newEnglish = ""
    @State private var newJapanese = ""
    @State private var newWordBookName = ""
    @State private var isAddingWordBook = false
    @State private var renamedWordBookName = ""
    @State private var isRenamingWordBook = false
    @State private var searchText = ""
    @State private var editingWord: Word?
    @State private var isImportingCSV = false
    @State private var isExportingCSV = false
    @State private var importMessage = ""
    @State private var isShowingImportResult = false
    @State private var selectedWordIDs = Set<PersistentIdentifier>()
    @State private var wordListEditMode: EditMode = .inactive
    @State private var isConfirmingBulkDeletion = false
    @FocusState private var focusedEntryField: EntryField?
    @FocusState private var isSearchFocused: Bool

    init() {
        _selectedCategory = State(
            initialValue: UserDefaults.standard.string(forKey: "defaultCategoryName") ?? "未分類"
        )
    }

    private var categories: [String] {
        Array(Set([defaultCategoryName] + wordBooks.map(\.name) + words.map(\.category))).sorted()
    }

    private var displayedWords: [Word] {
        words.filter { $0.category == selectedCategory }
    }

    private var filteredWords: [Word] {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return displayedWords }
        return displayedWords.filter {
            $0.frontText.localizedCaseInsensitiveContains(keyword)
                || $0.backText.localizedCaseInsensitiveContains(keyword)
        }
    }

    private var wordsToStudy: [Word] { displayedWords.filter { !$0.isMemorized } }
    private var difficultWords: [Word] { displayedWords.filter(\.isDifficult) }

    private var selectedStudyWords: [Word] {
        studyMode == .unmemorized ? wordsToStudy : difficultWords
    }

    private var categoryTestResults: [TestResult] {
        testResults.filter { $0.category == selectedCategory }
    }

    private var latestTestResult: TestResult? { categoryTestResults.first }

    private var bestTestResult: TestResult? {
        categoryTestResults.max {
            Double($0.correctAnswers) / Double($0.totalQuestions)
                < Double($1.correctAnswers) / Double($1.totalQuestions)
        }
    }

    private var testWords: [Word] {
        testScope == .all ? displayedWords : difficultWords
    }

    private var canTakeTest: Bool { !testWords.isEmpty }

    private var csvDocument: CSVDocument {
        let header = ["表面", "裏面"].map(csvEscaped).joined(separator: ",")
        let rows = displayedWords.map {
            [csvEscaped($0.frontText), csvEscaped($0.backText)].joined(separator: ",")
        }
        return CSVDocument(text: ([header] + rows).joined(separator: "\n"))
    }

    var body: some View {
        TabView {
            wordsTab
                .tabItem { Label("単語登録", systemImage: "square.and.pencil") }

            studyTab
                .tabItem { Label("学習", systemImage: "rectangle.portrait.on.rectangle.portrait.angled.fill") }

            testTab
                .tabItem { Label("テスト", systemImage: "checkmark.seal") }
        }
        .alert("新しい単語帳", isPresented: $isAddingWordBook) {
            TextField("例: 英検2級", text: $newWordBookName)
            Button("キャンセル", role: .cancel) { newWordBookName = "" }
            Button("作成") { addWordBook() }
        } message: {
            Text("単語帳の名前を入力してください。")
        }
        .alert("単語帳名を変更", isPresented: $isRenamingWordBook) {
            TextField("単語帳の名前", text: $renamedWordBookName)
            Button("キャンセル", role: .cancel) { renamedWordBookName = "" }
            Button("変更") { renameWordBook() }
        } message: {
            Text("登録済みの単語とテスト結果も新しい名前へ引き継がれます。")
        }
        .alert("CSVの読み込み", isPresented: $isShowingImportResult) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(importMessage)
        }
        .alert("選択した\(selectedWordIDs.count)語を削除しますか？", isPresented: $isConfirmingBulkDeletion) {
            Button("削除", role: .destructive) {
                deleteSelectedWords()
            }
            Button("キャンセル", role: .cancel) { }
        } message: {
            Text("この操作は取り消せません。")
        }
        .sheet(item: $editingWord) { word in
            WordEditorView(word: word)
        }
        .fileImporter(
            isPresented: $isImportingCSV,
            allowedContentTypes: [.commaSeparatedText, .plainText]
        ) { result in
            switch result {
            case .success(let url): importCSV(from: url)
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
    }

    private var studyTab: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    wordBookSelector
                    progressCard

                    VStack(alignment: .leading, spacing: 8) {
                        Text("出題対象").font(.headline)
                        Picker("出題対象", selection: $studyMode) {
                            ForEach(StudyMode.allCases) { mode in
                                Label(mode.rawValue, systemImage: mode.iconName).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    NavigationLink(destination: StudyView(category: selectedCategory, studyMode: studyMode)) {
                        Label("\(studyMode.rawValue)単語を学習（\(selectedStudyWords.count)語）", systemImage: studyMode.iconName)
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(selectedStudyWords.isEmpty ? .gray : .blue, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(selectedStudyWords.isEmpty)
                }
                .padding()
            }
            .navigationTitle("学習")
        }
    }

    private var wordsTab: some View {
        NavigationStack {
            VStack(spacing: 0) {
                wordBookSelector
                    .padding()

                HStack {
                    TextField("表面", text: $newEnglish)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedEntryField, equals: .front)
                    TextField("裏面", text: $newJapanese)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedEntryField, equals: .back)
                    Button("追加") {
                        dismissKeyboard()
                        addWord()
                    }
                        .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal)
                .padding(.bottom)

                List {
                    ForEach(filteredWords) { word in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(word.frontText).font(.headline)
                                Text(word.backText).font(.subheadline).foregroundStyle(.secondary)
                            }

                            if wordListEditMode == .inactive {
                                Spacer()
                                Button {
                                    dismissKeyboard()
                                    word.isMemorized.toggle()
                                    try? modelContext.save()
                                } label: {
                                    Label(
                                        "覚えた",
                                        systemImage: word.isMemorized ? "checkmark.circle.fill" : "circle"
                                    )
                                    .foregroundStyle(word.isMemorized ? .green : .secondary)
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel(word.isMemorized ? "学習済みを取り消す" : "覚えた")

                                Button {
                                    dismissKeyboard()
                                    word.isDifficult.toggle()
                                    try? modelContext.save()
                                } label: {
                                    Label(
                                        "苦手",
                                        systemImage: word.isDifficult ? "exclamationmark.triangle.fill" : "exclamationmark.triangle"
                                    )
                                    .foregroundStyle(word.isDifficult ? .orange : .secondary)
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel(word.isDifficult ? "苦手登録を取り消す" : "苦手単語に登録する")

                                Button {
                                    dismissKeyboard()
                                    editingWord = word
                                } label: {
                                    Label("編集", systemImage: "pencil")
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("この単語を編集する")
                            } else {
                                Spacer()
                                Image(systemName: selectedWordIDs.contains(word.persistentModelID) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedWordIDs.contains(word.persistentModelID) ? .blue : .secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard wordListEditMode == .active else { return }
                            toggleWordSelection(word)
                        }
                        .accessibilityElement(children: wordListEditMode == .active ? .ignore : .contain)
                        .accessibilityLabel(wordListEditMode == .active ? "\\(word.frontText) を選択" : "")
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                dismissKeyboard()
            }
            .navigationTitle("単語登録・編集")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button { isImportingCSV = true } label: {
                            Label("CSVから一括登録", systemImage: "square.and.arrow.down")
                        }
                        Button { isExportingCSV = true } label: {
                            Label("この単語帳をCSVで保存", systemImage: "square.and.arrow.up")
                        }
                        .disabled(displayedWords.isEmpty)
                    } label: { Image(systemName: "ellipsis.circle") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if wordListEditMode == .active {
                        HStack {
                            Button("削除（\(selectedWordIDs.count)）", role: .destructive) {
                                isConfirmingBulkDeletion = true
                            }
                            .disabled(selectedWordIDs.isEmpty)

                            Button("完了") {
                                wordListEditMode = .inactive
                                selectedWordIDs.removeAll()
                            }
                        }
                    } else {
                        Button("選択") {
                            dismissKeyboard()
                            wordListEditMode = .active
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "検索")
            .searchFocused($isSearchFocused)
        }
    }

    private var testTab: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    wordBookSelector

                    if let latestTestResult {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("テスト結果", systemImage: "checkmark.seal.fill").font(.headline)
                            Text("最新: \(latestTestResult.correctAnswers) / \(latestTestResult.totalQuestions)問正解（\(latestTestResult.takenAt.formatted(date: .abbreviated, time: .omitted))）")
                            if let bestTestResult {
                                Text("最高: \(bestTestResult.correctAnswers) / \(bestTestResult.totalQuestions)問正解")
                            }
                        }
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                    }

                    testSettingPicker(title: "テスト形式", selection: $testMode) {
                        ForEach(TestMode.allCases) { mode in
                            Label(mode.rawValue, systemImage: mode.iconName).tag(mode)
                        }
                    }

                    testSettingPicker(title: "出題方向", selection: $testDirection) {
                        ForEach(TestDirection.allCases) { direction in
                            Text(direction.rawValue).tag(direction)
                        }
                    }

                    testSettingPicker(title: "出題対象", selection: $testScope) {
                        ForEach(TestScope.allCases) { scope in
                            Label(scope.rawValue, systemImage: scope.iconName).tag(scope)
                        }
                    }

                    NavigationLink(destination: TestView(category: selectedCategory, testMode: testMode, testDirection: testDirection, testScope: testScope)) {
                        Label("\(testScope.rawValue)・\(testDirection.rawValue)・\(testMode.rawValue)テストを受ける（\(testWords.count)語）", systemImage: testMode.iconName)
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(canTakeTest ? .orange : .gray, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(!canTakeTest)

                }
                .padding()
            }
            .navigationTitle("テスト")
        }
    }

    private var wordBookSelector: some View {
        HStack {
            Menu {
                ForEach(categories, id: \.self) { category in
                    Button(category) {
                        dismissKeyboard()
                        selectedCategory = category
                    }
                }
                Divider()
                Button { isAddingWordBook = true } label: {
                    Label("単語帳を作成", systemImage: "plus")
                }
                Button {
                    renamedWordBookName = selectedCategory
                    isRenamingWordBook = true
                } label: {
                    Label("単語帳名を変更", systemImage: "pencil")
                }
            } label: {
                Label(selectedCategory, systemImage: "books.vertical.fill").font(.headline)
            }
            Spacer()
            Text("\(displayedWords.count)語").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var progressCard: some View {
        if !displayedWords.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("学習進捗", systemImage: "chart.bar.fill")
                    Spacer()
                    Text("\(displayedWords.count - wordsToStudy.count) / \(displayedWords.count)語")
                }
                .font(.subheadline)
                ProgressView(value: Double(displayedWords.count - wordsToStudy.count), total: Double(displayedWords.count))
                    .tint(.green)
            }
            .padding()
            .background(.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func testSettingPicker<Content: View>(
        title: String,
        selection: Binding<TestMode>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Picker(title, selection: selection, content: content).pickerStyle(.segmented)
        }
    }

    private func testSettingPicker<Content: View>(
        title: String,
        selection: Binding<TestDirection>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Picker(title, selection: selection, content: content).pickerStyle(.segmented)
        }
    }

    private func testSettingPicker<Content: View>(
        title: String,
        selection: Binding<TestScope>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Picker(title, selection: selection, content: content).pickerStyle(.segmented)
        }
    }

    private func addWord() {
        let front = newEnglish.trimmingCharacters(in: .whitespacesAndNewlines)
        let back = newJapanese.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !front.isEmpty, !back.isEmpty else { return }
        modelContext.insert(Word(frontText: front, backText: back, category: selectedCategory))
        try? modelContext.save()
        newEnglish = ""
        newJapanese = ""
    }

    private func dismissKeyboard() {
        focusedEntryField = nil
        isSearchFocused = false
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

    private func renameWordBook() {
        let newName = renamedWordBookName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty, newName != selectedCategory, !categories.contains(newName) else { return }

        let oldName = selectedCategory
        if oldName == defaultCategoryName {
            defaultCategoryName = newName
        }
        if !wordBooks.contains(where: { $0.name == newName }) {
            modelContext.insert(WordBook(name: newName))
        }
        for wordBook in wordBooks where wordBook.name == oldName {
            wordBook.name = newName
        }
        for word in words where word.category == oldName {
            word.category = newName
        }
        for result in testResults where result.category == oldName {
            result.category = newName
        }
        try? modelContext.save()
        selectedCategory = newName
        renamedWordBookName = ""
    }

    private func toggleWordSelection(_ word: Word) {
        let id = word.persistentModelID
        if selectedWordIDs.contains(id) {
            selectedWordIDs.remove(id)
        } else {
            selectedWordIDs.insert(id)
        }
    }

    private func deleteSelectedWords() {
        for word in words where selectedWordIDs.contains(word.persistentModelID) {
            modelContext.delete(word)
        }
        try? modelContext.save()
        selectedWordIDs.removeAll()
        wordListEditMode = .inactive
    }

    private func importCSV(from url: URL) {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            guard let decodedText = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .shiftJIS) else {
                throw CocoaError(.fileReadInapplicableStringEncoding)
            }
            var rows = parseCSV(decodedText.replacingOccurrences(of: "\u{FEFF}", with: ""))
            if let first = rows.first, first.count >= 2,
               ["表面", "front", "question"].contains(first[0].lowercased()),
               ["裏面", "back", "answer"].contains(first[1].lowercased()) {
                rows.removeFirst()
            }
            var count = 0
            for row in rows where row.count >= 2 {
                let front = row[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let back = row[1].trimmingCharacters(in: .whitespacesAndNewlines)
                guard !front.isEmpty, !back.isEmpty else { continue }
                modelContext.insert(Word(frontText: front, backText: back, category: selectedCategory))
                count += 1
            }
            try modelContext.save()
            importMessage = count > 0 ? "\(count)語を「\(selectedCategory)」に追加しました。" : "追加できる行が見つかりませんでした。"
        } catch {
            importMessage = "CSVを読み込めませんでした。\n\(error.localizedDescription)"
        }
        isShowingImportResult = true
    }
}

#Preview {
    ContentView().modelContainer(for: [Word.self, WordBook.self, TestResult.self], inMemory: true)
}
