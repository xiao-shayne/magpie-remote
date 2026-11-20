import Foundation
import Observation

@Observable
@MainActor
final class GroupsViewModel {
    var groups: [GroupDTO] = []
    var models: [GroupModelRefDTO] = []
    var pools: [GroupPoolDTO] = []
    var deciders: [GroupModelRefDTO] = []
    var drawers: [GroupModelRefDTO] = []
    var skippable: [GroupSkippableDTO] = []
    var templates: [GroupTemplateDTO] = []
    var skip: [String] = []
    var accounts: [String: [GroupAccountDTO]] = [:]
    var gatewayKeys: [GroupGatewayKeyDTO] = []
    var defaults = GroupDefaultsDTO()
    var found = true
    var isLoading = false
    var isOperating = false
    var errorMessage: String?
    var sharedText: String?
    var importedNote: String?

    func load(client: MagpieAPIClient) async {
        isLoading = true
        errorMessage = nil
        do {
            let res = try await client.send(.get("/api/groups"), as: GroupsResponseDTO.self)
            apply(res)
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }

    private func apply(_ res: GroupsResponseDTO) {
        groups = res.groups
        models = res.models ?? []
        pools = res.pools ?? []
        deciders = res.deciders ?? []
        drawers = res.drawers ?? []
        skippable = res.skippable ?? []
        skip = res.skip ?? []
        templates = res.templates ?? []
        accounts = res.accounts ?? [:]
        gatewayKeys = res.gatewayKeys ?? []
        defaults = res.defaults ?? GroupDefaultsDTO()
        if let f = res.found { found = f }
    }

    // MARK: - 动作

    func save(client: MagpieAPIClient, draft: GroupDraft, from: String?) async -> Bool {
        let request = GroupSaveRequest(
            id: draft.id,
            name: draft.name,
            members: draft.members,
            routing: draft.routing,
            affinity: draft.affinity,
            unlists: draft.unlists,
            sink: draft.sink,
            keys: draft.keys,
            accounts: draft.accounts,
            classifier: draft.classifier,
            rules: draft.rules,
            from: from
        )
        return await perform(client: client, path: "/api/groups/save", body: request)
    }

    func delete(client: MagpieAPIClient, id: String) async -> Bool {
        await perform(client: client, path: "/api/groups/delete", body: GroupActionBody(id: id))
    }

    func copy(client: MagpieAPIClient, id: String, name: String) async -> Bool {
        await perform(client: client, path: "/api/groups/copy", body: GroupActionBody(id: id, name: name))
    }

    func switchGroup(client: MagpieAPIClient, id: String, on: Bool) async -> Bool {
        await perform(client: client, path: "/api/groups/switch", body: GroupActionBody(id: id, on: on))
    }

    func pick(client: MagpieAPIClient, id: String, member: String) async -> Bool {
        await perform(client: client, path: "/api/groups/pick", body: GroupActionBody(id: id, pick: member))
    }

    func setFound(client: MagpieAPIClient, on: Bool) async -> Bool {
        await perform(client: client, path: "/api/groups/found", body: GroupActionBody(on: on))
    }

    /// 自动发现组里排除某些 Provider。
    func setSkip(client: MagpieAPIClient, skip: [String]) async -> Bool {
        await perform(client: client, path: "/api/groups/skip", body: GroupActionBody(skip: skip))
    }

    func addTemplate(client: MagpieAPIClient, kind: String, name: String) async -> Bool {
        await perform(
            client: client,
            path: "/api/groups/template",
            body: GroupActionBody(id: name, name: name, kind: kind)
        )
    }

    /// 每个组共同的默认值（限流后置、首 token 与耐心时长）。
    func setDefaults(client: MagpieAPIClient, sink: Bool, firstToken: Int, patience: Int) async -> Bool {
        await perform(
            client: client,
            path: "/api/groups/defaults",
            body: GroupActionBody(
                sink: sink,
                firstToken: firstToken,
                patience: patience
            )
        )
    }

    /// 分享组：返回可粘贴到另一台 magpie 的文本。
    func share(client: MagpieAPIClient, id: String) async -> String? {
        isOperating = true
        errorMessage = nil
        defer { isOperating = false }
        do {
            let data = try await client.sendData(try Endpoint.post("/api/groups/share", body: GroupActionBody(id: id)))
            // 响应是最新 groupsState，shared 字段在顶层。
            if let res = try? JSONDecoder().decode(GroupsResponseDTO.self, from: data) {
                apply(res)
                sharedText = res.shared
                return res.shared
            }
            return nil
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return nil
        }
    }

    /// 从文本导入组。
    func importGroup(client: MagpieAPIClient, text: String, replaceExisting: Bool) async -> Bool {
        await perform(
            client: client,
            path: "/api/groups/import",
            body: GroupActionBody(text: text, replace: replaceExisting)
        )
    }

    private struct GroupActionBody: Encodable {
        var id: String? = nil
        var name: String? = nil
        var on: Bool? = nil
        var pick: String? = nil
        var kind: String? = nil
        var sink: Bool? = nil
        var firstToken: Int? = nil
        var patience: Int? = nil
        var text: String? = nil
        var replace: Bool? = nil
        var skip: [String]? = nil
        var order: [String]? = nil
    }

    private func perform<Body: Encodable>(client: MagpieAPIClient, path: String, body: Body) async -> Bool {
        isOperating = true
        errorMessage = nil
        defer { isOperating = false }
        do {
            let data = try await client.sendData(try Endpoint.post(path, body: body))
            if let res = try? JSONDecoder().decode(GroupsResponseDTO.self, from: data) {
                apply(res)
            } else {
                await load(client: client)
            }
            MagpieHaptics.success()
            return true
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    func group(ref: String) -> GroupDTO? {
        groups.first { $0.ref == ref }
    }

    func group(id: String) -> GroupDTO? {
        groups.first { $0.id == id }
    }
}
