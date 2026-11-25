import Foundation
import Observation

// MARK: - Library 数据
/// `GET /api/library`（library.View 的核心字段）。
struct LibraryDTO: Codable, Sendable {
    var agents: [LibraryAgentDTO]?
    var servers: [LibraryServerDTO]?
    var skills: [LibrarySkillDTO]?
    var instructions: LibraryInstructionsDTO?
    var dir: String?
    var backups: String?
    var home: String?
    var problems: [LibraryProblemDTO]?
    var copySkills: Bool?
    var sharedSkills: Bool?
    var sharedDir: String?
    var mcpHub: Bool?
    var skillRouter: Bool?
    var autoUpdateSkills: Bool?
    var partial: Bool?

    enum CodingKeys: String, CodingKey {
        case agents, servers, skills, instructions, dir, backups, home, problems
        case copySkills, sharedSkills, sharedDir, mcpHub, skillRouter, autoUpdateSkills, partial
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.agents = try? c.decodeIfPresent([LibraryAgentDTO].self, forKey: .agents)
        self.servers = try? c.decodeIfPresent([LibraryServerDTO].self, forKey: .servers)
        self.skills = try? c.decodeIfPresent([LibrarySkillDTO].self, forKey: .skills)
        self.instructions = try? c.decodeIfPresent(LibraryInstructionsDTO.self, forKey: .instructions)
        self.dir = try? c.decodeIfPresent(String.self, forKey: .dir)
        self.backups = try? c.decodeIfPresent(String.self, forKey: .backups)
        self.home = try? c.decodeIfPresent(String.self, forKey: .home)
        self.problems = try? c.decodeIfPresent([LibraryProblemDTO].self, forKey: .problems)
        self.copySkills = try? c.decodeIfPresent(Bool.self, forKey: .copySkills)
        self.sharedSkills = try? c.decodeIfPresent(Bool.self, forKey: .sharedSkills)
        self.sharedDir = try? c.decodeIfPresent(String.self, forKey: .sharedDir)
        self.mcpHub = try? c.decodeIfPresent(Bool.self, forKey: .mcpHub)
        self.skillRouter = try? c.decodeIfPresent(Bool.self, forKey: .skillRouter)
        self.autoUpdateSkills = try? c.decodeIfPresent(Bool.self, forKey: .autoUpdateSkills)
        self.partial = try? c.decodeIfPresent(Bool.self, forKey: .partial)
    }
}

struct LibraryProblemDTO: Codable, Sendable, Identifiable, Hashable {
    var what: String?
    var agent: String?
    var error: String?

    var id: String { "\(what ?? "")-\(agent ?? "")-\(error ?? "")" }
}

struct LibraryAgentDTO: Codable, Sendable, Identifiable, Hashable {
    var id: String
    var name: String
    var icon: String?
    var instructions: String?
    var mcp: String?
    var skills: String?
    var mcpVia: String?
    var how: String?
    var gone: Bool?
    var asleep: String?
    var unseen: Bool?

    var displayName: String { name.isEmpty ? id : name }
}

struct LibraryServerDTO: Codable, Sendable, Identifiable, Hashable {
    var name: String
    var transport: String
    var command: String?
    var args: [String]?
    var url: String?
    var agents: [String]?
    var disabledTools: [String]?
    var hidden: Bool?
    var note: String?
    var plugin: String?
    var icon: String?
    var problems: [String: String]?
    var bundle: String?

    var id: String { name }

    var isRemote: Bool { transport == "http" || transport == "sse" }

    var commandLine: String {
        if isRemote { return url ?? "" }
        return ([command ?? ""] + (args ?? [])).filter { !$0.isEmpty }.joined(separator: " ")
    }

    var transportName: String {
        switch transport {
        case "stdio": return "STDIO"
        case "http": return "HTTP"
        case "sse": return "SSE"
        default: return transport.uppercased()
        }
    }
}

struct LibrarySkillDTO: Codable, Sendable, Identifiable, Hashable {
    var name: String
    var description: String
    var source: String?
    var kind: String?
    var agents: [String]?
    var offHere: Bool?
    var note: String?
    var repo: String?
    var bundle: String?
    var missing: Bool?
    var edited: Bool?
    var gone: String?
    var always: [String]?
    var shared: String?
    var behind: [String]?

    var id: String { name }

    var isOff: Bool { offHere ?? false }
}

struct LibraryInstructionsDTO: Codable, Sendable, Hashable {
    var shared: String?
    var sets: [LibrarySetDTO]?
    var agents: [LibraryInstructionsAgentDTO]?

    enum CodingKeys: String, CodingKey { case shared, sets, agents }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.shared = try? c.decodeIfPresent(String.self, forKey: .shared)
        self.sets = try? c.decodeIfPresent([LibrarySetDTO].self, forKey: .sets)
        self.agents = try? c.decodeIfPresent([LibraryInstructionsAgentDTO].self, forKey: .agents)
    }
}

struct LibrarySetDTO: Codable, Sendable, Identifiable, Hashable {
    var id: String
    var name: String
    var active: Bool?
}

struct LibraryInstructionsAgentDTO: Codable, Sendable, Identifiable, Hashable {
    var agent: String
    var name: String?
    var icon: String?
    var path: String?
    var on: Bool?
    var extra: String?
    var edited: Bool?
    var own: Int?

    var id: String { agent }

    var displayName: String { name?.isEmpty == false ? name! : agent }
}

// MARK: - 市场
/// `GET /api/library/market/{skills|servers}` 的返回。
struct LibraryMarketResponseDTO: Codable, Sendable {
    var items: [LibraryMarketItemDTO]
    var error: String?
    var failed: String?
    var cause: String?
    var custom: LibraryMarketCustomDTO?

    enum CodingKeys: String, CodingKey { case items, error, failed, cause, custom }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.items = (try? c.decode([LibraryMarketItemDTO].self, forKey: .items)) ?? []
        self.error = try? c.decodeIfPresent(String.self, forKey: .error)
        self.failed = try? c.decodeIfPresent(String.self, forKey: .failed)
        self.cause = try? c.decodeIfPresent(String.self, forKey: .cause)
        self.custom = try? c.decodeIfPresent(LibraryMarketCustomDTO.self, forKey: .custom)
    }
}

/// 市场条目：技能与 MCP 服务器共用一个宽松结构。
struct LibraryMarketItemDTO: Codable, Sendable, Identifiable, Hashable {
    var id: String?
    var name: String?
    var title: String?
    var publisher: String?
    var icon: String?
    var description: String?
    // 技能
    var source: String?
    var skillId: String?
    var installs: Int?
    var official: Bool?
    // 服务器
    var transport: String?
    var signIn: Bool?
    var runs: String?
    var featured: Bool?
    var unready: String?
    var optIn: Bool?
    var homepage: String?
    var inputs: [LibraryMarketInputDTO]?
    // Claude 插件市场
    var author: String?
    var category: String?
    var marketplace: String?
    var version: String?
    // 已安装时它在库中的名字
    var have: String?

    var displayName: String { title ?? name ?? id ?? source ?? "—" }

    var isAdded: Bool { have?.isEmpty == false }

    var needsInputs: Bool { (inputs ?? []).contains { $0.required == true } }

    var inputSummary: String? {
        let required = (inputs ?? []).filter { $0.required == true }.map(\.displayLabel)
        return required.isEmpty ? nil : required.joined(separator: "、")
    }

    enum CodingKeys: String, CodingKey {
        case id, name, title, publisher, icon, description
        case source, skillId, installs, official
        case transport, signIn, runs, featured, unready, optIn, homepage, inputs
        case author, category, marketplace, version, have
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try? c.decodeIfPresent(String.self, forKey: .id)
        self.name = try? c.decodeIfPresent(String.self, forKey: .name)
        self.title = try? c.decodeIfPresent(String.self, forKey: .title)
        self.publisher = try? c.decodeIfPresent(String.self, forKey: .publisher)
        self.icon = try? c.decodeIfPresent(String.self, forKey: .icon)
        self.description = try? c.decodeIfPresent(String.self, forKey: .description)
        self.source = try? c.decodeIfPresent(String.self, forKey: .source)
        self.skillId = try? c.decodeIfPresent(String.self, forKey: .skillId)
        self.installs = try? c.decodeIfPresent(Int.self, forKey: .installs)
        self.official = try? c.decodeIfPresent(Bool.self, forKey: .official)
        self.transport = try? c.decodeIfPresent(String.self, forKey: .transport)
        self.signIn = try? c.decodeIfPresent(Bool.self, forKey: .signIn)
        self.runs = try? c.decodeIfPresent(String.self, forKey: .runs)
        self.featured = try? c.decodeIfPresent(Bool.self, forKey: .featured)
        self.unready = try? c.decodeIfPresent(String.self, forKey: .unready)
        self.optIn = try? c.decodeIfPresent(Bool.self, forKey: .optIn)
        self.homepage = try? c.decodeIfPresent(String.self, forKey: .homepage)
        self.inputs = try? c.decodeIfPresent([LibraryMarketInputDTO].self, forKey: .inputs)
        self.author = try? c.decodeIfPresent(String.self, forKey: .author)
        self.category = try? c.decodeIfPresent(String.self, forKey: .category)
        self.marketplace = try? c.decodeIfPresent(String.self, forKey: .marketplace)
        self.version = try? c.decodeIfPresent(String.self, forKey: .version)
        self.have = try? c.decodeIfPresent(String.self, forKey: .have)
    }
}

struct LibraryMarketInputDTO: Codable, Sendable, Hashable, Identifiable {
    var key: String
    var label: String?
    var placeholder: String?
    var description: String?
    var whereField: String?
    var secret: Bool?
    var required: Bool?

    var id: String { key }
    var displayLabel: String { label ?? key }

    enum CodingKeys: String, CodingKey {
        case key, label, placeholder, description
        case whereField = "where"
        case secret, required
    }
}

/// 搜索地址时给出的「手动添加」建议。
struct LibraryMarketCustomDTO: Codable, Sendable, Hashable {
    var name: String?
    var transport: String?
    var command: String?
    var args: [String]?
    var url: String?
}

// MARK: - ViewModel
@Observable
@MainActor
final class LibraryViewModel {
    var library: LibraryDTO?
    var isLoading = false
    var isWorking = false
    var errorMessage: String?
    var lastAction: String?
    /// 每次读取成功后自增，供界面同步编辑草稿。
    var revision = 0

    func load(client: MagpieAPIClient) async {
        isLoading = true
        errorMessage = nil
        do {
            library = try await client.send(.get("/api/library"), as: LibraryDTO.self)
            revision += 1
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }

    func refresh(client: MagpieAPIClient) async {
        do {
            library = try await client.send(.get("/api/library"), as: LibraryDTO.self)
            revision += 1
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// 全量同步：把库内容写入所有 Agent。
    func sync(client: MagpieAPIClient) async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            library = try await client.send(
                .post("/api/library/all/sync"),
                as: LibraryDTO.self
            )
            revision += 1
            lastAction = String(localized: "已同步到全部 Agent")
            MagpieHaptics.success()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// 检查技能的上游是否有更新（官方 `skills/check`）。
    func checkSkills(client: MagpieAPIClient) async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            library = try await client.send(
                .post("/api/library/skills/check"),
                as: LibraryDTO.self,
                timeout: 120
            )
            revision += 1
            lastAction = String(localized: "已检查技能更新")
            MagpieHaptics.success()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// 更新全部有上游更新的技能（官方 `skills/update-all`）。
    func updateAllSkills(client: MagpieAPIClient) async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            library = try await client.send(
                .post("/api/library/skills/update-all"),
                as: LibraryDTO.self,
                timeout: 180
            )
            revision += 1
            lastAction = String(localized: "技能已全部更新")
            MagpieHaptics.success()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - 市场
    var marketItems: [LibraryMarketItemDTO] = []
    var marketLoading = false
    var marketError: String?

    func loadMarket(client: MagpieAPIClient, kind: String, query: String) async {
        marketLoading = true
        marketError = nil
        defer { marketLoading = false }
        var q: [URLQueryItem] = []
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            q.append(URLQueryItem(name: "q", value: trimmed))
        }
        do {
            let res: LibraryMarketResponseDTO = try await client.send(
                .get("/api/library/market/\(kind)", query: q),
                as: LibraryMarketResponseDTO.self,
                timeout: 60
            )
            marketItems = res.items
            if let error = res.error, !error.isEmpty {
                marketError = error
            }
        } catch {
            marketItems = []
            marketError = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// 从市场安装技能（`market/skill`，source + skillId）。
    func installMarketSkill(
        client: MagpieAPIClient,
        item: LibraryMarketItemDTO,
        agents: [String]
    ) async -> Bool {
        guard let source = item.source, let skillID = item.skillId else {
            marketError = String(localized: "这个技能缺少来源信息")
            return false
        }
        return await performMarket(
            client: client,
            path: "/api/library/market/skill",
            body: ["source": source, "id": skillID, "agents": agents],
            name: item.displayName
        )
    }

    /// 从市场安装 MCP 服务器（`market/server`，id + values）。
    func installMarketServer(
        client: MagpieAPIClient,
        item: LibraryMarketItemDTO,
        values: [String: String],
        agents: [String]
    ) async -> Bool {
        guard let id = item.id else {
            marketError = String(localized: "这个服务器缺少 id")
            return false
        }
        return await performMarket(
            client: client,
            path: "/api/library/market/server",
            body: ["id": id, "values": values, "agents": agents],
            name: item.displayName
        )
    }

    private func performMarket(
        client: MagpieAPIClient,
        path: String,
        body: [String: Any],
        name: String
    ) async -> Bool {
        guard JSONSerialization.isValidJSONObject(body),
              let data = try? JSONSerialization.data(withJSONObject: body) else {
            marketError = String(localized: "请求数据无效")
            return false
        }
        isWorking = true
        marketError = nil
        defer { isWorking = false }
        do {
            let resData = try await client.sendData(
                Endpoint(path: path, method: .post, body: data),
                timeout: 180
            )
            if let updated = try? JSONDecoder().decode(LibraryDTO.self, from: resData) {
                library = updated
                revision += 1
            } else {
                await refresh(client: client)
            }
            if let index = marketItems.firstIndex(where: { $0.displayName == name }) {
                marketItems[index].have = name
            }
            lastAction = String(localized: "已添加 \(name)")
            MagpieHaptics.success()
            return true
        } catch {
            marketError = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    /// 从市场安装 Claude 插件（`plugins/install`，source + names + agents）。
    func installMarketClaudePlugin(
        client: MagpieAPIClient,
        item: LibraryMarketItemDTO,
        agents: [String]
    ) async -> Bool {
        guard let source = item.source, let name = item.name, !source.isEmpty, !name.isEmpty else {
            marketError = String(localized: "这个插件缺少来源信息")
            return false
        }
        return await performMarket(
            client: client,
            path: "/api/library/plugins/install",
            body: ["Source": source, "Names": [name], "Agents": agents],
            name: item.displayName
        )
    }

    /// 开启或关闭 Skill Router（`POST /api/library/skills/router`）。
    func setSkillRouter(client: MagpieAPIClient, on: Bool) async {
        _ = await perform(client: client, path: "/api/library/skills/router", body: ["On": on])
    }

    /// 开启或关闭 MCP Router（`POST /api/library/servers/hub`）。
    func setMCPHub(client: MagpieAPIClient, on: Bool) async {
        _ = await perform(client: client, path: "/api/library/servers/hub", body: ["On": on])
    }

    /// MCP Router 工具暴露方式（`POST /api/library/servers/hub-tools`：false = 按需加载，true = 全部暴露）。
    func setHubAllTools(client: MagpieAPIClient, allTools: Bool) async {
        _ = await perform(client: client, path: "/api/library/servers/hub-tools", body: ["On": allTools])
    }

    /// MCP Router 的 `run_code` 代码模式（`POST /api/library/servers/hub-code`）。
    func setHubCode(client: MagpieAPIClient, on: Bool) async {
        _ = await perform(client: client, path: "/api/library/servers/hub-code", body: ["On": on])
    }

    func setSkillAgents(client: MagpieAPIClient, name: String, agents: [String]) async {
        await perform(client: client, path: "/api/library/skills/agents", body: ["Name": name, "Agents": agents])
    }

    func setServerAgents(client: MagpieAPIClient, name: String, agents: [String]) async {
        await perform(client: client, path: "/api/library/servers/agents", body: ["Name": name, "Agents": agents])
    }

    func setSkillHere(client: MagpieAPIClient, name: String, on: Bool) async {
        await perform(client: client, path: "/api/library/skills/here", body: ["Name": name, "On": on])
    }

    func removeSkill(client: MagpieAPIClient, name: String) async {
        await perform(client: client, path: "/api/library/skills/remove", body: ["Name": name])
    }

    func removeServer(client: MagpieAPIClient, name: String) async {
        await perform(client: client, path: "/api/library/servers/remove", body: ["Name": name])
    }

    func saveServer(
        client: MagpieAPIClient,
        old: String,
        name: String,
        transport: String,
        command: String,
        args: [String],
        url: String,
        agents: [String]
    ) async -> Bool {
        var server: [String: Any] = [
            "name": name,
            "transport": transport,
            "agents": agents
        ]
        if transport == "stdio" {
            server["command"] = command
            server["args"] = args
        } else {
            server["url"] = url
        }
        return await perform(
            client: client,
            path: "/api/library/servers/save",
            body: ["Old": old, "Server": server]
        )
    }

    /// 保存共享指令与每个 Agent 的启用状态。
    func saveInstructions(client: MagpieAPIClient, shared: String, agents: [String]) async -> Bool {
        await perform(
            client: client,
            path: "/api/library/instructions/save",
            body: ["Shared": shared, "Agents": agents]
        )
    }

    @discardableResult
    private func perform(client: MagpieAPIClient, path: String, body: [String: Any]) async -> Bool {
        guard JSONSerialization.isValidJSONObject(body),
              let data = try? JSONSerialization.data(withJSONObject: body) else {
            errorMessage = String(localized: "请求数据无效")
            return false
        }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            _ = try await client.sendData(Endpoint(path: path, method: .post, body: data))
            await refresh(client: client)
            MagpieHaptics.success()
            return true
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    // MARK: - 便捷查询
    func agent(_ id: String) -> LibraryAgentDTO? {
        library?.agents?.first { $0.id == id }
    }

    func agentName(_ id: String) -> String {
        agent(id)?.displayName ?? id
    }

    func agentIcon(_ id: String) -> String? {
        agent(id)?.icon
    }

    /// 可以接收技能 / MCP 的 Agent（排除未安装或未就绪的）。
    var activeAgents: [LibraryAgentDTO] {
        (library?.agents ?? []).filter { $0.gone != true && $0.unseen != true }
    }
}
