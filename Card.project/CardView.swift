import SwiftUI
import SwiftData

struct CardView: View {
    @Environment(\.modelContext) private var modelContext
    let word: Word
    @State private var isFlipped = false

    var body: some View {
        ZStack {
            // ---------------------------------
            // 表面 (英語)
            // ---------------------------------
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.white)
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
