import Foundation

enum StreamDelta: Sendable {
    case reasoning(String)
    case text(String)
    case toolCall(ToolCallDelta)
    case done
}

struct ToolCallDelta: Sendable {
    var index: Int
    var id: String
    var name: String
    var arguments: String

    func toDSToolCall() -> DSToolCall {
        DSToolCall(id: id, type: "function", function: DSFunctionCall(name: name, arguments: arguments))
    }
}

struct DSMessage: Sendable {
    let role: String
    let content: String?
    let toolCallId: String?
    let name: String?
    let toolCalls: [DSToolCall]?

    init(role: String, content: String?, toolCallId: String? = nil, name: String? = nil, toolCalls: [DSToolCall]? = nil) {
        self.role = role
        self.content = content
        self.toolCallId = toolCallId
        self.name = name
        self.toolCalls = toolCalls
    }

    nonisolated func toDict() -> [String: Any] {
        var dict: [String: Any] = ["role": role]
        if let content {
            dict["content"] = content
        } else {
            dict["content"] = NSNull()
        }
        if let toolCallId { dict["tool_call_id"] = toolCallId }
        if let name { dict["name"] = name }
        if let toolCalls, !toolCalls.isEmpty {
            dict["tool_calls"] = toolCalls.map { $0.toDict() }
        }
        return dict
    }
}

struct DSToolCall: Sendable, Codable {
    let id: String
    let type: String
    let function: DSFunctionCall

    nonisolated func toDict() -> [String: Any] {
        [
            "id": id,
            "type": type,
            "function": function.toDict(),
        ]
    }
}

struct DSFunctionCall: Sendable, Codable {
    let name: String
    let arguments: String

    nonisolated func toDict() -> [String: Any] {
        ["name": name, "arguments": arguments]
    }
}

struct DSTool: Sendable {
    let name: String
    let description: String
    nonisolated(unsafe) let parameters: [String: Any]

    nonisolated func toDict() -> [String: Any] {
        [
            "type": "function",
            "function": [
                "name": name,
                "description": description,
                "parameters": parameters,
            ] as [String: Any],
        ]
    }
}

@Observable
final class DeepSeekService {
    private let baseURL = "https://api.deepseek.com/chat/completions"

    func streamChat(
        messages: [DSMessage],
        tools: [DSTool]? = nil,
        model: String = "deepseek-chat"
    ) -> AsyncThrowingStream<StreamDelta, Error> {
        let apiKey = APIKeys.deepSeek
        let endpoint = baseURL

        return AsyncThrowingStream { continuation in
            let task = Task.detached {
                var body: [String: Any] = [
                    "model": model,
                    "messages": messages.map { $0.toDict() },
                    "stream": true,
                ]

                if let tools, !tools.isEmpty {
                    body["tools"] = tools.map { $0.toDict() }
                }

                let jsonData = try JSONSerialization.data(withJSONObject: body)

                var request = URLRequest(url: URL(string: endpoint)!)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                request.httpBody = jsonData

                let (bytes, response) = try await URLSession.shared.bytes(for: request)

                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200
                else {
                    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                    continuation.finish(throwing: DeepSeekError.httpError(statusCode: statusCode))
                    return
                }

                var toolCalls: [Int: ToolCallDelta] = [:]

                for try await line in bytes.lines {
                    guard line.hasPrefix("data: ") else { continue }
                    let payload = String(line.dropFirst(6))

                    if payload == "[DONE]" {
                        if !toolCalls.isEmpty {
                            for key in toolCalls.keys.sorted() {
                                if let tc = toolCalls[key] {
                                    continuation.yield(.toolCall(tc))
                                }
                            }
                        }
                        continuation.yield(.done)
                        break
                    }

                    guard let data = payload.data(using: .utf8),
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let choices = json["choices"] as? [[String: Any]],
                          let delta = choices.first?["delta"] as? [String: Any]
                    else { continue }

                    if let reasoning = delta["reasoning_content"] as? String, !reasoning.isEmpty {
                        continuation.yield(.reasoning(reasoning))
                    }

                    if let content = delta["content"] as? String, !content.isEmpty {
                        continuation.yield(.text(content))
                    }

                    if let tcs = delta["tool_calls"] as? [[String: Any]] {
                        for tc in tcs {
                            let idx = tc["index"] as? Int ?? 0
                            let fn = tc["function"] as? [String: Any] ?? [:]

                            if let id = tc["id"] as? String {
                                toolCalls[idx] = ToolCallDelta(
                                    index: idx,
                                    id: id,
                                    name: fn["name"] as? String ?? "",
                                    arguments: fn["arguments"] as? String ?? ""
                                )
                            } else if var existing = toolCalls[idx] {
                                existing.arguments += fn["arguments"] as? String ?? ""
                                if let name = fn["name"] as? String, !name.isEmpty {
                                    existing.name = name
                                }
                                toolCalls[idx] = existing
                            }
                        }
                    }
                }

                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}

enum DeepSeekError: LocalizedError {
    case httpError(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .httpError(let code):
            return "DeepSeek API 请求失败 (HTTP \(code))"
        }
    }
}
