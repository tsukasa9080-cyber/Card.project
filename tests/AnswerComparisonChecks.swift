import Foundation

@main
struct AnswerComparisonChecks {
    static func main() {
        precondition(AnswerComparison.matches("apple fruit", "Apple fruit"))
        precondition(AnswerComparison.matches(" ＡＰＰＬＥ\u{3000} fruit ", "apple  fruit"))
        precondition(AnswerComparison.matches("apple\nfruit", " apple fruit "))
        precondition(!AnswerComparison.matches("", " "))
        precondition(!AnswerComparison.matches("fruit", "apple fruit"))
        precondition(!AnswerComparison.matches("-1", "1"))
        precondition(!AnswerComparison.matches("cafe", "café"))
        precondition(AnswerComparison.uniqueChoices(["Apple", "apple", "ＡＰＰＬＥ", "book", " book ", " ", "cat"]) == ["Apple", "book", "cat"])
        print("Answer comparison checks passed (8 cases)")
    }
}
