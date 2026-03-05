import Foundation

@Observable
final class WebSearchService {
    private let baseURL = "https://open.bigmodel.cn/api/paas/v4/web_search"

    func search(query: String, count: Int = 10) async throws -> String {
        let body: [String: Any] = [
            "search_query": query,
            "search_engine": "search_pro_sogou",
            "search_intent": false,
            "count": count,
            "content_size": "medium",
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: body)

        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(APIKeys.zhipuAI)", forHTTPHeaderField: "Authorization")
        request.httpBody = jsonData
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw WebSearchError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = json["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw WebSearchError.apiError(message)
            }
            throw WebSearchError.httpError(httpResponse.statusCode)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["search_result"] as? [[String: Any]],
              !results.isEmpty
        else {
            throw WebSearchError.noResults
        }

        return formatResults(results)
    }

    private func formatResults(_ results: [[String: Any]]) -> String {
        var lines = ["搜索结果："]

        for (i, result) in results.prefix(10).enumerated() {
            let title = result["title"] as? String ?? ""
            let content = result["content"] as? String ?? ""
            let media = result["media"] as? String
            let date = result["publish_date"] as? String

            var entry = "\(i + 1). 【\(title)】\n   \(content)"
            if let media, !media.isEmpty {
                entry += "\n   来源: \(media)"
            }
            if let date, !date.isEmpty {
                entry += " | \(date)"
            }
            lines.append(entry)
        }

        return lines.joined(separator: "\n\n")
    }
}

enum WebSearchError: LocalizedError {
    case invalidResponse
    case httpError(Int)
    case apiError(String)
    case noResults

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "搜索服务响应无效"
        case .httpError(let code): return "搜索请求失败 (HTTP \(code))"
        case .apiError(let msg): return "搜索服务错误: \(msg)"
        case .noResults: return "未找到相关搜索结果"
        }
    }
}
