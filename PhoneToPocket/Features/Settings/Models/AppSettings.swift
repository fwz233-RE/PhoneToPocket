import Foundation

@Observable
final class AppSettings {
    static let shared = AppSettings()

    var systemPrompt: String {
        didSet { UserDefaults.standard.set(systemPrompt, forKey: "systemPrompt") }
    }

    var ttsVoice: String {
        didSet { UserDefaults.standard.set(ttsVoice, forKey: "ttsVoice") }
    }

    var metaStreamQuality: String {
        didSet { UserDefaults.standard.set(metaStreamQuality, forKey: "metaStreamQuality") }
    }

    var silenceTimeout: Double {
        didSet { UserDefaults.standard.set(silenceTimeout, forKey: "silenceTimeout") }
    }

    private init() {
        systemPrompt = UserDefaults.standard.string(forKey: "systemPrompt") ?? Self.defaultSystemPrompt
        ttsVoice = UserDefaults.standard.string(forKey: "ttsVoice") ?? "Cherry"
        metaStreamQuality = UserDefaults.standard.string(forKey: "metaStreamQuality") ?? "中画质"
        let t = UserDefaults.standard.double(forKey: "silenceTimeout")
        silenceTimeout = t > 0 ? t : 1.5
    }

    static let defaultSystemPrompt = """
        你是一个智能助手，可以帮助用户完成各种任务。
        你可以使用以下工具：
        - get_current_time: 获取当前日期和时间
        - get_current_location: 获取用户当前位置
        - capture_photo: 通过眼镜拍照并识别图像内容
        - web_search: 搜索互联网获取最新信息、新闻、实时数据
        - manage_todos: 管理待办事项（查看、添加、完成）
        当用户的问题涉及实时信息、天气、新闻、位置、待办事项等，你必须主动调用对应工具获取真实数据，不要凭空编造。
        回答要求：
        1. 用简洁的话回答问题
        2. 不要使用 * 、- 、# 等 Markdown 符号
        3. 不要使用表情符号 emoji
        4. 不要使用英文缩写，用中文表达
        5. 数字和单位之间加空格，如：5 度、10 公里
        """

    static let voicePromptSuffix = """

        语音回答要求（非常重要）：
        1. 用几句简洁的话直接回答问题
        2. 禁止使用任何 Markdown 符号，包括：* - # ` > 等
        3. 禁止使用表情符号 emoji
        4. 禁止使用英文缩写，全部用中文表达
        5. 数字和单位之间加空格，如：5 度、10 公里
        6. 不要分条列举，用流畅的句子表达
        7. 适合语音朗读，避免复杂的格式
        """

    static let forcePrompt = "\n请根据需要调用工具获取真实数据，简洁回答。"

    static let voiceOptions: [(id: String, name: String, desc: String)] = [
        ("Cherry", "芊悦", "阳光积极、亲切自然小姐姐"),
        ("Ethan", "晨煦", "阳光、温暖、活力、朝气"),
        ("Nofish", "不吃鱼", "不会翘舌音的设计师"),
        ("Jennifer", "詹妮弗", "品牌级、电影质感般美语女声"),
        ("Ryan", "甜茶", "节奏拉满，戏感炸裂"),
        ("Katerina", "卡捷琳娜", "御姐音色，韵律回味十足"),
        ("Elias", "墨讲师", "学科严谨，知识转化"),
        ("Jada", "上海-阿珍", "风风火火的沪上阿姐"),
        ("Dylan", "北京-晓东", "北京胡同里长大的少年"),
        ("Sunny", "四川-晴儿", "甜到你心里的川妹子"),
        ("Li", "南京-老李", "耐心的瑜伽老师"),
        ("Marcus", "陕西-秦川", "面宽话短，老陕的味道"),
        ("Roy", "闽南-阿杰", "诙谐直爽的台湾哥仔"),
        ("Peter", "天津-李彼得", "天津相声，专业捧哏"),
        ("Rocky", "粤语-阿强", "幽默风趣，在线陪聊"),
        ("Kiki", "粤语-阿清", "甜美的港妹闺蜜"),
        ("Eric", "四川-程川", "跳脱市井的成都男子"),
    ]
}
