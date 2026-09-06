import Foundation

enum MeaningGenerationError: LocalizedError {
    case missingServerURL
    case invalidServerURL
    case invalidResponse
    case requestFailed(String)
    case emptyResult

    var errorDescription: String? {
        switch self {
        case .missingServerURL:
            return "生成AIサーバーURLが設定されていません。メニューからサーバーURLを設定してください。"
        case .invalidServerURL:
            return "生成AIサーバーURLが正しくありません。"
        case .invalidResponse:
            return "生成AIサーバーの応答を読み取れませんでした。"
        case .requestFailed(let message):
            return message
        case .emptyResult:
            return "意味を生成できませんでした。"
        }
    }
}

struct MeaningGenerator {
    private struct ServerResponse: Decodable {
        let meaning: String?
        let error: String?
    }

    static func generateMeaning(for term: String) async throws -> String {
        let trimmedTerm = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTerm.isEmpty else { return "" }
        guard let endpoint else { throw MeaningGenerationError.missingServerURL }

        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 100
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "term": trimmedTerm
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MeaningGenerationError.invalidResponse
        }

        let decodedResponse = try? JSONDecoder().decode(ServerResponse.self, from: data)
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = decodedResponse?.error ?? "生成AIサーバーでエラーが発生しました。"
            throw MeaningGenerationError.requestFailed(message)
        }

        let content = decodedResponse?.meaning?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !content.isEmpty else { throw MeaningGenerationError.emptyResult }
        return content
    }

    struct Explanation: Decodable {
        let explanation: String
        let example: String
        let hint: String
    }
    struct Question: Decodable {
        let question: String
        let choices: [String]
    }
    struct Grade: Decodable {
        let correct: Bool
        let feedback: String
    }

    static func assist<T: Decodable>(_ action: String, prompt: String, expected: String, answer: String? = nil) async throws -> T {
        guard let endpoint else { throw MeaningGenerationError.missingServerURL }
        let url = endpoint.deletingLastPathComponent().appending(path: "ai/" + action)
        var request = URLRequest(url: url)
        request.timeoutInterval = 100
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body = ["prompt": prompt, "expected": expected]
        if let answer { body["answer"] = answer }
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw MeaningGenerationError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else {
            let error = try? JSONDecoder().decode(ServerResponse.self, from: data)
            throw MeaningGenerationError.requestFailed(error?.error ?? "AIとの通信に失敗しました。")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static var endpoint: URL? {
        let storedURL = UserDefaults.standard.string(forKey: "meaningServerURL")
        let infoPlistURL = Bundle.main.object(forInfoDictionaryKey: "MeaningServerURL") as? String
        let environmentURL = ProcessInfo.processInfo.environment["MEANING_SERVER_URL"]

        guard let baseURLString = [storedURL, infoPlistURL, environmentURL]
            .compactMap({ $0?.trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { !$0.isEmpty }) else {
            return nil
        }

        guard let baseURL = URL(string: baseURLString) else {
            return nil
        }

        return baseURL.appending(path: "generate-meaning")
    }
}
