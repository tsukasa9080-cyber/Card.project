import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ContentView: View {
    private enum MainTab: Int, CaseIterable, Identifiable {
        case words, study, test
        var id: Int { rawValue }
        var title: String {
            switch self {
            case .words: "単語登録"
            case .study: "学習"
            case .test: "テスト"
            }
        }
        var icon: String {
            switch self {
            case .words: "square.and.pencil"
            case .study: "rectangle.portrait.on.rectangle.portrait.angled.fill"
            case .test: "checkmark.seal"
            }
        }
    }
    @State private var selectedTab: MainTab = .words
    @State private var isStudying = false

    private enum EntryField: Hashable {
        case front
        case back
    }

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Word.english) private var words: [Word]
    @Query(sort: \WordBook.name) private var wordBooks: [WordBook]
    @Query(sort: \TestResult.takenAt, order: .reverse) private var testResults: [TestResult]

    @AppStorage("defaultCategoryName") private var defaultCategoryName = "未登録"
    @AppStorage("meaningServerURL") private var meaningServerURL = "http://127.0.0.1:3000"
    @State private var selectedCategory: String
    @State private var studyMode: StudyMode = .unmemorized
    @State private var testMode: TestMode = .multipleChoice
    @State private var testDirection: TestDirection = .frontToBack
    @State private var testScope: TestScope = .all
    @AppStorage("testQuestionLimit") private var testQuestionLimit = 10
    @State private var newEnglish = ""
    @State private var newJapanese = ""
    @State private var newWordBookName = ""
    @State private var isAddingWordBook = false
    @State private var renamedWordBookName = ""
    @State private var isRenamingWordBook = false
    @State private var searchText = ""
    @State private var editingWord: Word?
    @State private var isImportingCSV = false
    @State private var receivedBook: SharedWordBook?
    @State private var showsExchange = false
    @State private var isExportingCSV = false
    @State private var importMessage = ""
    @State private var isShowingImportResult = false
    @State private var selectedWordIDs = Set<PersistentIdentifier>()
    @State private var isConfirmingBulkDeletion = false
    @State private var saveError: String?
    @State private var isGeneratingMeaning = false
    @State private var generationMessage = ""
    @State private var isShowingGenerationMessage = false
    @State private var isSettingMeaningServerURL = false
    @State private var draftMeaningServerURL = ""
    @FocusState private var focusedEntryField: EntryField?
    @FocusState private var isSearchFocused: Bool

    init() {
        _selectedCategory = State(
            initialValue: UserDefaults.standard.string(forKey: "defaultCategoryName") ?? "未登録"
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
        displayedWords.filter { testScope.includes($0) }
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
        fileHandlingView
    }

    private var mainTabs: some View {
        TabView(selection: $selectedTab) {
            wordsTab.tag(MainTab.words)
            studyTab.tag(MainTab.study)
            testTab.tag(MainTab.test)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            mainTabBar
        }
        .onChange(of: selectedTab) { _, _ in
            dismissKeyboard()
        }
    }

    private var alertsView: some View {
        mainTabs
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
        .alert("ファイルの読み込み", isPresented: $isShowingImportResult) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(importMessage)
        }
        .alert("生成AI", isPresented: $isShowingGenerationMessage) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(generationMessage)
        }
        .alert("生成AIサーバーURL", isPresented: $isSettingMeaningServerURL) {
            TextField("http://127.0.0.1:3000", text: $draftMeaningServerURL)
            Button("キャンセル", role: .cancel) { draftMeaningServerURL = meaningServerURL }
            Button("保存") { saveMeaningServerURL() }
        } message: {
            Text("OpenAI APIキーではなく、自分のサーバーURLを入力してください。")
        }
        .alert("選択した\(selectedWordIDs.count)語を削除しますか？", isPresented: $isConfirmingBulkDeletion) {
            Button("削除", role: .destructive) {
                deleteSelectedWords()
            }
            Button("キャンセル", role: .cancel) { }
        } message: {
            Text("この操作は取り消せません。")
        }
        .alert("保存エラー", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("OK", role: .cancel) { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
    }

    private var sheetsView: some View {
        alertsView
        .sheet(item: $editingWord) { word in
            WordEditorView(word: word)
        }
        .sheet(isPresented: $showsExchange) {
            NavigationStack {
                List {
                    Section("送る単語帳") {
                        Text(selectedCategory).font(.headline)
                        Text("\(displayedWords.count)語")
                        ShareLink(item: sharedWordBook, preview: SharePreview(selectedCategory)) {
                            Label("単語帳を送る", systemImage: "square.and.arrow.up")
                        }.disabled(displayedWords.isEmpty)
                    }
                    Section {
                        Text("共有メニューでAirDropやメッセージなどを選べます。相手にもこのアプリが必要です。学習状況やテスト結果は含まれません。")
                        Text("受け取るときは、受信した.cardbookファイルを開くか、メニューの「ファイルから読み込む」を使ってください。")
                    }
                }
                .navigationTitle("単語帳を交換")
                .toolbar { Button("閉じる") { showsExchange = false } }
            }
        }
        .sheet(item: $receivedBook) { book in
            WordBookImportView(book: book) { name in
                selectedCategory = name
            }
        }
    }

    private var sharedWordBook: SharedWordBook {
        let cards = displayedWords.map { SharedWordBook.Card(front: $0.frontText, back: $0.backText) }
        return SharedWordBook(version: 1, name: selectedCategory, cards: cards)
    }

    private var fileHandlingView: some View {
        sheetsView
        .onOpenURL { url in
            receiveBook(url)
        }
        .fileImporter(
            isPresented: $isImportingCSV,
            allowedContentTypes: [.cardBook, .commaSeparatedText, .plainText]
        ) { result in
            switch result {
            case .success(let url):
                if url.pathExtension.lowercased() == "cardbook" { receiveBook(url) }
                else { importCSV(from: url) }
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

    private var mainTabBar: some View {
        HStack(spacing: 0) {
            ForEach(MainTab.allCases) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { selectedTab = tab }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon).font(.system(size: 21))
                        Text(tab.title)
                            .font(.caption)
                            // ラベルの左右に全角文字のおよそ半分ずつ余白を置き、
                            // 太字表示時も隣の項目と詰まりすぎないようにする。
                            .padding(.horizontal, 4)
                    }
                    .foregroundStyle(selectedTab == tab ? Color.accentColor : Color.secondary)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
            }
        }
        .padding(.top, 4)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
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

                    Button { isStudying = true } label: {
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
        .fullScreenCover(isPresented: $isStudying) {
            NavigationStack {
                StudyView(category: selectedCategory, studyMode: studyMode)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("戻る", systemImage: "chevron.left") { isStudying = false }
                        }
                    }
            }
        }
    }

    private var wordRegistrationForm: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Label("表面 · 単語・用語", systemImage: "rectangle.portrait")
                    .font(.subheadline.weight(.semibold))
                TextField("例：apple / 光合成", text: $newEnglish, axis: .vertical)
                    .lineLimit(1...3)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedEntryField, equals: .front)
                    .padding(12)
                    .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityLabel("表面の単語・用語")
                    .disabled(isGeneratingMeaning)
            }

            VStack(alignment: .leading, spacing: 8) {
                Label("裏面 · 意味・答え", systemImage: "text.alignleft")
                    .font(.subheadline.weight(.semibold))
                TextField("意味を入力、またはAIで生成", text: $newJapanese, axis: .vertical)
                    .lineLimit(3...6)
                    .focused($focusedEntryField, equals: .back)
                    .padding(12)
                    .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityLabel("裏面の意味・答え")
                    .disabled(isGeneratingMeaning)

                Button {
                    dismissKeyboard()
                    generateMeaning()
                } label: {
                    HStack(spacing: 8) {
                        if isGeneratingMeaning { ProgressView() }
                        Label(isGeneratingMeaning ? "意味を生成中…" : "AIで意味を生成", systemImage: "sparkles")
                    }
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)
                .disabled(isGeneratingMeaning || newEnglish.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Text("生成した意味は、確認してから編集できます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                dismissKeyboard()
                addWord()
            } label: {
                Label("単語帳に追加", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isGeneratingMeaning || newEnglish.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || newJapanese.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var wordsTab: some View {
        NavigationStack {
            VStack(spacing: 0) {
                wordBookSelector
                    .padding()
                    .background(Color(.systemGroupedBackground))

                List {
                    Section {
                        wordRegistrationForm
                            .listRowInsets(EdgeInsets(top: 18, leading: 16, bottom: 18, trailing: 16))
                    } header: {
                        Text("新しい単語")
                    }

                    ForEach(filteredWords) { word in
                        wordRow(word)
                    }
                }
                .scrollDismissesKeyboard(.interactively)
                .scrollContentBackground(.hidden)
                .background(Color(.systemGroupedBackground))
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("単語登録・編集")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button { showsExchange = true } label: {
                            Label("単語帳を交換", systemImage: "person.2.wave.2")
                        }
                        Button { isImportingCSV = true } label: {
                            Label("ファイルから読み込む", systemImage: "square.and.arrow.down")
                        }
                        Button { isExportingCSV = true } label: {
                            Label("この単語帳をCSVで保存", systemImage: "square.and.arrow.up")
                        }
                        .disabled(displayedWords.isEmpty)
                        Divider()
                        Button {
                            draftMeaningServerURL = meaningServerURL
                            isSettingMeaningServerURL = true
                        } label: {
                            Label("生成AIサーバーURLを設定", systemImage: "server.rack")
                        }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("削除（\(selectedWordIDs.count)）", role: .destructive) {
                        dismissKeyboard()
                        isConfirmingBulkDeletion = true
                    }
                    .disabled(selectedWordIDs.isEmpty)
                }
            }
            .searchable(text: $searchText, prompt: "検索")
            .searchFocused($isSearchFocused)
            .onChange(of: selectedCategory) { _, _ in
                selectedWordIDs.removeAll()
            }
            .onChange(of: searchText) { _, _ in
                selectedWordIDs.formIntersection(filteredWords.map(\.persistentModelID))
            }
        }
    }


    private func wordRow(_ word: Word) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                dismissKeyboard()
                toggleWordSelection(word)
            } label: {
                HStack {
                    Image(systemName: selectedWordIDs.contains(word.persistentModelID) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selectedWordIDs.contains(word.persistentModelID) ? .blue : .secondary)
                    VStack(alignment: .leading) {
                        Text(word.frontText).font(.headline)
                        Text(word.backText).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(word.frontText)、\(word.backText)")
            .accessibilityValue(selectedWordIDs.contains(word.persistentModelID) ? "選択中" : "未選択")
            .accessibilityHint("タップして削除対象の選択を切り替えます")

            if word.testAttempts > 0 {
                Text("正答率 \(Int(word.learningProgress.correctRate * 100))%（\(word.testCorrectAnswers)/\(word.testAttempts)回）・連続正解 \(word.consecutiveTestCorrect)/3回")
                    .font(.caption).foregroundStyle(.secondary)
            }

            HStack(spacing: 16) {
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

                Spacer(minLength: 0)
                Button {
                    dismissKeyboard()
                    editingWord = word
                } label: {
                    Label("編集", systemImage: "pencil")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("この単語を編集する")
            }
            .font(.subheadline)
            .labelStyle(.titleAndIcon)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
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

                    Stepper("1回の問題数：\(testQuestionLimit)問", value: $testQuestionLimit, in: 1...100)
                    Text(testScope == .review
                         ? "覚えた単語を均等に出題します。間違えた単語は未習得に戻ります。"
                         : "最初の3回答は均等に、その後は正答率が低い単語を優先します。別々のテストで3回連続正解すると「覚えた」になります。")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("候補\(testWords.count)語から最大\(testQuestionLimit)問を選び、同じ単語は1回だけ出題します。候補が問題数以下なら全語を出題します。")
                        .font(.caption).foregroundStyle(.secondary)

                    NavigationLink(destination: TestView(category: selectedCategory, testMode: testMode, testDirection: testDirection, testScope: testScope, questionLimit: testQuestionLimit)) {
                        Label("\(testScope.rawValue)・\(testDirection.rawValue)・\(testMode.rawValue)テストを受ける（\(min(testQuestionLimit, testWords.count))問）", systemImage: testMode.iconName)
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(canTakeTest ? .orange : .gray, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(!canTakeTest)
                    if !canTakeTest {
                        Text(testScope == .review ? "覚えた単語がまだありません。" : "出題対象の単語がありません。覚えた単語は「復習」で確認できます。")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }

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
        let word = Word(frontText: front, backText: back, category: selectedCategory)
        modelContext.insert(word)
        do {
            try modelContext.save()
            newEnglish = ""
            newJapanese = ""
        } catch {
            modelContext.delete(word)
            saveError = "単語を追加できませんでした。\(error.localizedDescription)"
        }
    }

    private func generateMeaning() {
        let front = newEnglish.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !front.isEmpty else { return }
        isGeneratingMeaning = true
        Task {
            do {
                newJapanese = try await MeaningGenerator.generateMeaning(for: front)
                focusedEntryField = .back
            } catch {
                generationMessage = error.localizedDescription
                isShowingGenerationMessage = true
            }
            isGeneratingMeaning = false
        }
    }

    private func saveMeaningServerURL() {
        meaningServerURL = draftMeaningServerURL.trimmingCharacters(in: .whitespacesAndNewlines)
        draftMeaningServerURL = meaningServerURL
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
        do {
            try WordBookStore.rename(from: oldName, to: newName, in: modelContext.container)
            if oldName == defaultCategoryName { defaultCategoryName = newName }
            selectedCategory = newName
            renamedWordBookName = ""
        } catch {
            saveError = "単語帳名を変更できませんでした。\(error.localizedDescription)"
        }
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
        let context = ModelContext(modelContext.container)
        context.autosaveEnabled = false
        do {
            let savedWords = try context.fetch(FetchDescriptor<Word>())
            for word in savedWords where word.category == selectedCategory && selectedWordIDs.contains(word.persistentModelID) {
                context.delete(word)
            }
            try context.save()
            selectedWordIDs.removeAll()
        } catch {
            context.rollback()
            saveError = "削除できませんでした。選択した単語は残っています。\(error.localizedDescription)"
        }
    }

    private func receiveBook(_ url: URL) {
        do {
            let book = try SharedWordBook.read(url)
            showsExchange = false
            receivedBook = book
        } catch {
            importMessage = "単語帳を開けませんでした。\n\(error.localizedDescription)"
            isShowingImportResult = true
        }
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
    let container = try! ModelContainer(
        for: Word.self, WordBook.self, TestResult.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let category = UserDefaults.standard.string(forKey: "defaultCategoryName") ?? "未登録"
    container.mainContext.insert(Word(frontText: "apple", backText: "りんご", category: category))
    container.mainContext.insert(Word(frontText: "book", backText: "本", category: category))
    container.mainContext.insert(Word(frontText: "study", backText: "勉強する", category: category))
    return ContentView().modelContainer(container)
}
