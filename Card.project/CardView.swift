import SwiftUI
import SwiftData

struct CardView: View {
    @Environment(\.modelContext) private var modelContext
    let word: Word
    @State private var isFlipped = false

    @State private var showsExplanation = false

    var body: some View {
        VStack {
        card
        Button { showsExplanation = true } label: {
            Label("AIで解説・例文を見る", systemImage: "sparkles")
        }
        .buttonStyle(.bordered)
        }
        .sheet(isPresented: $showsExplanation) {
            AIExplanationView(prompt: word.frontText, expected: word.backText)
        }
    }

    private var card: some View {
        ZStack {
            // ---------------------------------
            // 表面 (英語)
            // ---------------------------------
            RoundedRectangle(cornerRadius: 24)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)
                .overlay(
                    VStack(spacing: 16) {
                        Image(systemName: "hand.tap.fill")
                            .font(.title)
                            .foregroundColor(.blue.opacity(0.6))
                        
                        Text(word.frontText)
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                        
                        Text("タップして裏面を表示")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                )
                .opacity(isFlipped ? 0 : 1)

            // ---------------------------------
            // 裏面 (日本語)
            // ---------------------------------
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.blue.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Color.blue, lineWidth: 2)
                )
                .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)
                .overlay(
                    VStack(spacing: 16) {
                        Text(word.backText)
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundColor(.blue)

                        Button {
                            word.isMemorized = true
                            try? modelContext.save()
                        } label: {
                            Label("覚えた", systemImage: "checkmark.circle.fill")
                                .font(.headline)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                    }
                )
                // 裏面の文字が鏡文字にならないようにY軸で180度反転
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                .opacity(isFlipped ? 1 : 0)
        }
        .frame(width: 300, height: 420)
        // ---------------------------------
        // 3D回転アニメーション
        // ---------------------------------
        .rotation3DEffect(
            .degrees(isFlipped ? 180 : 0),
            axis: (x: 0, y: 1, z: 0)
        )
        .onTapGesture {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                isFlipped.toggle()
            }
        }
    }
}

struct AIExplanationView: View {
    let prompt: String
    let expected: String
    @Environment(\.dismiss) private var dismiss
    @State private var explanation: MeaningGenerator.Explanation?
    @State private var error: String?
    @State private var attempt = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(prompt).font(.title.bold())
                    if let explanation {
                        Text("解説").font(.headline)
                        Text(explanation.explanation)
                        Text("例文・具体例").font(.headline)
                        Text(explanation.example)
                        Text("覚え方").font(.headline)
                        Text(explanation.hint)
                        Text("AIの説明には誤りが含まれる場合があります。登録した答えと合わせて確認してください。")
                            .font(.caption).foregroundStyle(.secondary)
                    } else if let error {
                        Text(error).foregroundStyle(.red)
                        Button("再試行") { attempt += 1 }
                    } else {
                        ProgressView("AIが解説を作成中…")
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding()
            }
            .navigationTitle("AI学習サポート")
            .toolbar { Button("閉じる") { dismiss() } }
            .task(id: attempt) {
                error = nil
                do {
                    let result: MeaningGenerator.Explanation = try await MeaningGenerator.assist("explain", prompt: prompt, expected: expected)
                    try Task.checkCancellation()
                    explanation = result
                } catch {
                    if !Task.isCancelled { self.error = error.localizedDescription }
                }
            }
        }
    }
}
