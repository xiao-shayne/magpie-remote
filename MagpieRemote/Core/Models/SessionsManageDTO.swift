import Foundation

/// 官方 Sessions › 管理（`/api/sessions/manage`）的模型。

struct SessionsManageDTO: Codable, Sendable {
    var agents: [SessionManageAgentDTO]?
    var agent: String?
    var sessions: [SessionManageItemDTO]?
    var trash: [SessionTrashDTO]?
    var trashDir: String?
    var home: String?
    var recording: Bool?
    var recorded: Bool?
    var reads: SessionReadsDTO?
    var terminal: Bool?
}

struct SessionManageAgentDTO: Codable, Sendable, Hashable, Identifiable {
    var agent: String?
    var count: Int?
    var deletable: Bool?
    var name: String?
    var icon: String?

    var id: String { agent ?? name ?? "agent" }
    var displayName: String { name ?? agent ?? "Agent" }
}

struct SessionManageItemDTO: Codable, Sendable, Hashable, Identifiable {
    var agent: String?
    var id: String
    var cwd: String?
    var title: String?
    var start: String?
    var last: String?
    var size: Int?
    var messages: Int?
    var files: Int?
    var deletable: Bool?
    var via: String?

    enum CodingKeys: String, CodingKey {
        case agent, id, cwd, title, start, last, size, messages, files, deletable, via
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let s = try? c.decodeIfPresent(String.self, forKey: .id) {
            self.id = s
        } else if let i = try? c.decodeIfPresent(Int.self, forKey: .id) {
            self.id = String(i)
        } else {
            throw DecodingError.keyNotFound(
                CodingKeys.id,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "session id")
            )
        }
        self.agent = try? c.decodeIfPresent(String.self, forKey: .agent)
        self.cwd = try? c.decodeIfPresent(String.self, forKey: .cwd)
        self.title = try? c.decodeIfPresent(String.self, forKey: .title)
        self.start = try? c.decodeIfPresent(String.self, forKey: .start)
        self.last = try? c.decodeIfPresent(String.self, forKey: .last)
        self.size = try? c.decodeIfPresent(Int.self, forKey: .size)
        self.messages = try? c.decodeIfPresent(Int.self, forKey: .messages)
        self.files = try? c.decodeIfPresent(Int.self, forKey: .files)
        self.deletable = try? c.decodeIfPresent(Bool.self, forKey: .deletable)
        self.via = try? c.decodeIfPresent(String.self, forKey: .via)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(agent, forKey: .agent)
        try c.encodeIfPresent(title, forKey: .title)
        try c.encodeIfPresent(last, forKey: .last)
    }
}

/// 回收站里的一条会话：可恢复。
/// 注意 `id` 是会话 id，回收站的唯一键是 `key`（列表里用 `id: \.key`）。
struct SessionTrashDTO: Codable, Sendable, Hashable {
    var key: String
    var agent: String?
    var id: String?
    var title: String?
    var cwd: String?
    var last: String?

    enum CodingKeys: String, CodingKey {
        case key, agent, id, title, cwd, last
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let s = try? c.decodeIfPresent(String.self, forKey: .key) {
            self.key = s
        } else if let i = try? c.decodeIfPresent(Int.self, forKey: .key) {
            self.key = String(i)
        } else {
            throw DecodingError.keyNotFound(
                CodingKeys.key,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "trash key")
            )
        }
        self.agent = try? c.decodeIfPresent(String.self, forKey: .agent)
        self.id = try? c.decodeIfPresent(String.self, forKey: .id)
        self.title = try? c.decodeIfPresent(String.self, forKey: .title)
        self.cwd = try? c.decodeIfPresent(String.self, forKey: .cwd)
        self.last = try? c.decodeIfPresent(String.self, forKey: .last)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(key, forKey: .key)
    }
}

/// 会话读取来源：哪些 Agent 的会话会被读取。
struct SessionReadsDTO: Codable, Sendable, Hashable {
    var asked: Bool?
    var all: Bool?
    var found: [SessionReadSourceDTO]?
}

struct SessionReadSourceDTO: Codable, Sendable, Hashable, Identifiable {
    var agent: String?
    var name: String?
    var icon: String?
    var on: Bool?
    /// 新检测到且尚未单独关闭的 Agent（readAgentJSON.new）。
    var isNew: Bool?

    var id: String { agent ?? name ?? "source" }
    var displayName: String { name ?? agent ?? "Agent" }

    enum CodingKeys: String, CodingKey {
        case agent, name, icon, on
        case isNew = "new"
    }
}
