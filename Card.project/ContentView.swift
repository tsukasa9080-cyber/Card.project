import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Word.english) private var words: [Word]

    @State private var newEnglish = ""
    @State private var newJapanese = ""

    var body: some View {
        NavigationStack { // ← 全体を1つの NavigationStack で囲む
            VStack(spacing: 0) {
                // 1. カード学習への遷移ボタン
                NavigationLink(destination: StudyView()) {
                    HStack {
                        Image(systemName: "rectangle.portrait.on.rectangle.portrait.angled.fill")
                            .font(.title2)
                        Text("カード学習を始める (\(words.count)語)")
                            .font(.headline)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(words.isEmpty ? Color.gray : Color.blue)
                    .cornerRadius(12)
                }
                .disabled(words.isEmpty) // 単語が0件なら押せない
                .padding()

                Divider()

                // 2. 単語追加フォーム
                HStack {
                    TextField("単語", text: $newEnglish)
                        .textFieldStyle(.roundedBorder)
                    TextField("意味", text: $newJapanese)
                        .textFieldStyle(.roundedBorder)
                    Button("追加") {
                        addWord()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()

                // 3. 単語リスト
                List {
                    ForEach(words) { word in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(word.english)
                                    .font(.headline)
                                Text(word.japanese)
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                    .onDelete(perform: deleteWords)
                }
            }
            .navigationTitle("単語帳")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                }
            }
        }
    }

    private func addWord() {
        // 空文字チェック（前後スペースを除外）
        let trimmedEnglish = newEnglish.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedJapanese = newJapanese.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmedEnglish.isEmpty, !trimmedJapanese.isEmpty else { return }
        
        withAnimation {
            // 新しいWordモデルの作成
            let newWord = Word(english: trimmedEnglish, japanese: trimmedJapanese)
            
            // データベースに挿入
            modelContext.insert(newWord)
            
            // 明示的に保存を実行
            try? modelContext.save()
            
            // 入力フォームの初期化
            newEnglish = ""
            newJapanese = ""
        }
    }

    private func deleteWords(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(words[index])
            }
        }
    }
}
