import SwiftUI
import SwiftData

enum TestMode: String, CaseIterable, Identifiable {
    case multipleChoice = "4択"
    case typing = "入力"

    var id: Self { self }

    var iconName: String {
        switch self {
        case .multipleChoice: "list.bullet"
        case .typing: "keyboard"
        }
    }
}

enum TestDirection: String, CaseIterable, Identifiable {
    case frontToBack = "表→裏"
    case backToFront = "裏→表"

    var id: Self { self }

    func prompt(for word: Word) -> String {
        switch self {
        case .frontToBack: word.frontText
        case .backToFront: word.backText
        }
    }

    func answer(for word: Word) -> String {
        switch self {
        case .frontToBack: word.backText
        case .backToFront: word.frontText
        }
    }
}

enum TestScope: String, CaseIterable, Identifiable {
    case all = "未習得"
    case difficult = "苦手のみ"
    case review = "復習"

    var id: Self { self }

    var iconName: String {
        switch self {
        case .all: "rectangle.stack"
        case .difficult: "exclamationmark.triangle.fill"
        case .review: "arrow.clockwise"
        }
    }

    func includes(_ word: Word) -> Bool {
        switch self {
        case .all: !word.isMemorized
        case .difficult: !word.isMemorized && word.isDifficult
        case .review: word.isMemorized
        }
    }
}

struct TestView: View {
    @Environment(\.modelContext) private var modelContext
    let category: String
    let testMode: TestMode
    let testDirection: TestDirection
    let testScope: TestScope
    let questionLimit: Int
    @Query private var words: [Word]

    @State private var questions: [Word] = []
    @State private var choices: [String] = []
    @State private var questionIndex = 0
    @State private var correctAnswers = 0
    @State private var selectedAnswer: String?
    @State private var typedAnswer = ""
    @State private var hasFinished = false
    @State private var usesAI = false
    @State private var isBusy = false
    @State private var aiQuestion: String?
    @State private var aiFeedback: String?
    @State private var errorMessage: String?
    @State private var aiTask: Task<Void, Never>?
    @State private var requestID = UUID()
    @State private var recordedCorrect = false
    @State private var previousProgress: LearningProgress?
    @State private var testSessionID = UUID().uuidString


    init(category: String, testMode: TestMode, testDirection: TestDirection, testScope: TestScope, questionLimit: Int = 10) {
        self.category = category
        self.testMode = testMode
        self.testDirection = testDirection
        self.testScope = testScope
        self.questionLimit = questionLimit
        _words = Query(filter: #Predicate<Word> { $0.category == category }, sort: \Word.english)
    }

    private var currentQuestion: Word? {
        guard questions.indices.contains(questionIndex) else { return nil }
        return questions[questionIndex]
    }

    var body: some View {
        Group {
            if hasFinished {
                resultView
            } else if let question = currentQuestion {
                questionView(question)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("\(testScope.rawValue)・\(testDirection.rawValue)テスト")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            requestID = UUID()
            aiTask?.cancel()
            isBusy = false
        }
        .onAppear {
            if questions.isEmpty {
                startTest()
            } else if usesAI && testMode == .multipleChoice && choices.isEmpty && !hasFinished {
                prepareChoices()
            }
        }
    }

    private var resultView: some View {
        VStack(spacing: 24) {
            Image(systemName: !questions.isEmpty && correctAnswers == questions.count ? "trophy.fill" : "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundStyle(.yellow)

            Text(questions.isEmpty ? "出題できる単語がありません" : "テスト完了！")
                .font(.title.bold())

            Text("\(questions.count)問中 \(correctAnswers)問正解")
                .font(.title2)

            Button("もう一度テストする") {
                startTest()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func questionView(_ question: Word) -> some View {
        ScrollView {
        VStack(spacing: 24) {
            Toggle("AIで問題作成・入力採点", isOn: $usesAI)
                .disabled(isBusy || selectedAnswer != nil)
                .onChange(of: usesAI) { _, _ in
                    aiQuestion = nil
                    aiFeedback = nil
                    errorMessage = nil
                    prepareChoices()
                }
            ProgressView(value: Double(questionIndex + 1), total: Double(questions.count))
                .tint(.blue)

            Text("第\(questionIndex + 1)問 / \(questions.count)問")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let aiQuestion { Text(aiQuestion).font(.headline) }
            Text("「\(testDirection.prompt(for: question))」")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 140)
                .padding()
                .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 20))

            Text(testMode == .multipleChoice ? "正しい答えを選んでください" : "答えを入力してください")
                .foregroundStyle(.secondary)
            if testMode == .multipleChoice && !usesAI && choices.count < 4 {
                Text("異なる答えが少ないため、今回は\(choices.count)択で出題します。AIをオンにすると4択を生成できます。")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if isBusy { ProgressView("AIが処理中…") }
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
                if usesAI && testMode == .multipleChoice {
                    Button("問題作成を再試行") { prepareChoices() }.disabled(isBusy)
                }
            }
            if testMode == .multipleChoice {
                multipleChoiceView(question)
            } else {
                typingAnswerView(question)
            }

            if selectedAnswer != nil {
                if let aiFeedback {
                    Text(aiFeedback).font(.callout)
                    Button(recordedCorrect ? "不正解に訂正" : "正解に訂正") {
                        let corrected = !recordedCorrect
                        if correctRecordedAnswer(corrected, question: question) {
                            self.aiFeedback = corrected ? "正解に訂正しました。" : "不正解に訂正しました。"
                        }
                    }.buttonStyle(.bordered)
                    Text("登録した答えと照合し、必要に応じてAIで判定しています。判定が違う場合は訂正できます。")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Text(question.isMemorized ? "覚えた単語になりました。通常テストから外れ、復習で出題できます。" : "連続正解 \(question.consecutiveTestCorrect) / 3回")
                    .font(.subheadline).foregroundStyle(.secondary)
                if testMode == .typing && aiFeedback == nil {
                    Text(isCorrect(selectedAnswer ?? "", for: question) ? "正解！" : "不正解　正解: \(testDirection.answer(for: question))")
                        .font(.headline)
                        .foregroundStyle(isCorrect(selectedAnswer ?? "", for: question) ? .green : .red)
                }

                Button(questionIndex + 1 == questions.count ? "結果を見る" : "次の問題へ") {
                    nextQuestion()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        }
    }

    private func multipleChoiceView(_ question: Word) -> some View {
        VStack(spacing: 12) {
            ForEach(choices, id: \.self) { choice in
                Button {
                    answer(choice, for: question)
                } label: {
                    HStack {
                        Text(choice)
                            .font(.headline)
                        Spacer()
                        if selectedAnswer == choice {
                            Image(systemName: isCorrect(choice, for: question) ? "checkmark.circle.fill" : "xmark.circle.fill")
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(buttonColor(for: choice, correctAnswer: testDirection.answer(for: question)))
                .disabled(selectedAnswer != nil || isBusy)
            }
        }
    }

    private func typingAnswerView(_ question: Word) -> some View {
        VStack(spacing: 12) {
            TextField("答えを入力", text: $typedAnswer)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
                .disabled(selectedAnswer != nil || isBusy)

            Button("回答する") {
                answer(typedAnswer, for: question)
            }
            .buttonStyle(.bordered)
            .disabled(typedAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedAnswer != nil || isBusy)
        }
    }

    private func buttonColor(for choice: String, correctAnswer: String) -> Color {
        guard let selectedAnswer else { return .blue }
        if AnswerComparison.matches(choice, correctAnswer) { return .green }
        return choice == selectedAnswer ? .red : .blue
    }

    private func startTest() {
        requestID = UUID()
        aiTask?.cancel()
        isBusy = false
        aiQuestion = nil
        aiFeedback = nil
        errorMessage = nil
        let candidates = words.filter { testScope.includes($0) }
        var generator = SystemRandomNumberGenerator()
        questions = WeightedSampling.select(candidates, count: questionLimit, weight: {
            testScope == .review ? 1 : $0.learningProgress.selectionWeight
        }, using: &generator)
        testSessionID = UUID().uuidString
        previousProgress = nil
        questionIndex = 0
        correctAnswers = 0
        selectedAnswer = nil
        typedAnswer = ""
        hasFinished = questions.isEmpty
        prepareChoices()
    }

    private func answer(_ choice: String, for question: Word) {
        guard selectedAnswer == nil && !isBusy else { return }
        errorMessage = nil
        if usesAI && testMode == .typing && isCorrect(choice, for: question) {
            aiFeedback = "正解！ 登録した答えと一致しています。"
            recordAnswer(choice, correct: true, question: question)
            return
        }
        if usesAI && testMode == .typing {
            isBusy = true
            let id = UUID()
            requestID = id
            let prompt = testDirection.prompt(for: question)
            let expected = testDirection.answer(for: question)
            aiTask = Task { @MainActor in
                do {
                    let grade: MeaningGenerator.Grade = try await MeaningGenerator.assist("grade", prompt: prompt, expected: expected, answer: choice)
                    guard !Task.isCancelled && requestID == id else { return }
                    aiFeedback = (grade.correct ? "正解！ " : "不正解。正解: \(expected)\n") + grade.feedback
                    recordAnswer(choice, correct: grade.correct, question: question)
                } catch {
                    guard !Task.isCancelled && requestID == id else { return }
                    errorMessage = error.localizedDescription
                }
                isBusy = false
            }
        } else {
            recordAnswer(choice, correct: isCorrect(choice, for: question), question: question)
        }
    }

    private func recordAnswer(_ choice: String, correct: Bool, question: Word) {
        guard selectedAnswer == nil else { return }
        let previous = question.learningProgress
        question.learningProgress = previous.recording(correct: correct, testID: testSessionID)
        do {
            try modelContext.save()
        } catch {
            question.learningProgress = previous
            aiFeedback = nil
            errorMessage = "回答を保存できませんでした。もう一度回答してください。\(error.localizedDescription)"
            return
        }
        previousProgress = previous
        recordedCorrect = correct
        selectedAnswer = choice
        correctAnswers += correct ? 1 : 0
    }

    private func correctRecordedAnswer(_ correct: Bool, question: Word) -> Bool {
        guard let previousProgress else { return false }
        let saved = question.learningProgress
        question.learningProgress = previousProgress.recording(correct: correct, testID: testSessionID)
        do {
            try modelContext.save()
        } catch {
            question.learningProgress = saved
            errorMessage = "訂正を保存できませんでした。\(error.localizedDescription)"
            return false
        }
        correctAnswers += correct ? 1 : -1
        recordedCorrect = correct
        errorMessage = nil
        return true
    }

    private func nextQuestion() {
        guard !isBusy else { return }
        errorMessage = nil
        if questionIndex + 1 == questions.count {
            if saveResult() { hasFinished = true }
        } else {
            aiQuestion = nil
            aiFeedback = nil
            questionIndex += 1
            selectedAnswer = nil
            previousProgress = nil
            typedAnswer = ""
            prepareChoices()
        }
    }

    private func prepareChoices() {
        guard testMode == .multipleChoice else {
            choices = []
            return
        }

        guard let question = currentQuestion else {
            choices = []
            return
        }

        if usesAI {
            choices = []
            isBusy = true
            errorMessage = nil
            let id = UUID()
            requestID = id
            let prompt = testDirection.prompt(for: question)
            let expected = testDirection.answer(for: question)
            aiTask = Task { @MainActor in
                do {
                    let generated: MeaningGenerator.Question = try await MeaningGenerator.assist("question", prompt: prompt, expected: expected)
                    guard !Task.isCancelled && requestID == id else { return }
                    guard generated.choices.count == 4, generated.choices.contains(expected), AnswerComparison.uniqueChoices(generated.choices).count == 4 else {
                        throw MeaningGenerationError.invalidResponse
                    }
                    aiQuestion = generated.question
                    choices = generated.choices.shuffled()
                } catch {
                    guard !Task.isCancelled && requestID == id else { return }
                    errorMessage = error.localizedDescription
                }
                isBusy = false
            }
            return
        }

        let otherChoices = AnswerComparison.uniqueChoices(words.map { testDirection.answer(for: $0) })
            .filter { !AnswerComparison.matches($0, testDirection.answer(for: question)) }
            .shuffled()
            .prefix(3)

        choices = ([testDirection.answer(for: question)] + otherChoices).shuffled()
    }

    private func isCorrect(_ answer: String, for question: Word) -> Bool {
        AnswerComparison.matches(answer, testDirection.answer(for: question))
    }

    private func saveResult() -> Bool {
        let result = TestResult(
                category: category,
                correctAnswers: correctAnswers,
                totalQuestions: questions.count
        )
        modelContext.insert(result)
        do {
            try modelContext.save()
            return true
        } catch {
            modelContext.delete(result)
            errorMessage = "結果を保存できませんでした。もう一度「結果を見る」を押してください。\(error.localizedDescription)"
            return false
        }
    }
}
