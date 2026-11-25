import Foundation

/// magpie 插件系统响应体 (`GET /api/plugins`)
struct PluginsResponseDTO: Codable, Sendable {
    var plugins: [PluginEntryDTO]
    var bun: Bool?
    var bunVersion: String?
    var mirror: Bool?
    var picker: Bool?
    var registry: PluginRegistryDTO?
    var leftovers: [PluginLeftoverDTO]?
    var error: String?

    init(
        plugins: [PluginEntryDTO] = [],
        bun: Bool? = nil,
        bunVersion: String? = nil,
        mirror: Bool? = nil,
        picker: Bool? = nil,
        registry: PluginRegistryDTO? = nil,
        leftovers: [PluginLeftoverDTO]? = nil,
        error: String? = nil
    ) {
        self.plugins = plugins
        self.bun = bun
        self.bunVersion = bunVersion
        self.mirror = mirror
        self.picker = picker
        self.registry = registry
        self.leftovers = leftovers
        self.error = error
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.plugins = (try? container.decode([PluginEntryDTO].self, forKey: .plugins)) ?? []
        self.bun = try? container.decodeIfPresent(Bool.self, forKey: .bun)
        self.bunVersion = try? container.decodeIfPresent(String.self, forKey: .bunVersion)
        self.mirror = try? container.decodeIfPresent(Bool.self, forKey: .mirror)
        self.picker = try? container.decodeIfPresent(Bool.self, forKey: .picker)
        self.registry = try? container.decodeIfPresent(PluginRegistryDTO.self, forKey: .registry)
        self.leftovers = try? container.decodeIfPresent([PluginLeftoverDTO].self, forKey: .leftovers)
        self.error = try? container.decodeIfPresent(String.self, forKey: .error)
    }

    enum CodingKeys: String, CodingKey {
        case plugins, bun, bunVersion, mirror, picker, registry, leftovers, error
    }
}

/// 残留的未注册依赖包（`plugin.Leftover`）：曾安装失败残留，可通过 `/api/plugins/leftover` 清理。
struct PluginLeftoverDTO: Codable, Sendable, Identifiable, Hashable {
    var name: String
    var spec: String
    var version: String?
    var missing: Bool?

    var id: String { spec.isEmpty ? name : spec }
}

/// npm registry 的来源（`plugin.RegistryInUse`）。
struct PluginRegistryDTO: Codable, Sendable, Hashable {
    var url: String?
    var from: String?
    var envVar: String?
    var path: String?

    enum CodingKeys: String, CodingKey {
        case url, from
        case envVar = "var"
        case path
    }
}

/// 单个扩展插件条目
struct PluginEntryDTO: Codable, Sendable, Identifiable, Hashable {
    var id: String { spec }
    var spec: String
    var name: String?
    var ownName: String?
    var version: String?
    var latest: String?
    var icon: String?
    var error: String?
    var off: Bool?
    var providers: [String]?
    var tools: [PluginToolDTO]?
    var isGateway: Bool?
    var isMiddleware: Bool?
    var isAgent: Bool?
    var packageName: String?
    var serves: [String]?
    var moved: [String]?
    var commit: String?
    var head: String?
    var named: Bool?
    var gatewayOnly: Bool?
    var middlewareOnly: Bool?
    var inMagpieOnly: Bool?
    /// 插件的运行选项（`/api/plugins/options`）。
    var options: JSONValue?
    /// 其包建议的示例选项。
    var optionsExample: JSONValue?

    /// 有可编辑选项（非 middleware/gateway 且已有 options 或示例）。
    var hasEditableOptions: Bool {
        !(isMiddleware ?? false) && !(isGateway ?? false) && (options != nil || optionsExample != nil)
    }

    var displayName: String {
        if let ownName, !ownName.isEmpty { return ownName }
        if let name, !name.isEmpty { return name }
        return spec
    }

    var isOff: Bool { off ?? false }

    /// 是否有可用更新（npm 或 git commit）。
    var hasUpdate: Bool {
        if let version, let latest, !latest.isEmpty, latest != version { return true }
        if let commit, let head, !head.isEmpty, commit != head { return true }
        return false
    }

    enum CodingKeys: String, CodingKey {
        case spec, name, ownName, version, latest, icon, error, off, providers, tools
        case isGateway, isMiddleware, isAgent, packageName = "package", serves, moved, commit, head, named
        case gatewayOnly, middlewareOnly, inMagpieOnly
        case options, optionsExample
    }
}

/// 插件所暴露的 MCP 工具定义
struct PluginToolDTO: Codable, Sendable, Identifiable, Hashable {
    var id: String { name }
    var name: String
    var description: String?
    var mcp: String?
}

// MARK: - 插件商店
/// `GET /api/plugins/market`：推荐插件 + 已安装状态。
struct PluginMarketResponseDTO: Codable, Sendable {
    var listings: [PluginListingDTO]
    var state: PluginsResponseDTO?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.listings = (try? c.decode([PluginListingDTO].self, forKey: .listings)) ?? []
        self.state = try? c.decodeIfPresent(PluginsResponseDTO.self, forKey: .state)
    }

    enum CodingKeys: String, CodingKey { case listings, state }
}

/// `GET /api/plugins/listings`。
struct PluginListingsResponseDTO: Codable, Sendable {
    var listings: [PluginListingDTO]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.listings = (try? c.decode([PluginListingDTO].self, forKey: .listings)) ?? []
    }

    enum CodingKeys: String, CodingKey { case listings }
}

/// 市场推荐的一个插件（plugin.Listing + npm 信息）。
struct PluginListingDTO: Codable, Sendable, Identifiable {
    var packageName: String
    var name: String
    var icon: String?
    var providers: [String]?
    var community: Bool?
    var replaces: String?
    var kind: String?
    var summary: [String: String]?
    var npm: PluginNPMDTO?

    var id: String { packageName }

    var displayName: String { name.isEmpty ? packageName : name }

    var summaryText: String {
        if let zh = summary?["zh"], !zh.isEmpty { return zh }
        if let en = summary?["en"], !en.isEmpty { return en }
        if let description = npm?.description, !description.isEmpty { return description }
        return ""
    }

    var kindLabel: String? {
        switch kind {
        case "middleware": return String(localized: "网关中间件")
        case "agent": return String(localized: "Agent")
        case "tools": return String(localized: "工具")
        case "page": return String(localized: "页面")
        default: return nil
        }
    }

    enum CodingKeys: String, CodingKey {
        case packageName = "package", name, icon, providers, community, replaces, kind, summary, npm
    }
}

/// npm 对一个包的描述（plugin.NPM）。
struct PluginNPMDTO: Codable, Sendable, Hashable {
    var version: String?
    var description: String?
    var publisher: String?
    var license: String?
    var homepage: String?
    var repository: String?
    var weekly: Int?
    var icon: String?
}

// MARK: - npm 搜索
/// `GET /api/plugins/search?q=`：npm 上匹配的插件包。
struct PluginSearchResponseDTO: Codable, Sendable {
    var hits: [PluginSearchHitDTO]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.hits = (try? c.decode([PluginSearchHitDTO].self, forKey: .hits)) ?? []
    }

    enum CodingKeys: String, CodingKey { case hits }
}

struct PluginSearchHitDTO: Codable, Sendable, Identifiable {
    var packageName: String
    var version: String?
    var description: String?
    var publisher: String?
    var license: String?
    var homepage: String?
    var repository: String?
    var weekly: Int?
    var icon: String?

    var id: String { packageName }

    enum CodingKeys: String, CodingKey {
        case packageName = "package", version, description, publisher, license, homepage, repository, weekly, icon
    }
}

// MARK: - 插件更新
/// `GET /api/plugins/updates`。
struct PluginUpdatesDTO: Codable, Sendable {
    var checked: String?
    var waiting: [PluginWaitingDTO]?
    var updated: [PluginUpdatedDTO]?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.checked = try? c.decodeIfPresent(String.self, forKey: .checked)
        self.waiting = try? c.decodeIfPresent([PluginWaitingDTO].self, forKey: .waiting)
        self.updated = try? c.decodeIfPresent([PluginUpdatedDTO].self, forKey: .updated)
    }

    enum CodingKeys: String, CodingKey { case checked, waiting, updated }
}

struct PluginWaitingDTO: Codable, Sendable, Identifiable, Hashable {
    var spec: String
    var packageName: String
    var version: String?
    var latest: String?
    var git: Bool?

    var id: String { spec }

    enum CodingKeys: String, CodingKey {
        case spec, packageName = "package", version, latest, git
    }
}

struct PluginUpdatedDTO: Codable, Sendable, Identifiable, Hashable {
    var packageName: String
    var from: String?
    var to: String?
    var at: String?

    var id: String { packageName + (at ?? "") }

    enum CodingKeys: String, CodingKey {
        case packageName = "package", from, to, at
    }
}

/// `POST /api/plugins/check` 的回答。
struct PluginCheckResponseDTO: Codable, Sendable {
    var at: String?
    var plugins: PluginUpdatesDTO?
    var state: PluginsResponseDTO?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.at = try? c.decodeIfPresent(String.self, forKey: .at)
        self.plugins = try? c.decodeIfPresent(PluginUpdatesDTO.self, forKey: .plugins)
        self.state = try? c.decodeIfPresent(PluginsResponseDTO.self, forKey: .state)
    }

    enum CodingKeys: String, CodingKey { case at, plugins, state }
}
