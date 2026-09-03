import SwiftUI
import SwiftData

struct StudyView: View {
    @Query private var words: [Word]
    
    var body: some View {
        // ※ ここにあった NavigationStack を削除しました
        VStack {
            if words.isEmpty {
                ContentUnavailableView("単語がありません", systemImage: "book.closed")
            } else {
                TabView {
                    ForEach(words) { word in
                        CardView(word: word)
                            .padding(.vertical, 20)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))
            }
        }
        .navigationTitle("カード学習")
        .navigationBarTitleDisplayMode(.inline)
    }
}
