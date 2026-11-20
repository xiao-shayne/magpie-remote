import XCTest
@testable import MagpieRemote

final class ModelDecodingTests: XCTestCase {
    func testDecodeProviders() throws {
        let json = """
        {
          "providers": [
            {
              "id": "deepseek",
              "name": "DeepSeek",
              "host": "api.deepseek.com",
              "off": false,
              "models": ["deepseek-chat", "deepseek-coder"],
              "keyList": [
                {"id": "k1", "masked": "sk-abc...xyz", "active": true, "on": true}
              ]
            }
          ],
          "presets": [
            {"id": "kimi", "name": "Kimi Code", "kind": "partner", "added": false}
          ]
        }
        """.data(using: .utf8)!

        let res = try JSONDecoder().decode(ProvidersResponseDTO.self, from: json)
        XCTAssertEqual(res.providers.count, 1)
        XCTAssertEqual(res.providers[0].name, "DeepSeek")
        XCTAssertFalse(res.providers[0].isOff)
        XCTAssertEqual(res.providers[0].models?.count, 2)
        XCTAssertEqual(res.providers[0].models?[0].id, "deepseek-chat")
        XCTAssertEqual(res.providers[0].keyList?.count, 1)
        XCTAssertEqual(res.presets?.count, 1)
    }

    func testDecodeProvidersWithObjectModels() throws {
        let json = """
        {
          "providers": [
            {
              "id": "grok",
              "name": "xAI Grok",
              "models": [
                {"id": "grok-4", "name": "Grok 4 (Reasoning)", "on": true},
                {"id": "grok-code", "name": "grok-code", "on": false}
              ]
            }
          ]
        }
        """.data(using: .utf8)!

        let res = try JSONDecoder().decode(ProvidersResponseDTO.self, from: json)
        XCTAssertEqual(res.providers.count, 1)
        let models = res.providers[0].models ?? []
        XCTAssertEqual(models.count, 2)
        XCTAssertEqual(models[0].id, "grok-4")
        XCTAssertEqual(models[0].name, "Grok 4 (Reasoning)")
        XCTAssertEqual(models[0].displayName, "Grok 4 (Reasoning) (grok-4)")
        XCTAssertEqual(models[1].displayName, "grok-code")
    }

    func testDecodeGroups() throws {
        let json = """
        {
          "groups": [
            {
              "id": "g1",
              "ref": "auto/deepseek-v4",
              "name": "DeepSeek V4",
              "routing": "smart",
              "ready": true,
              "members": ["provider1/modelA", "provider2/modelB"]
            },
            {
              "id": "g2",
              "ref": "group/g2",
              "name": "Custom",
              "members": ["provider1/modelA", "provider2/modelB"],
              "unlists": true,
              "off": ["provider1/modelA"],
              "disabled": true
            }
          ],
          "found": true
        }
        """.data(using: .utf8)!

        let res = try JSONDecoder().decode(GroupsResponseDTO.self, from: json)
        XCTAssertEqual(res.groups.count, 2)
        XCTAssertEqual(res.groups[0].name, "DeepSeek V4")
        XCTAssertTrue(res.groups[0].isAuto)
        XCTAssertEqual(res.groups[0].members?.count, 2)
        XCTAssertEqual(res.groups[1].unlists, true)
        XCTAssertEqual(res.groups[1].off, ["provider1/modelA"])
        XCTAssertEqual(res.groups[1].disabled, true)
    }

    func testGroupSaveRequestEncodesUpstreamKeys() throws {
        let request = GroupSaveRequest(
            id: "g2",
            name: "Custom",
            members: ["provider1/modelA"],
            routing: "smart",
            affinity: "",
            unlists: true,
            sink: false,
            keys: nil,
            accounts: nil,
            classifier: nil,
            rules: nil,
            from: nil
        )
        let data = try JSONEncoder().encode(request)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["unlists"] as? Bool, true)
        XCTAssertNil(object["unlisted"])
    }

    func testDecodeUsageAndQuotas() throws {
        let json = """
        {
          "period": "30d",
          "calls": 12050,
          "input": 50000000,
          "output": 1000000,
          "cache_read": 20000000,
          "cost": 15.65
        }
        """.data(using: .utf8)!

        let usage = try JSONDecoder().decode(UsageDTO.self, from: json)
        XCTAssertEqual(usage.calls, 12050)
        XCTAssertEqual(usage.formattedCost, "$15.65")
        XCTAssertEqual(UsageDTO.formatTokens(usage.input ?? 0), "50.00 M")

        let quotaJson = """
        [
          {
            "provider": "codex",
            "name": "Codex",
            "balance": "$20.00",
            "windows": [
              {"name": "30 days", "used": 45.5, "remaining": 54.5}
            ]
          }
        ]
        """.data(using: .utf8)!

        let quotas = try JSONDecoder().decode([QuotaItemDTO].self, from: quotaJson)
        XCTAssertEqual(quotas.count, 1)
        XCTAssertEqual(quotas[0].windows?.first?.percentUsed, 45.5)
    }

    func testDecodeSessions() throws {
        let json = """
        {
          "sessions": [
            {
              "id": "sess-123",
              "agent": "claude",
              "name": "Claude Code",
              "title": "Fix login bug",
              "cost": 0.0521,
              "input": 15000,
              "output": 800,
              "last": "2026-11-14T06:00:00Z"
            }
          ]
        }
        """.data(using: .utf8)!

        let res = try JSONDecoder().decode(SessionsResponseDTO.self, from: json)
        XCTAssertEqual(res.sessions.count, 1)
        XCTAssertEqual(res.sessions[0].displayTitle, "Fix login bug")
        XCTAssertEqual(res.sessions[0].displayAgent, "Claude Code")
    }

    func testDecodeGatewayKeys() throws {
        let json = """
        {
          "keys": [
            {
              "id": "key_abc",
              "name": "Work Laptop",
              "masked": "sk-magpie...99",
              "off": false,
              "admin": "local"
            }
          ]
        }
        """.data(using: .utf8)!

        let res = try JSONDecoder().decode(GatewayKeysResponseDTO.self, from: json)
        XCTAssertEqual(res.keys.count, 1)
        XCTAssertEqual(res.keys[0].displayName, "Work Laptop")
        XCTAssertTrue(res.keys[0].isAdmin)
        XCTAssertFalse(res.keys[0].isOff)
    }

    func testDecodeGatewayKeyLimitUsage() throws {
        let json = """
        {
          "keys": [
            {
              "id": "key_abc",
              "name": "Work Laptop",
              "limit": {"period": "day", "tokens": 2000000},
              "moreLimits": [{"period": "week", "cost": 1.5}],
              "usedAll": [
                {
                  "period": "day",
                  "tokenLimit": 2000000,
                  "tokens": 1200000,
                  "tokensLeft": 800000,
                  "cost": 0.42,
                  "reset": "2026-11-16T00:00:00+08:00",
                  "spent": false
                },
                {
                  "period": "week",
                  "costLimit": 1.5,
                  "cost": 0.3,
                  "costLeft": 1.2,
                  "reset": "2026-11-17T00:00:00+08:00",
                  "spent": false
                }
              ]
            }
          ]
        }
        """.data(using: .utf8)!

        let res = try JSONDecoder().decode(GatewayKeysResponseDTO.self, from: json)
        let key = try XCTUnwrap(res.keys.first)
        XCTAssertEqual(key.limits.count, 2)
        XCTAssertEqual(key.limitUsages.count, 2)
        XCTAssertEqual(key.limitUsages[0].tokensLeftDescription, "800.0 K / 2.00 M")
        XCTAssertEqual(key.limitUsages[1].costLeftDescription, "$1.20 / $1.50")
        XCTAssertFalse(key.limitUsages[0].isSpent)
        XCTAssertNotNil(key.limitUsages[0].resetDate)
    }

    func testQuotaItemsForDifferentAccountsHaveUniqueIDs() throws {
        let json = """
        [
          {"provider": "codex", "name": "Codex", "user": "alice", "windows": []},
          {"provider": "codex", "name": "Codex", "user": "bob", "windows": []},
          {"provider": "mistral", "name": "Mistral", "windows": []}
        ]
        """.data(using: .utf8)!

        let quotas = try JSONDecoder().decode([QuotaItemDTO].self, from: json)
        XCTAssertEqual(quotas.count, 3)
        XCTAssertEqual(quotas[0].user, "alice")
        XCTAssertEqual(Set(quotas.map(\.id)).count, quotas.count)
    }

    func testExtractCleanURLAndKey() {
        let input = "https://mapm.2020713.xyz/?k=79261a46b263781ddc6af6d168a8597543d8065fc5f71f14c2b942bef3f8afa0"
        let (clean, key) = ConnectionEditViewModel.extractCleanURLAndKey(from: input)
        XCTAssertEqual(clean, "https://mapm.2020713.xyz/")
        XCTAssertEqual(key, "79261a46b263781ddc6af6d168a8597543d8065fc5f71f14c2b942bef3f8afa0")

        let cleanOnly = "http://192.168.1.50:3426"
        let (resURL, resKey) = ConnectionEditViewModel.extractCleanURLAndKey(from: cleanOnly)
        XCTAssertEqual(resURL, "http://192.168.1.50:3426")
        XCTAssertNil(resKey)
    }
}
