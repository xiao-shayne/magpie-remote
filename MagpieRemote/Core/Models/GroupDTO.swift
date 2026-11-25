import Foundation

/// 路由组分类器上次失败记录（`classifierFailedJSON`）。
struct GroupClassifierFailedDTO: Codable, Sendable, Hashable {
    var error: String
    var at: String?
}

/// 路由组定义（provider.Group 的 JSON 映射，含官方的会员信息）。
struct GroupDTO: Codable, Sendable, Identifiable, Hashable {
    var id: String
    var ref: String
    var name: String
    var members: [String]?
    var routing: String?
    var affinity: String?
    var classifier: String?
    var rules: JSONValue?
    var pick: String?
    var unlists: Bool?
    var sink: Bool?
    var off: [String]?
    var disabled: Bool?
    var keys: [String]?
    var accounts: [String]?
    var auto: Bool?
    var ready: Bool?
    var holds: [String]?
    var offers: [String]?
    var shared: [String]?
    var picked: String?
    var decides: Bool?
    var memberInfo: [GroupMemberDTO]?
    var patterns: [JSONValue]?
    var routedAt: String?
    var context: Int?
    var classifierFailed: GroupClassifierFailedDTO?

    var isAuto: Bool {
        auto == true || ref.hasPrefix("auto/")
    }

    var memberCount: Int {
        members?.count ?? 0
    }

    var routingDisplayName: String {
        GroupRouting.displayName(routing)
    }

    /// 供编辑页回填：官方的可编辑字段。
    var draft: GroupDraft {
        GroupDraft(
            id: id,
            name: name,
            members: members ?? [],
            routing: routing ?? "smart",
            affinity: affinity ?? "",
            unlists: unlists ?? false,
            sink: sink ?? false,
            keys: keys,
            accounts: accounts,
            classifier: classifier,
            rules: rules
        )
    }
}

/// 编辑草稿。
struct GroupDraft: Sendable, Equatable {
    var id: String
    var name: String
    var members: [String]
    var routing: String
    var affinity: String
    var unlists: Bool
    var sink: Bool
    var keys: [String]? = nil
    var accounts: [String]? = nil
    var classifier: String? = nil
    var rules: JSONValue? = nil
}

/// 组成员（memberInfo）。
struct GroupMemberDTO: Codable, Sendable, Identifiable, Hashable {
    var id: String
    var ready: Bool?
    var provider: String?
    var name: String?
    var icon: String?
    var model: String?
    var on: Int?
    var group: Bool?
    var providerOff: Bool?
    var of: String?
    var effort: String?
    var account: String?
    var billing: String?
    var fast: Bool?
    var canFast: Bool?
    var ultra: Bool?
    var ultraOK: Bool?
    var ownFast: Bool?
    var efforts: [String]?
    var context: Int?
    var images: Bool?
    var free: Bool?

    var isReady: Bool { ready ?? false }

    var displayName: String {
        if group == true { return name ?? id }
        return model ?? of ?? id
    }
}

/// 可加入组的模型条目。
struct GroupModelRefDTO: Codable, Sendable, Identifiable, Hashable {
    var id: String
    var name: String?
    var provider: String?
    var providerName: String?
    var icon: String?
    var context: Int?
    var efforts: [String]?
    var canFast: Bool?
    var ultraOK: Bool?
    var ownFast: Bool?
    var images: Bool?
    var imagesUnknown: Bool?
    var sub: Bool?
    var free: Bool?
    var zero: Bool?

    var displayName: String { name ?? id }
}

/// 多 Key / 多账号池。
struct GroupPoolDTO: Codable, Sendable, Identifiable, Hashable {
    var provider: String
    var name: String
    var icon: String?
    var kind: String?
    var who: [String]?
    var routing: String?
    var affinity: String?
    var sink: Bool?
    var `protocol`: String?

    var id: String { "\(provider)-\(`protocol` ?? kind ?? "")" }
}

/// 自动发现组可跳过的 Provider。
struct GroupSkippableDTO: Codable, Sendable, Identifiable, Hashable {
    var id: String
    var name: String
}

/// 组可绑定的账号 / Key。
struct GroupAccountDTO: Codable, Sendable, Identifiable, Hashable {
    var id: String
    var name: String
    var provider: String
    var providerName: String?
    var account: Bool?
    var key: Bool?
    var plan: String?
}

/// 组的网关 Key 绑定项。
struct GroupGatewayKeyDTO: Codable, Sendable, Identifiable, Hashable {
    var id: String
    var name: String
    var masked: String?
    var off: Bool?
}

/// 官方模板（Add a template）。
struct GroupTemplateDTO: Codable, Sendable, Identifiable, Hashable {
    var kind: String
    var group: GroupTemplateBodyDTO

    var id: String { kind }
}

struct GroupTemplateBodyDTO: Codable, Sendable, Hashable {
    var id: String
    var name: String
    var members: [String]?
    var routing: String?
    var affinity: String?
    var classifier: String?
    var rules: JSONValue?
    var unlists: Bool?
}

/// 每个组的共同默认值。
struct GroupDefaultsDTO: Codable, Sendable, Hashable {
    var sink: Bool? = nil
    var firstToken: Int? = nil
    var patience: Int? = nil
}

struct GroupClockDTO: Codable, Sendable, Hashable {
    var zone: String?
    var offset: Int?
}

/// `GET /api/groups` 响应体。
struct GroupsResponseDTO: Codable, Sendable {
    var groups: [GroupDTO]
    var models: [GroupModelRefDTO]?
    var pools: [GroupPoolDTO]?
    var deciders: [GroupModelRefDTO]?
    var drawers: [GroupModelRefDTO]?
    var found: Bool?
    var skip: [String]?
    var skippable: [GroupSkippableDTO]?
    var templates: [GroupTemplateDTO]?
    var clock: GroupClockDTO?
    var defaults: GroupDefaultsDTO?
    var accounts: [String: [GroupAccountDTO]]?
    var gatewayKeys: [GroupGatewayKeyDTO]?
    var shared: String?
    var imported: GroupImportedDTO?
}

struct GroupImportedDTO: Codable, Sendable, Hashable {
    var group: GroupImportedGroupDTO?
    var missing: [String]?
}

/// 导入结果里的组摘要：字段全部宽松解码，避免未知结构导致整份响应失败。
struct GroupImportedGroupDTO: Codable, Sendable, Hashable {
    var id: String?
    var name: String?
    var members: [String]?
    var routing: String?
    var affinity: String?
    var unlists: Bool?
}

/// `POST /api/groups/save` 的请求体：官方 provider.Group 的扁平结构 + from。
struct GroupSaveRequest: Encodable, Sendable {
    var id: String
    var name: String
    var members: [String]
    var routing: String
    var affinity: String
    var unlists: Bool
    var sink: Bool
    var keys: [String]?
    var accounts: [String]?
    var classifier: String?
    var rules: JSONValue?
    var from: String?

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(members, forKey: .members)
        try c.encode(routing, forKey: .routing)
        try c.encode(affinity, forKey: .affinity)
        try c.encode(unlists, forKey: .unlists)
        try c.encode(sink, forKey: .sink)
        try c.encodeIfPresent(keys, forKey: .keys)
        try c.encodeIfPresent(accounts, forKey: .accounts)
        try c.encodeIfPresent(classifier, forKey: .classifier)
        try c.encodeIfPresent(rules, forKey: .rules)
        try c.encodeIfPresent(from, forKey: .from)
    }

    enum CodingKeys: String, CodingKey {
        case id, name, members, routing, affinity, unlists, sink, keys, accounts
        case classifier, rules, from
    }
}

struct GroupRoutingOption: Identifiable, Hashable, Sendable {
    let id: String
    let label: String
}

/// 官方策略名与说明（对齐 upstream internal/provider/routing.go 与 routing/client.js）。
enum GroupRouting {
    static let editable: [GroupRoutingOption] = [
        GroupRoutingOption(id: "smart", label: String(localized: "额度优先 (Quota first)")),
        GroupRoutingOption(id: "order", label: String(localized: "顺序故障转移 (Order)")),
        GroupRoutingOption(id: "drain", label: String(localized: "逐个用完 (Drain)")),
        GroupRoutingOption(id: "rotate", label: String(localized: "轮询 (Rotate)")),
        GroupRoutingOption(id: "usage", label: String(localized: "用量最少 (Usage)")),
        GroupRoutingOption(id: "pace", label: String(localized: "到期前用完 (Use before expiry)")),
        GroupRoutingOption(id: "weight", label: String(localized: "按权重 (Weight)")),
        GroupRoutingOption(id: "free", label: String(localized: "免费优先 (Free first)")),
        GroupRoutingOption(id: "fast", label: String(localized: "速度优先 (Speed first)")),
        GroupRoutingOption(id: "cheap", label: String(localized: "最低价优先 (Cheapest first)")),
        GroupRoutingOption(id: "expiring", label: String(localized: "免费额度先到期 (Free expiring)")),
        GroupRoutingOption(id: "fit", label: String(localized: "小上下文优先 (Small context first)")),
        GroupRoutingOption(id: "manual", label: String(localized: "手动指定 (Manual)"))
    ]

    /// 供 Gateway Key 覆盖组路由时选择的策略（不含 manual）。
    static let keyOverrides: [GroupRoutingOption] = [
        GroupRoutingOption(id: "", label: String(localized: "跟随路由组默认"))
    ] + editable.filter { $0.id != "manual" }

    static func displayName(_ value: String?) -> String {
        switch value {
        case "", nil, "smart": return String(localized: "额度优先 (Quota first)")
        case "order": return String(localized: "顺序故障转移 (Order)")
        case "drain": return String(localized: "逐个用完 (Drain)")
        case "rotate": return String(localized: "轮询 (Rotate)")
        case "usage": return String(localized: "用量最少 (Usage)")
        case "pace": return String(localized: "到期前用完 (Pace)")
        case "weight": return String(localized: "按权重 (Weight)")
        case "free": return String(localized: "免费优先 (Free)")
        case "fast": return String(localized: "速度优先 (Fast)")
        case "cheap": return String(localized: "最低价优先 (Cheap)")
        case "expiring": return String(localized: "免费额度先到期 (Expiring)")
        case "fit": return String(localized: "小上下文优先 (Small context)")
        case "manual": return String(localized: "手动指定 (Manual)")
        default: return value ?? String(localized: "额度优先")
        }
    }

    static func shortName(_ value: String?) -> String {
        switch value {
        case "", nil, "smart": return String(localized: "额度优先")
        case "order": return String(localized: "顺序")
        case "drain": return String(localized: "逐个用完")
        case "rotate": return String(localized: "轮询")
        case "usage": return String(localized: "用量最少")
        case "pace": return String(localized: "到期前用完")
        case "weight": return String(localized: "权重")
        case "free": return String(localized: "免费优先")
        case "fast": return String(localized: "速度优先")
        case "cheap": return String(localized: "最低价")
        case "expiring": return String(localized: "先用到期免费")
        case "fit": return String(localized: "小上下文优先")
        case "manual": return String(localized: "手动指定")
        default: return value ?? String(localized: "额度优先")
        }
    }

    static func icon(_ value: String?) -> String {
        switch value {
        case "", nil, "smart": return "gauge.with.dots.needle.67percent"
        case "order": return "list.number"
        case "drain": return "battery.25percent"
        case "rotate": return "arrow.triangle.2.circlepath"
        case "usage": return "chart.line.uptrend.xyaxis"
        case "pace": return "metronome"
        case "weight": return "scalemass.fill"
        case "free": return "gift.fill"
        case "fast": return "bolt.fill"
        case "cheap": return "dollarsign.circle.fill"
        case "expiring": return "hourglass"
        case "fit": return "arrow.down.right.and.arrow.up.left"
        case "manual": return "hand.point.up.left.fill"
        default: return "arrow.triangle.branch"
        }
    }

    static func description(_ value: String?) -> String {
        switch value {
        case "", nil, "smart": return String(localized: "额度优先：有余量的账号中额度最先重置的排第一，避免到期前剩余额度作废。")
        case "order": return String(localized: "严格依照成员顺序依次调用，首选节点正常时独占流量，遇 429 或故障时自动故障转移到下一位。")
        case "drain": return String(localized: "先集中消耗同一个账号或 Key 的额度，用尽后再切到下一个。")
        case "rotate": return String(localized: "请求轮流平均分配到组内所有成员节点上，适用于多账号均匀消耗场景。")
        case "usage": return String(localized: "自动跟踪各提供方的累计调用量，优先分发给当前使用量最少的节点。")
        case "pace": return String(localized: "优先选择在重置或到期前每小时剩余额度最多的账号，减少额度闲置。")
        case "weight": return String(localized: "按账号或 Key 设置的权重比例分配请求流量。")
        case "free": return String(localized: "优先把请求发往免费的成员模型或免费额度，全部耗尽后再使用付费节点。")
        case "fast": return String(localized: "优先发给最近首字延迟与输出速度最快的成员。")
        case "cheap": return String(localized: "按当前生效价格选择单价最低的成员模型。")
        case "expiring": return String(localized: "优先消耗即将到期的免费或试用额度账号。")
        case "fit": return String(localized: "小上下文优先：按本次请求体积选择能装下的最小上下文窗口成员，为长对话留出大窗口。")
        case "manual": return String(localized: "始终只走手动选定的那一个成员。")
        default: return String(localized: "默认路由与容灾备份。")
        }
    }
}
