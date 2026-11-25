import Foundation

/// magpie 历史会话记录
struct SessionDTO: Codable, Sendable, Identifiable, Hashable {
    var id: String
    var agent: String
    var name: String?
    var title: String?
    var cost: Double?
    var input: Int?
    var output: Int?
    var last: String?
    /// 官方 Carry：这段会话可以转换成的其他 Agent 会话。
    var carry: [SessionCarryDTO]?

    var displayTitle: String {
        if let title, !title.isEmpty { return title }
        return id
    }

    var displayAgent: String {
        name ?? agent
    }

    var formattedCost: String {
        guard let cost, cost > 0 else { return "$0.00" }
        return String(format: "$%.4f", cost)
    }

    var formattedTokens: String {
        let total = (input ?? 0) + (output ?? 0)
        return UsageDTO.formatTokens(total)
    }
}

/// 会话可以转成的其他 Agent（sessions.Session.Carry）。
struct SessionCarryDTO: Codable, Sendable, Hashable, Identifiable {
    var agent: String
    var command: String?
    /// 是否支持转换（Convert）；缺省按支持处理。
    var convert: Bool?

    var id: String { agent }
}

/// `POST /api/sessions/carry` 的返回。
struct SessionCarryResultDTO: Codable, Sendable {
    var agent: String?
    var id: String?
    var command: String?
}

/// `POST /api/sessions/export` 的返回（服务器 Downloads 里的路径）。
struct SessionExportResultDTO: Codable, Sendable {
    var path: String?
}

/// `GET /api/sessions` 响应体
struct SessionsResponseDTO: Codable, Sendable {
    var sessions: [SessionDTO]
}

/// 会话详细多轮对话记录 (Transcript)
struct TranscriptDTO: Codable, Sendable {
    var parts: [TranscriptPartDTO]
    var cut: Bool?
    var source: String?
}

/// 会话对话中的一个消息片段
struct TranscriptPartDTO: Codable, Sendable, Identifiable {
    var id: UUID = UUID()
    var role: String
    var kind: String
    var name: String?
    var text: String
    var cut: Int?

    enum CodingKeys: String, CodingKey {
        case role, kind, name, text, cut
    }
}

/// `GET /api/sessions/said`：跨全部 Agent 的对话全文检索结果。
struct SessionSaidResponseDTO: Codable, Sendable {
    var hits: [SessionSaidHitDTO]
    var indexed: Int?
    var total: Int?
    var cut: Bool?
    var listing: Bool?

    enum CodingKeys: String, CodingKey { case hits, indexed, total, cut, listing }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.hits = (try? c.decode([SessionSaidHitDTO].self, forKey: .hits)) ?? []
        self.indexed = try? c.decodeIfPresent(Int.self, forKey: .indexed)
        self.total = try? c.decodeIfPresent(Int.self, forKey: .total)
        self.cut = try? c.decodeIfPresent(Bool.self, forKey: .cut)
        self.listing = try? c.decodeIfPresent(Bool.self, forKey: .listing)
    }
}

struct SessionSaidHitDTO: Codable, Sendable, Identifiable, Hashable {
    var agent: String
    var sessionID: String
    var title: String?
    var cwd: String?
    var last: String?
    var wsl: String?
    var transcript: Bool?
    var hit: SessionHitDTO

    var id: String { "\(agent):\(sessionID)" }
    var displayTitle: String { (title?.isEmpty == false) ? title! : sessionID }

    enum CodingKeys: String, CodingKey {
        case agent
        case sessionID = "id"
        case title, cwd, last, wsl, transcript, hit
    }

    func asSessionDTO() -> SessionDTO {
        SessionDTO(id: sessionID, agent: agent, name: nil, title: title, cost: nil, input: nil, output: nil, last: last, carry: nil)
    }
}

struct SessionHitDTO: Codable, Sendable, Hashable {
    var role: String?
    var kind: String?
    var before: String?
    var match: String?
    var after: String?
}
