import Foundation
import Observation

/// Agents 页 ViewModel：选模型、页面面板与行操作。
@Observable
@MainActor
final class AgentsViewModel {
    var isSaving = false
    var saveError: String?

    var quotas: [QuotaItemDTO] = []
    var groups: [GroupDTO] = []
    var usageAgents: [UsageGroupDTO] = []
    var isLoadingPanels = false

    /// 为某 Agent 的某字段选值（核心「选模型」动作），成功后应用返回的最新 state。
    func pick(
        client: MagpieAPIClient,
        app: AppModel,
        agentID: String,
        fieldKey: String,
        value: String
    ) async -> Bool {
        isSaving = true
        saveError = nil
        defer { isSaving = false }
        do {
            let body = SetRequest(agent: agentID, field: fieldKey, value: value)
            let newState = try await client.send(.post("/api/set", body: body), as: StateDTO.self)
            app.apply(newState)
            return true
        } catch {
            saveError = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    /// 将被隐藏/未选入列表的路由组重新放回该 Agent 的模型列表（`POST /api/agent-models/{id}`），再设为当前值。
    func showAndPick(
        client: MagpieAPIClient,
        app: AppModel,
        agentID: String,
        fieldKey: String,
        ref: String,
        value: String
    ) async -> Bool {
        isSaving = true
        saveError = nil
        defer { isSaving = false }
        do {
            if !ref.isEmpty {
                struct ShowBody: Encodable { let Show: String }
                _ = try await client.sendData(
                    try Endpoint.post("/api/agent-models/\(agentID)", body: ShowBody(Show: ref))
                )
            }
            let body = SetRequest(agent: agentID, field: fieldKey, value: value)
            let newState = try await client.send(.post("/api/set", body: body), as: StateDTO.self)
            app.apply(newState)
            return true
        } catch {
            saveError = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    // MARK: - 面板
    func loadPanels(client: MagpieAPIClient) async {
        isLoadingPanels = true
        defer { isLoadingPanels = false }

        do {
            let usage: UsageDTO = try await client.send(
                .get("/api/usage", query: [URLQueryItem(name: "period", value: "30d")]),
                as: UsageDTO.self,
                timeout: 60
            )
            usageAgents = usage.agents ?? []
        } catch {
            // 用量面板失败不影响 Agents
        }

        do {
            quotas = try await client.send(.get("/api/usage/quotas"), as: [QuotaItemDTO].self, timeout: 60)
        } catch {
            // 配额面板失败不影响 Agents
        }

        do {
            let response: GroupsResponseDTO = try await client.send(.get("/api/groups"), as: GroupsResponseDTO.self)
            groups = response.groups
        } catch {
            // 路由面板失败不影响 Agents
        }
    }

    // MARK: - 行操作
    func openAgent(client: MagpieAPIClient, id: String) async -> Bool {
        do {
            struct Body: Encodable { var agent: String }
            _ = try await client.sendData(try Endpoint.post("/api/agents/open", body: Body(agent: id)))
            return true
        } catch {
            saveError = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    func restartAgent(client: MagpieAPIClient, id: String) async -> Bool {
        await stateAction(client: client, path: "/api/agents/restart/\(id)")
    }

    func disconnectOffline(client: MagpieAPIClient, id: String) async -> Bool {
        await stateAction(client: client, path: "/api/agents/disconnect-offline/\(id)")
    }

    private func stateAction(client: MagpieAPIClient, path: String) async -> Bool {
        do {
            _ = try await client.sendData(Endpoint.post(path))
            return true
        } catch {
            saveError = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }
}
