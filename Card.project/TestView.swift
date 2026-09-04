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

struct TestView: View {
    @Environment(\.modelContext) private var modelContext
    let category: String
    let testMode: TestMode
    let testDirection: TestDirection
    @Query private var words: [Word]

    @State private var questions: [Word] = []
    @State private var choices: [String] = []
    @State private var questionIndex = 0
    @State private var correctAnswers = 0
    @State private var selectedAnswer: String?
    @State private var typedAnswer = ""
    @State private var hasFinished = false

    init(category: String, testMode: TestMode, testDirection: TestDirection) {
        self.category = category
        self.testMode = testMode
        self.testDirection = testDirection
        _words = Query(
            filter: #Predicate<Word> { word in
                word.category == category
            },
            sort: \Word.english
        )
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
        .navigationTitle("\(category)・\(testDirection.rawValue)テスト")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if questions.isEmpty {
                startTest()
            }
        }
    }

    private var resultView: some View {
        VStack(spacing: 24) {
            Image(systemName: correctAnswers == questions.count ? "trophy.fill" : "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundStyle(.yellow)

            Text("テスト完了！")
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
        VStack(spacing: 24) {
            ProgressView(value: Double(questionIndex + 1), total: Double(questions.count))
                .tint(.blue)

            Text("第\(questionIndex + 1)問 / \(questions.count)問")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("「\(testDirection.prompt(for: question))」")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 140)
                .padding()
                .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 20))

            Text(testMode == .multipleChoice ? "正しい答えを選んでください" : "答えを入力してください")
                .foregroundStyle(.secondary)

            if testMode == .multipleChoice {
                multipleChoiceView(question)
            } else {
                typingAnswerView(question)
            }

            if selectedAnswer != nil {
                if testMode == .typing {
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
                .disabled(selectedAnswer != nil)
            }
        }
    }

    private func typingAnswerView(_ question: Word) -> some View {
        VStack(spacing: 12) {
            TextField("答えを入力", text: $typedAnswer)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
                .disabled(selectedAnswer != nil)

            Button("回答する") {
                answer(typedAnswer, for: question)
            }
            .buttonStyle(.bordered)
            .disabled(typedAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedAnswer != nil)
        }
    }

    private func buttonColor(for choice: String, correctAnswer: String) -> Color {
        guard let selectedAnswer else { return .blue }
        if choice == correctAnswer { return .green }
        return choice == selectedAnswer ? .red : .blue
    }

    private func startTest() {
        questions = words.shuffled()
        questionIndex = 0
        correctAnswers = 0
        selectedAnswer = nil
        typedAnswer = ""
        hasFinished = questions.isEmpty
        prepareChoices()
    }

    private func answer(_ choice: String, for question: Word) {
        selectedAnswer = choice
        if isCorrect(choice, for: question) {
            correctAnswers += 1
        } else {
            question.isDifficult = true
            try? modelContext.save()
        }
    }

    private func nextQuestion() {
        if questionIndex + 1 == questions.count {
            saveResult()
            hasFinished = true
        } else {
            questionIndex += 1
            selectedAnswer = nil
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

        let otherChoices = words
            .filter { testDirection.answer(for: $0) != testDirection.answer(for: question) }
            .map { testDirection.answer(for: $0) }
            .shuffled()
            .prefix(3)

        choices = ([testDirection.answer(for: question)] + otherChoices).shuffled()
    }

    private func isCorrect(_ answer: String, for question: Word) -> Bool {
        answer.trimmingCharacters(in: .whitespacesAndNewlines)
            .localizedCaseInsensitiveCompare(testDirection.answer(for: question)) == .orderedSame
    }

    private func saveResult() {
        modelContext.insert(
            TestResult(
                category: category,
                correctAnswers: correctAnswers,
                totalQuestions: questions.count
            )
        )
        try? modelContext.save()
    }
}
