import Foundation
import SwiftData
import EventKit

@Observable
final class ToolCallService {
    let locationService = LocationService()
    let webSearchService = WebSearchService()
    let qwenVLService = QwenVLService()
    let metaGlassesService: MetaGlassesService
    var chatMode: ChatMode = .voice
    var lastFrameDescription: String?

    @ObservationIgnored var modelContext: ModelContext?
    @ObservationIgnored private let eventStore = EKEventStore()

    private var remindersAuthorized: Bool {
        EKEventStore.authorizationStatus(for: .reminder) == .fullAccess
    }

    init(metaGlassesService: MetaGlassesService) {
        self.metaGlassesService = metaGlassesService
    }

    private func ensureRemindersAccess() async -> Bool {
        if remindersAuthorized { return true }
        do {
            return try await eventStore.requestFullAccessToReminders()
        } catch {
            print("[ToolCall] Reminders access error: \(error)")
            return false
        }
    }

    // MARK: - Tool Definitions

    static let tools: [DSTool] = [
        DSTool(
            name: "get_current_time",
            description: "获取当前的日期和时间信息。",
            parameters: [
                "type": "object",
                "properties": [:] as [String: Any],
                "required": [] as [String],
            ]
        ),
        DSTool(
            name: "get_current_location",
            description: "获取用户的当前位置信息，包括经纬度和地址。",
            parameters: [
                "type": "object",
                "properties": [:] as [String: Any],
                "required": [] as [String],
            ]
        ),
        DSTool(
            name: "capture_photo",
            description: "从 Meta 眼镜拍摄照片并识别图像内容。用于查看当前场景、识别物体、读取文字、翻译图片中的内容等。当用户想要让你看看周围环境、识别面前的东西、或让你帮忙看什么时，使用此工具。",
            parameters: [
                "type": "object",
                "properties": [:] as [String: Any],
                "required": [] as [String],
            ]
        ),
        DSTool(
            name: "web_search",
            description: "搜索互联网获取最新信息。当用户询问新闻、实时信息、最新动态、或需要查询网络上的内容时使用此工具。",
            parameters: [
                "type": "object",
                "properties": [
                    "query": [
                        "type": "string",
                        "description": "搜索关键词",
                    ] as [String: Any],
                ] as [String: Any],
                "required": ["query"],
            ]
        ),
        DSTool(
            name: "manage_todos",
            description: "管理用户的待办事项列表。可以查看所有待办事项、添加新事项、或完成已有事项。会同步到 iOS 提醒事项。",
            parameters: [
                "type": "object",
                "properties": [
                    "action": [
                        "type": "string",
                        "enum": ["list", "add", "complete"],
                        "description": "操作类型：list 查看全部，add 添加新事项，complete 完成某事项",
                    ] as [String: Any],
                    "title": [
                        "type": "string",
                        "description": "待办事项标题（add 和 complete 时使用）",
                    ] as [String: Any],
                ] as [String: Any],
                "required": ["action"],
            ]
        ),
    ]

    // MARK: - Execute Tool

    func execute(name: String, arguments: String) async -> String {
        let args = parseArgs(arguments)

        switch name {
        case "get_current_time":
            return executeGetCurrentTime()
        case "get_current_location":
            return await executeGetCurrentLocation()
        case "capture_photo":
            return await executeCapturePhoto()
        case "web_search":
            let query = args["query"] as? String ?? ""
            return await executeWebSearch(query: query)
        case "manage_todos":
            let action = args["action"] as? String ?? "list"
            let title = args["title"] as? String
            return await executeManageTodos(action: action, title: title)
        default:
            return "未知工具：\(name)"
        }
    }

    // MARK: - Tool Implementations

    private func executeGetCurrentTime() -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "zh_CN")
        fmt.dateFormat = "yyyy年M月d日 EEEE HH:mm:ss"
        return fmt.string(from: Date())
    }

    private func executeGetCurrentLocation() async -> String {
        do {
            let result = try await locationService.getCurrentLocation()
            return "纬度：\(result.latitude)，经度：\(result.longitude)，地址：\(result.address)"
        } catch {
            return "无法获取位置信息：\(error.localizedDescription)"
        }
    }

    private func executeCapturePhoto() async -> String {
        if chatMode == .visual, let desc = lastFrameDescription {
            return "当前画面识别结果：\(desc)"
        }

        var imageData: Data?

        if metaGlassesService.connectionState == .streaming {
            imageData = metaGlassesService.captureCurrentFrame()
            if imageData == nil {
                imageData = await metaGlassesService.capturePhoto()
            }
        } else {
            imageData = await metaGlassesService.captureHighQualityPhoto()
        }

        guard let imageData else {
            return "无法拍摄照片，Meta 眼镜未连接或无法获取图像"
        }

        do {
            return try await qwenVLService.captureAndAnalyze(imageData: imageData)
        } catch {
            return "图像识别失败：\(error.localizedDescription)"
        }
    }

    private func executeWebSearch(query: String) async -> String {
        guard !query.isEmpty else { return "搜索关键词不能为空" }

        do {
            return try await webSearchService.search(query: query)
        } catch {
            return "搜索失败：\(error.localizedDescription)"
        }
    }

    private func executeManageTodos(action: String, title: String?) async -> String {
        if await ensureRemindersAccess() {
            return await executeWithReminders(action: action, title: title)
        }
        return executeWithSwiftData(action: action, title: title)
    }

    // MARK: - Reminders (EventKit)

    private func executeWithReminders(action: String, title: String?) async -> String {
        let defaultCalendar = eventStore.defaultCalendarForNewReminders()

        switch action {
        case "list":
            return await listReminders()

        case "add":
            guard let title, !title.isEmpty else { return "请提供待办事项标题" }
            guard let calendar = defaultCalendar else { return "无法访问提醒事项" }
            let reminder = EKReminder(eventStore: eventStore)
            reminder.title = title
            reminder.calendar = calendar
            do {
                try eventStore.save(reminder, commit: true)
                syncToSwiftData(title: title, isCompleted: false)
                return "已添加待办事项：\(title)"
            } catch {
                return "添加失败：\(error.localizedDescription)"
            }

        case "complete":
            guard let title, !title.isEmpty else { return "请提供要完成的待办事项标题" }
            return await completeReminder(matching: title)

        default:
            return "未知操作：\(action)"
        }
    }

    private func listReminders() async -> String {
        let predicate = eventStore.predicateForIncompleteReminders(
            withDueDateStarting: nil, ending: nil, calendars: nil
        )

        let reminders = await withCheckedContinuation { (c: CheckedContinuation<[EKReminder], Never>) in
            eventStore.fetchReminders(matching: predicate) { items in
                c.resume(returning: items ?? [])
            }
        }

        if reminders.isEmpty { return "当前没有未完成的待办事项" }

        return reminders.enumerated().map { i, r in
            "\(i + 1). \(r.title ?? "无标题")"
        }.joined(separator: "\n")
    }

    private func completeReminder(matching title: String) async -> String {
        let predicate = eventStore.predicateForIncompleteReminders(
            withDueDateStarting: nil, ending: nil, calendars: nil
        )

        let reminders = await withCheckedContinuation { (c: CheckedContinuation<[EKReminder], Never>) in
            eventStore.fetchReminders(matching: predicate) { items in
                c.resume(returning: items ?? [])
            }
        }

        guard let match = reminders.first(where: { ($0.title ?? "").contains(title) }) else {
            return "未找到匹配的待办事项：\(title)"
        }

        match.isCompleted = true
        do {
            try eventStore.save(match, commit: true)
            completeInSwiftData(matching: title)
            return "已完成待办事项：\(match.title ?? title)"
        } catch {
            return "完成失败：\(error.localizedDescription)"
        }
    }

    // MARK: - SwiftData Fallback

    private func executeWithSwiftData(action: String, title: String?) -> String {
        guard let context = modelContext else { return "待办事项功能暂不可用，请在设置中授权提醒事项权限" }

        switch action {
        case "list":
            let descriptor = FetchDescriptor<TodoItem>(
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
            let items = (try? context.fetch(descriptor)) ?? []
            if items.isEmpty { return "当前没有待办事项" }
            return items.enumerated().map { i, item in
                "\(i + 1). [\(item.isCompleted ? "✓" : " ")] \(item.title)"
            }.joined(separator: "\n")

        case "add":
            guard let title, !title.isEmpty else { return "请提供待办事项标题" }
            let item = TodoItem(title: title)
            context.insert(item)
            try? context.save()
            return "已添加待办事项：\(title)"

        case "complete":
            guard let title, !title.isEmpty else { return "请提供要完成的待办事项标题" }
            let descriptor = FetchDescriptor<TodoItem>()
            let items = (try? context.fetch(descriptor)) ?? []
            if let match = items.first(where: { $0.title.contains(title) }) {
                match.isCompleted = true
                try? context.save()
                return "已完成待办事项：\(match.title)"
            }
            return "未找到匹配的待办事项：\(title)"

        default:
            return "未知操作：\(action)"
        }
    }

    private func syncToSwiftData(title: String, isCompleted: Bool) {
        guard let context = modelContext else { return }
        let item = TodoItem(title: title)
        item.isCompleted = isCompleted
        context.insert(item)
        try? context.save()
    }

    private func completeInSwiftData(matching title: String) {
        guard let context = modelContext else { return }
        let descriptor = FetchDescriptor<TodoItem>()
        let items = (try? context.fetch(descriptor)) ?? []
        if let match = items.first(where: { $0.title.contains(title) }) {
            match.isCompleted = true
            try? context.save()
        }
    }

    // MARK: - Helpers

    private func parseArgs(_ json: String) -> [String: Any] {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return dict
    }
}
