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

    // MARK: - 上游同步契约测试

    func testDecodeUnservedGroupsAndEffortOrdering() throws {
        let json = """
        {
          "key": "model",
          "label": "Model",
          "value": "claude/claude-sonnet-4-6",
          "unserved": [
            {
              "value": "group/fast-code",
              "label": "Fast Code",
              "icons": ["claude"],
              "ref": "group/fast-code",
              "why": "Hidden from this agent's model list",
              "pick": true
            },
            {
              "value": "group/offline",
              "label": "Offline Group",
              "ref": "group/offline",
              "why": "No ready provider"
            }
          ]
        }
        """.data(using: .utf8)!

        let field = try JSONDecoder().decode(FieldDTO.self, from: json)
        XCTAssertEqual(field.unserved?.count, 2)
        XCTAssertTrue(field.unserved?[0].isPickable == true)
        XCTAssertFalse(field.unserved?[1].isPickable == true)

        // 对齐 upstream commit 7b5ca963：推理档从低到高排列，已持有的非候选值插入其对应位置
        let options = [
            ModelOption(value: "", label: "Default"),
            ModelOption(value: "high", label: "High"),
            ModelOption(value: "low", label: "Low")
        ]
        let ordered = ModelPickerView.orderedEffortOptions(options, currentValue: "max")
        XCTAssertEqual(ordered.map(\.value), ["", "low", "high", "max"])

        let orderedMiddle = ModelPickerView.orderedEffortOptions(options, currentValue: "medium")
        XCTAssertEqual(orderedMiddle.map(\.value), ["", "low", "medium", "high"])
    }

    func testDecodeRoutingStrategiesAndTraceExtensions() throws {
        XCTAssertTrue(GroupRouting.editable.contains(where: { $0.id == "fit" }))
        XCTAssertTrue(GroupRouting.editable.contains(where: { $0.id == "expiring" }))
        XCTAssertTrue(GroupRouting.editable.contains(where: { $0.id == "drain" }))
        XCTAssertFalse(GroupRouting.keyOverrides.contains(where: { $0.id == "manual" }))

        let routeJSON = """
        {
          "id": 42,
          "model": "group/main",
          "provider": "openai",
          "done": true,
          "status": 200,
          "tries": [
            {"id": "seat-1", "model": "gpt-5", "wire": "gpt-5-2026-11", "ms": 420, "ttft": 110}
          ],
          "order": [
            {
              "id": "seat-1",
              "provider": "openai",
              "model": "gpt-5",
              "fast": true,
              "ultra": true,
              "context": 200000,
              "lateTtft": 320.5,
              "lateTps": 85.4
            }
          ]
        }
        """.data(using: .utf8)!

        let route = try JSONDecoder().decode(GatewayRouteDTO.self, from: routeJSON)
        XCTAssertEqual(route.effectiveWireModel, "gpt-5-2026-11")
        XCTAssertEqual(route.tries?.first?.id, "seat-1")
        XCTAssertEqual(route.tries?.first?.millis, 420)
        XCTAssertEqual(route.tries?.first?.ttft, 110)
        let seat = try XCTUnwrap(route.order?.first)
        XCTAssertEqual(seat.ultra, true)
        XCTAssertEqual(seat.context, 200000)
        XCTAssertEqual(seat.lateTps, 85.4)
    }

    func testDecodeGatewayAccountWindowLimitAndKeyOverrides() throws {
        let keysJSON = """
        {
          "keys": [
            {
              "id": "k_mem",
              "name": "Remote Agent",
              "memory": true,
              "routing": "fit",
              "limit": {
                "period": "account",
                "account": "claude:alice",
                "accountWindow": "5h",
                "tokens": 500000
              }
            }
          ]
        }
        """.data(using: .utf8)!

        let keys = try JSONDecoder().decode(GatewayKeysResponseDTO.self, from: keysJSON)
        let key = try XCTUnwrap(keys.keys.first)
        XCTAssertEqual(key.memory, true)
        XCTAssertEqual(key.routing, "fit")
        XCTAssertEqual(key.limit?.period, "account")
        XCTAssertEqual(key.limit?.account, "claude:alice")
        XCTAssertEqual(key.limit?.accountWindow, "5h")

        let winJSON = """
        {
          "windows": [
            {"account": "claude:alice", "window": "5h", "provider": "claude", "user": "alice@example.com"}
          ]
        }
        """.data(using: .utf8)!
        let wins = try JSONDecoder().decode(GatewayAccountWindowsResponseDTO.self, from: winJSON)
        XCTAssertEqual(wins.windows.count, 1)
        XCTAssertEqual(wins.windows[0].id, "claude:alice|5h")
    }

    func testDecodeProviderEgressRelayCheckAndWithdrawn() throws {
        let provJSON = """
        {
          "providers": [
            {
              "id": "claude",
              "name": "Claude",
              "egress": {"state": "unsupported", "loc": "HK", "via": "direct"},
              "proxyGone": "old-vps",
              "topUpRate": 7.2,
              "embedIds": ["text-embedding-3-small"],
              "rerankIds": ["rerank-v3"],
              "models": [
                {"id": "claude-sonnet-4-6", "disabled": "*sonnet*"}
              ],
              "keyList": [
                {"id": "k1", "masked": "sk-...", "rest": {"why": "rate limit", "notice": true}}
              ]
            }
          ],
          "withdrawn": [
            {"id": "old-agy", "name": "Old Antigravity", "instead": "agy-cli"}
          ]
        }
        """.data(using: .utf8)!

        let res = try JSONDecoder().decode(ProvidersResponseDTO.self, from: provJSON)
        let p = try XCTUnwrap(res.providers.first)
        XCTAssertTrue(p.egress?.isUnsupported == true)
        XCTAssertEqual(p.egress?.loc, "HK")
        XCTAssertEqual(p.proxyGone, "old-vps")
        XCTAssertEqual(p.topUpRate, 7.2)
        XCTAssertEqual(p.embedIds?.count, 1)
        XCTAssertEqual(p.rerankIds?.count, 1)
        XCTAssertEqual(p.models?.first?.disabled, "*sonnet*")
        XCTAssertEqual(p.keyList?.first?.rest?.notice, true)
        XCTAssertEqual(res.withdrawn?.first?.instead, "agy-cli")

        let relayJSON = """
        {
          "provider": "relay1",
          "model": "claude-sonnet-4-6",
          "parts": [
            {"kind": "chat", "ok": true, "match": true, "ms": 820, "ttft_ms": 210, "tps": 64.5, "served": "claude-sonnet-4-6"}
          ]
        }
        """.data(using: .utf8)!
        let relay = try JSONDecoder().decode(RelayCheckResultDTO.self, from: relayJSON)
        XCTAssertEqual(relay.passedCount, 1)
        XCTAssertEqual(relay.parts.first?.ttftMs, 210)
    }

    func testDecodeUsageSpeedsSessionsSaidMaskingSearchAndSettingsSSHProxy() throws {
        let ledgerJSON = """
        {
          "total": 1,
          "rows": [
            {"id": 1, "model": "sonnet", "wire": "claude-sonnet-4-6-2026", "ttft_ms": 180, "ms": 950, "in": 100, "out": 50}
          ],
          "provider_speeds": [
            {"model": "sonnet", "name": "Sonnet", "provider": "anthropic", "provider_name": "Anthropic", "tries": 10, "failed": 1, "tps": 72.3, "ttft_ms": 220}
          ]
        }
        """.data(using: .utf8)!
        let ledger = try JSONDecoder().decode(UsageLedgerDTO.self, from: ledgerJSON)
        XCTAssertEqual(ledger.rows?.first?.wire, "claude-sonnet-4-6-2026")
        XCTAssertEqual(ledger.rows?.first?.ttft, 180)
        XCTAssertEqual(ledger.providerSpeeds?.first?.tries, 10)
        XCTAssertEqual(ledger.providerSpeeds?.first?.failed, 1)

        let saidJSON = """
        {
          "hits": [
            {
              "agent": "codex",
              "id": "s-1",
              "title": "Refactor auth",
              "hit": {"role": "user", "before": "please check ", "match": "mTLS", "after": " cert"}
            }
          ],
          "indexed": 10,
          "total": 10
        }
        """.data(using: .utf8)!
        let said = try JSONDecoder().decode(SessionSaidResponseDTO.self, from: saidJSON)
        XCTAssertEqual(said.hits.count, 1)
        XCTAssertEqual(said.hits[0].hit.match, "mTLS")

        let maskJSON = """
        {
          "records": [
            {"key": "101", "n": 2, "hits": ["[SECRET_1]"]}
          ],
          "more": false,
          "unknown": true
        }
        """.data(using: .utf8)!
        let mask = try JSONDecoder().decode(MaskingRecordsResponseDTO.self, from: maskJSON)
        XCTAssertEqual(mask.unknown, true)
        XCTAssertEqual(mask.records.first?.hits, ["[SECRET_1]"])

        let settingsJSON = """
        {
          "name": "Home Studio",
          "nameEnv": "STUDIO_ENV",
          "claudeRegionHold": true,
          "claudeNoExtraUsage": true,
          "imageResolution": "2K",
          "codexSuggestions": "openai/gpt-5-mini",
          "routerNoCode": true,
          "redactWordsAnyCase": true,
          "proxies": [
            {
              "id": "p1",
              "name": "Tokyo SSH",
              "url": "ssh://203.0.113.5:22",
              "user": "root",
              "hasKey": true,
              "hostKey": "ssh-ed25519 AAA",
              "uses": [
                {"where": "global"},
                {"provider": "claude", "account": "alice@example.com"}
              ],
              "check": {"ok": true, "ms": 48, "ip": "203.0.113.5", "loc": "JP"}
            }
          ]
        }
        """.data(using: .utf8)!
        let settings = try JSONDecoder().decode(SettingsDTO.self, from: settingsJSON)
        XCTAssertEqual(settings.name, "Home Studio")
        XCTAssertEqual(settings.claudeRegionHold, true)
        XCTAssertEqual(settings.imageResolution, "2K")
        XCTAssertEqual(settings.routerNoCode, true)
        let proxy = try XCTUnwrap(settings.proxies?.first)
        XCTAssertEqual(proxy.isSSH, true)
        XCTAssertEqual(proxy.hasKey, true)
        XCTAssertEqual(proxy.test?.ok, true)
        XCTAssertEqual(proxy.test?.loc, "JP")
        XCTAssertEqual(proxy.uses?.count, 2)
        XCTAssertEqual(proxy.uses?[1].displayLabel, "claude (alice@example.com)")

        // 验证 Settings 安全合并：保留兄弟字段、剥离只读 proxies、正确覆盖目标键
        let merged = try MagpieAPIClient.mergedSettingsBody(
            baseJSON: settingsJSON,
            key: "claudeRegionHold",
            value: false
        )
        let mergedObj = try XCTUnwrap(JSONSerialization.jsonObject(with: merged) as? [String: Any])
        XCTAssertEqual(mergedObj["claudeRegionHold"] as? Bool, false)
        XCTAssertEqual(mergedObj["name"] as? String, "Home Studio")
        XCTAssertEqual(mergedObj["imageResolution"] as? String, "2K")
        XCTAssertNil(mergedObj["proxies"])

        // 验证 UsageGroupDTO 中位速度计算（对齐 upstream speedHist.median）
        let groupHistJSON = """
        {"id": "m1", "model": "sonnet", "decode_n": 3, "rates": {"s": {"632": 3}}}
        """.data(using: .utf8)!
        let groupHist = try JSONDecoder().decode(UsageGroupDTO.self, from: groupHistJSON)
        let medianTPS = try XCTUnwrap(groupHist.effectiveTPS)
        XCTAssertGreaterThan(medianTPS, 95.0)
        XCTAssertLessThan(medianTPS, 105.0)

        let groupSingleJSON = """
        {"id": "m2", "model": "opus", "decode_n": 1, "decode_out": 500, "decode_ms": 5000}
        """.data(using: .utf8)!
        let groupSingle = try JSONDecoder().decode(UsageGroupDTO.self, from: groupSingleJSON)
        XCTAssertEqual(try XCTUnwrap(groupSingle.effectiveTPS), 100.0, accuracy: 0.01)

        let updateJSON = """
        {"state": "found", "current": "0.2.0", "latest": "0.2.1", "channel": "stable", "run": 1700000000}
        """.data(using: .utf8)!
        let upd = try JSONDecoder().decode(UpdateStatusDTO.self, from: updateJSON)
        XCTAssertEqual(upd.current, "0.2.0")
        XCTAssertEqual(upd.latest, "0.2.1")
        XCTAssertTrue(upd.hasUpdate)
    }
}
