import Foundation
import Observation

/// `POST /api/caller-keys/limit-key` 的 `limit` 对象。
/// 只带用户可设置的字段；`since` 由服务端维护。
struct GatewayLimitPayload: Encodable, Sendable {
    var period: String
    var days: Int?
    var hours: Int?
    var account: String?
    var accountWindow: String?
    var tokens: Int64?
    var cost: Double?
    var cacheReads: Bool?
    var models: [String]?
}

@Observable
@MainActor
final class GatewayViewModel {
    var keys: [GatewayKeyDTO] = []
    var gateway: GatewayStateDTO?
    var models: [GatewayModelDTO] = []
    var accounts: [GatewayModelDTO] = []
    var accountWindows: [GatewayAccountWindowDTO] = []
    var accountGroups: [GatewayAccountGroupDTO] = []
    var callDetail: GatewayCallDetailDTO?
    var isLoading = false
    var isOperating = false
    var errorMessage: String?

    func load(client: MagpieAPIClient) async {
        isLoading = true
        errorMessage = nil
        do {
            let res = try await client.send(.get("/api/caller-keys"), as: GatewayKeysResponseDTO.self)
            self.keys = res.keys
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }

    func loadGateway(client: MagpieAPIClient) async {
        do {
            let envelope: GatewayStateEnvelope = try await client.send(
                .get("/api/providers"),
                as: GatewayStateEnvelope.self,
                timeout: 60
            )
            gateway = envelope.gateway
        } catch {
            if gateway == nil {
                errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    func loadModels(client: MagpieAPIClient) async {
        do {
            let res: GatewayModelsResponseDTO = try await client.send(
                .get("/api/caller-keys/models"),
                as: GatewayModelsResponseDTO.self
            )
            models = res.models ?? []
            accounts = res.accounts ?? []
        } catch {
            // 模型列表失败不阻断其他区域
        }
    }

    func loadAccountWindows(client: MagpieAPIClient) async {
        do {
            let res: GatewayAccountWindowsResponseDTO = try await client.send(
                .get("/api/caller-keys/account-windows"),
                as: GatewayAccountWindowsResponseDTO.self
            )
            accountWindows = res.windows
        } catch {
            // 账号窗口列表失败不阻断
        }
    }

    /// 读取 / 保存 / 删除账户组（官方 `GET/POST /api/account-groups`）。
    func loadAccountGroups(client: MagpieAPIClient) async {
        do {
            struct Response: Decodable { var groups: [GatewayAccountGroupDTO]? }
            let res: Response = try await client.send(
                .get("/api/account-groups"),
                as: Response.self
            )
            accountGroups = res.groups ?? []
        } catch {
            // 分组读取失败不阻断
        }
    }

    func saveAccountGroup(
        client: MagpieAPIClient,
        id: String?,
        name: String,
        accounts: [String]
    ) async -> Bool {
        await accountGroupAction(
            client: client,
            action: "save",
            body: AccountGroupBody(id: id, name: name, accounts: accounts)
        )
    }

    func removeAccountGroup(client: MagpieAPIClient, id: String) async -> Bool {
        await accountGroupAction(
            client: client,
            action: "remove",
            body: AccountGroupBody(id: id)
        )
    }

    private func accountGroupAction(
        client: MagpieAPIClient,
        action: String,
        body: AccountGroupBody
    ) async -> Bool {
        isOperating = true
        errorMessage = nil
        defer { isOperating = false }
        do {
            let resData = try await client.sendData(
                try Endpoint.post("/api/account-groups/\(action)", body: body)
            )
            struct Response: Decodable { var groups: [GatewayAccountGroupDTO]? }
            if let res = try? JSONDecoder().decode(Response.self, from: resData) {
                accountGroups = res.groups ?? []
            }
            MagpieHaptics.success()
            return true
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    private struct AccountGroupBody: Encodable {
        var id: String?
        var name: String?
        var accounts: [String]?

        init(id: String? = nil, name: String? = nil, accounts: [String]? = nil) {
            self.id = id
            self.name = name
            self.accounts = accounts
        }
    }

    func loadAll(client: MagpieAPIClient) async {
        await load(client: client)
        await loadGateway(client: client)
        await loadModels(client: client)
        await loadAccountWindows(client: client)
    }

    func loadCall(client: MagpieAPIClient, id: Int64) async -> GatewayCallDetailDTO? {
        do {
            let detail: GatewayCallDetailDTO = try await client.send(
                .get("/api/gateway/call", query: [URLQueryItem(name: "id", value: "\(id)")]),
                as: GatewayCallDetailDTO.self
            )
            callDetail = detail
            return detail
        } catch {
            return nil
        }
    }

    /// 新建 Key。action 必须是 `add-key`；`admin` 为空、`local` 或 `any`。
    func create(
        client: MagpieAPIClient,
        name: String,
        admin: String,
        readOnly: Bool
    ) async -> String? {
        isOperating = true
        errorMessage = nil
        defer { isOperating = false }
        do {
            struct Body: Encodable {
                var name: String
                var admin: String
                var readOnly: Bool
            }
            let res: GatewayKeysResponseDTO = try await client.send(
                .post("/api/caller-keys/add-key", body: Body(name: name, admin: admin, readOnly: readOnly)),
                as: GatewayKeysResponseDTO.self
            )
            self.keys = res.keys
            MagpieHaptics.success()
            return res.secret
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return nil
        }
    }

    /// 取回某个 Key 的明文（`copy-key`）。用于用户主动查看/复制。
    func revealSecret(client: MagpieAPIClient, id: String) async -> String? {
        isOperating = true
        errorMessage = nil
        defer { isOperating = false }
        do {
            struct Body: Encodable { var key: String }
            let res: GatewayKeysResponseDTO = try await client.send(
                .post("/api/caller-keys/copy-key", body: Body(key: id)),
                as: GatewayKeysResponseDTO.self
            )
            self.keys = res.keys
            return res.secret
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return nil
        }
    }

    /// 轮换 Key 的明文；返回新的明文。
    func rotate(client: MagpieAPIClient, id: String) async -> String? {
        isOperating = true
        errorMessage = nil
        defer { isOperating = false }
        do {
            struct Body: Encodable { var key: String }
            let res: GatewayKeysResponseDTO = try await client.send(
                .post("/api/caller-keys/rotate-key", body: Body(key: id)),
                as: GatewayKeysResponseDTO.self
            )
            self.keys = res.keys
            MagpieHaptics.success()
            return res.secret
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return nil
        }
    }

    func rename(client: MagpieAPIClient, id: String, name: String) async {
        isOperating = true
        errorMessage = nil
        defer { isOperating = false }
        do {
            struct Body: Encodable { var key: String; var name: String }
            let res: GatewayKeysResponseDTO = try await client.send(
                .post("/api/caller-keys/rename-key", body: Body(key: id, name: name)),
                as: GatewayKeysResponseDTO.self
            )
            self.keys = res.keys
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// 设置、替换或移除一个限额。
    ///
    /// - `index == nil`：把 `limit` 作为该 Key 唯一的限额（`limit == nil` 即清除）。
    /// - `index` 为已有下标：替换该限额；`index == limits.count`：追加；
    ///   `limit == nil` 且下标有效：移除该限额。
    func setLimit(
        client: MagpieAPIClient,
        keyID: String,
        limit: GatewayLimitPayload?,
        index: Int?
    ) async -> Bool {
        isOperating = true
        errorMessage = nil
        defer { isOperating = false }
        do {
            struct Body: Encodable {
                var key: String
                var limit: GatewayLimitPayload?
                var index: Int?
            }
            let res: GatewayKeysResponseDTO = try await client.send(
                .post("/api/caller-keys/limit-key", body: Body(key: keyID, limit: limit, index: index)),
                as: GatewayKeysResponseDTO.self
            )
            self.keys = res.keys
            MagpieHaptics.success()
            return true
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    /// 把某个限额已用的 tokens 与成本清零（`reset-limit-key`）。
    /// `index == nil` 时重置该 Key 的所有限额。
    func resetLimit(client: MagpieAPIClient, keyID: String, index: Int?) async -> Bool {
        isOperating = true
        errorMessage = nil
        defer { isOperating = false }
        do {
            struct Body: Encodable {
                var key: String
                var index: Int?
            }
            let res: GatewayKeysResponseDTO = try await client.send(
                .post("/api/caller-keys/reset-limit-key", body: Body(key: keyID, index: index)),
                as: GatewayKeysResponseDTO.self
            )
            self.keys = res.keys
            MagpieHaptics.success()
            return true
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    func setRouting(client: MagpieAPIClient, keyID: String, routing: String) async -> Bool {
        isOperating = true
        errorMessage = nil
        defer { isOperating = false }
        do {
            struct Body: Encodable { var key: String; var routing: String }
            let res: GatewayKeysResponseDTO = try await client.send(
                .post("/api/caller-keys/routing-key", body: Body(key: keyID, routing: routing)),
                as: GatewayKeysResponseDTO.self
            )
            self.keys = res.keys
            MagpieHaptics.success()
            return true
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    func setMemory(client: MagpieAPIClient, keyID: String, memory: Bool) async -> Bool {
        isOperating = true
        errorMessage = nil
        defer { isOperating = false }
        do {
            struct Body: Encodable { var key: String; var memory: Bool }
            let res: GatewayKeysResponseDTO = try await client.send(
                .post("/api/caller-keys/memory-key", body: Body(key: keyID, memory: memory)),
                as: GatewayKeysResponseDTO.self
            )
            self.keys = res.keys
            MagpieHaptics.success()
            return true
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    func toggle(client: MagpieAPIClient, id: String, turnOn: Bool) async {
        let action = turnOn ? "on-key" : "off-key"
        do {
            struct KeyActionBody: Encodable { var key: String }
            let res: GatewayKeysResponseDTO = try await client.send(
                .post("/api/caller-keys/\(action)", body: KeyActionBody(key: id)),
                as: GatewayKeysResponseDTO.self
            )
            self.keys = res.keys
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func delete(client: MagpieAPIClient, id: String) async -> Bool {
        do {
            struct RemoveBody: Encodable { var key: String }
            let res: GatewayKeysResponseDTO = try await client.send(
                .post("/api/caller-keys/remove-key", body: RemoveBody(key: id)),
                as: GatewayKeysResponseDTO.self
            )
            self.keys = res.keys
            return true
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }
}
