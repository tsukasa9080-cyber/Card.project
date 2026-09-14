import Foundation

struct LearningProgress: Equatable {
    var attempts = 0
    var correctAnswers = 0
    var consecutiveCorrect = 0
    var lastTestID = ""
    var isMemorized = false
    var isDifficult = false

    var correctRate: Double {
        attempts > 0 ? Double(correctAnswers) / Double(attempts) : 0
    }

    // 最初の3回答は同じ重み。その後は正答率0%で4、100%で1。
    var selectionWeight: Double {
        attempts < 3 ? 1 : 1 + 3 * (1 - min(1, max(0, correctRate)))
    }

    func recording(correct: Bool, testID: String) -> Self {
        guard lastTestID != testID else { return self }
        var next = self
        next.attempts += 1
        next.correctAnswers += correct ? 1 : 0
        next.consecutiveCorrect = correct ? min(3, consecutiveCorrect + 1) : 0
        next.lastTestID = testID
        if !correct {
            next.isMemorized = false
            next.isDifficult = true
        } else if next.consecutiveCorrect >= 3 {
            next.isMemorized = true
            next.isDifficult = false
        }
        return next
    }
}

enum WeightedSampling {
    static func select<T, R: RandomNumberGenerator>(
        _ candidates: [T], count: Int, weight: (T) -> Double, using generator: inout R
    ) -> [T] {
        var remaining = candidates
        var selected: [T] = []
        for _ in 0..<min(max(0, count), remaining.count) {
            let weights = remaining.map { max(0.001, weight($0)) }
            let total = weights.reduce(0, +)
            var value = Double.random(in: 0..<total, using: &generator)
            var chosen = remaining.count - 1
            for index in remaining.indices {
                value -= weights[index]
                if value < 0 {
                    chosen = index
                    break
                }
            }
            selected.append(remaining.remove(at: chosen))
        }
        return selected
    }
}
