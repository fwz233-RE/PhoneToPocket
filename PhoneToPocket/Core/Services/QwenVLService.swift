import Foundation
#if os(iOS)
import UIKit
#endif

@Observable
final class QwenVLService {
    private let baseURL = "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
    private let model = "qwen3-vl-flash"

    func analyzeImage(imageData: Data, prompt: String) async throws -> String {
        let base64 = imageData.base64EncodedString()
        let dataURI = "data:image/jpeg;base64,\(base64)"

        let body: [String: Any] = [
            "model": model,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        ["type": "image_url", "image_url": ["url": dataURI]],
                        ["type": "text", "text": prompt],
                    ] as [[String: Any]],
                ] as [String: Any],
            ],
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: body)

        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(APIKeys.dashScope)", forHTTPHeaderField: "Authorization")
        request.httpBody = jsonData
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200
        else { throw QwenVLError.httpError }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String
        else { throw QwenVLError.parseError }

        return content
    }

    func captureAndAnalyze(imageData: Data) async throws -> String {
        let prompt = """
            请仔细分析这张图片，回答以下问题：
            1. 图片的主要内容是什么？请详细描述。
            2. 图片中是否包含需要完成的任务或待办事项？
               例如：会议安排、作业截止日期、购物清单、预约提醒、需要回复的消息等。
               如果有，请提取具体内容。
            请用 JSON 格式回答，确保 JSON 格式正确：
            ```json
            {
                "description": "图片详细描述",
                "hasTodo": true或false,
                "todoContent": "待办事项内容或null"
            }
            ```
            """
        return try await analyzeImage(imageData: imageData, prompt: prompt)
    }
}

enum QwenVLError: LocalizedError {
    case httpError, parseError

    var errorDescription: String? {
        switch self {
        case .httpError: return "Qwen VL API 请求失败"
        case .parseError: return "Qwen VL 响应解析失败"
        }
    }
}
