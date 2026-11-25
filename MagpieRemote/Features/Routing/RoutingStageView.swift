import SwiftUI

// MARK: - Web 原版 Routing 舞台 (.rt) 的 SwiftUI 复刻
//
// 原版结构：顶部说明（.rt-what / .rt-mode）→ 舞台（Agent 列、magpie 枢纽、
// 候选账号列、虚线流向）→ 底部解说与 KPI（.rt-cap / .rt-stats）。
// 窄屏按原版 max560 布局：Agent 与 magpie 并排，账号列表在下方。

struct RoutingStageCard: View {
    let route: GatewayRouteDTO?
    let routes: [GatewayRouteDTO]
    let requestsCount: Int
    let reroutedCount: Int
    let errorCount: Int
    let isHistory: Bool
    let masked: Bool
    let activeURL: URL?
    let filterStatus: RouteFilterStatus
    let onFilter: (RouteFilterStatus) -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var anchors: [String: CGRect] = [:]
    @State private var accountsExpanded = true
    @State private var appeared = false

    private var accounts: [GatewayWeighedDTO] { route?.order ?? [] }
    private var isLive: Bool { route?.isPending == true && !isHistory }

    private var stageAgents: [RoutingStageAgent] {
        var seen = Set<String>()
        var out: [RoutingStageAgent] = []
        for item in routes {
            guard let agent = item.agent, !agent.isEmpty, seen.insert(agent).inserted else { continue }
            out.append(RoutingStageAgent(id: agent, model: item.model))
            if out.count >= 3 { break }
        }
        if out.isEmpty, let agent = route?.agent, !agent.isEmpty {
            out.append(RoutingStageAgent(id: agent, model: route?.model))
        }
        return out
    }

    private var chosenAccountID: String? {
        accounts.first(where: { $0.fallback != true })?.id ?? accounts.first?.id
    }

    private var accent: Color {
        RoutingStagePalette.color(for: stageAgents.first?.id ?? "magpie")
    }

    private var agentWireColors: [String: Color] {
        var out: [String: Color] = [:]
        for (index, agent) in stageAgents.enumerated() {
            out["agent-\(index)"] = RoutingStagePalette.color(for: agent.id)
        }
        return out
    }

    /// 每帧都重新构造飞行路径会拖慢主线程；只在锚点或数据变化时计算一次。
    private var stageFlights: [RoutingFlight] {
        RoutingStageFliers.makeFlights(anchors: anchors, colors: agentWireColors, accent: accent)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                headline
                Text(modeText)
                    .font(.system(size: 12.5))
                    .foregroundStyle(MagpieTheme.textSecondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            stageLayout

            footer
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(MagpieTheme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(MagpieTheme.border, lineWidth: 1)
        )
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 6)
        .onAppear {
            withAnimation(.easeOut(duration: 0.35)) { appeared = true }
        }
    }

    // MARK: - 顶部说明

    private var headline: Text {
        let name = route?.group?.displayName
            ?? accounts.first(where: { $0.fallback != true })?.name
            ?? route?.provider
            ?? route?.agent
            ?? "magpie"
        return Text(name)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(MagpieTheme.textPrimary)
            + Text(headlineTail)
            .font(.system(size: 13))
            .foregroundColor(MagpieTheme.textMuted)
    }

    private var headlineTail: String {
        guard let route else { return String(localized: " · 等待下一次请求") }
        var parts: [String] = []
        if route.group != nil { parts.append(String(localized: "路由组")) }
        let onCount = route.group?.members?.count
            ?? accounts.filter { $0.fallback != true }.count
        if accounts.isEmpty {
            if route.isPending { parts.append(String(localized: "正在读取请求")) }
        } else {
            parts.append(onCount == 1
                ? String(localized: "启用 1 个")
                : String(localized: "启用 \(onCount) 个"))
        }
        if stageAgents.count > 1 {
            parts.append(String(localized: "\(stageAgents.count) 个 Agent 同时在发"))
        }
        return parts.isEmpty ? "" : " · " + parts.joined(separator: " · ")
    }

    private var strategyRaw: String {
        if let groupRouting = route?.group?.routing, !groupRouting.isEmpty {
            return groupRouting
        }
        if let accountRouting = accounts.first(where: { $0.fallback != true })?.routing, !accountRouting.isEmpty {
            return accountRouting
        }
        if let accountRouting = accounts.first?.routing, !accountRouting.isEmpty {
            return accountRouting
        }
        return "smart"
    }

    private var modeText: String {
        guard let route else {
            return String(localized: "实时读取网关的路由记录；下一次请求会在这里显示去向。")
        }
        if accounts.isEmpty {
            return route.isPending
                ? String(localized: "magpie 正在读取请求并决定去向。")
                : String(localized: "这次请求没有可用的账号或 Key。")
        }
        let onCount = route.group?.members?.count
            ?? accounts.filter { $0.fallback != true }.count
        if route.group == nil, onCount <= 1 {
            return String(localized: "这里只开了一个账号或 Key，路由没有可选的。在供应商的编辑页再开一个，路由方式就在下面的「多账号 / 多 Key」里设置。")
        }
        return RoutingStagePalette.strategyDescription(strategyRaw)
    }

    private var strategyShort: String? {
        RoutingStagePalette.strategyShort(strategyRaw)
    }

    private var hubSubtitle: String {
        let host: String
        if let url = activeURL {
            let name = url.host ?? "127.0.0.1"
            host = url.port.map { "\(name):\($0)" } ?? name
        } else {
            host = "127.0.0.1:3425"
        }
        if isHistory { return String(localized: "历史记录 · \(host)") }
        return isLive
            ? String(localized: "正在路由 · \(host)")
            : String(localized: "app 正在待命 · \(host)")
    }

    // MARK: - 舞台

    private var agentColumn: some View {
        VStack(spacing: 10) {
            if stageAgents.isEmpty {
                RoutingStageIdleNode(text: String(localized: "等待 Agent"))
            } else {
                ForEach(Array(stageAgents.enumerated()), id: \.element.id) { index, agent in
                    RoutingStageAgentNode(agent: agent, color: RoutingStagePalette.color(for: agent.id))
                        .routingStageAnchor("agent-\(index)")
                }
            }
        }
    }

    private var hubNode: some View {
        RoutingStageHubNode(subtitle: hubSubtitle, chip: strategyShort)
            .routingStageAnchor("hub")
    }

    private var accountsColumn: some View {
        RoutingStageAccountsColumn(
            group: route?.group,
            accounts: accounts,
            expanded: $accountsExpanded,
            masked: masked,
            chosenID: chosenAccountID,
            isPending: isLive,
            accent: accent
        )
        .routingStageAnchor("accounts")
    }

    @ViewBuilder
    private var stageLayout: some View {
        Group {
            if horizontalSizeClass == .regular {
                HStack(alignment: .top, spacing: 28) {
                    agentColumn.frame(width: 170)
                    hubNode.frame(width: 190)
                    accountsColumn
                }
                .padding(.vertical, 18)
            } else {
                VStack(spacing: 26) {
                    HStack(alignment: .center, spacing: 28) {
                        agentColumn.frame(maxWidth: .infinity)
                        hubNode.frame(maxWidth: .infinity)
                    }
                    accountsColumn.padding(.leading, 22)
                }
                .padding(.vertical, 16)
            }
        }
        .coordinateSpace(name: "routing-stage")
        .onPreferenceChange(RoutingStageAnchorKey.self) { newAnchors in
            // 布局稳定后 preference 会重复触发；不比较会形成无意义的更新循环。
            guard newAnchors != anchors else { return }
            anchors = newAnchors
        }
        .background(
            RoutingStageWires(
                anchors: anchors,
                colors: agentWireColors,
                accent: accent,
                animated: isLive && !reduceMotion
            )
            .allowsHitTesting(false)
        )
        .overlay {
            // 没有进行中的请求时不播放飞鸟，避免空闲页面持续重绘。
            if isLive && !reduceMotion {
                RoutingStageFliers(flights: stageFlights)
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: - 底部解说与 KPI

    private var footer: some View {
        VStack(spacing: 10) {
            Divider().overlay(MagpieTheme.border)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .bottom, spacing: 14) {
                    caption
                    Spacer(minLength: 6)
                    stats
                }
                VStack(alignment: .leading, spacing: 8) {
                    caption
                    HStack {
                        Spacer()
                        stats
                    }
                }
            }
        }
        .padding(.top, 10)
    }

    private var caption: some View {
        Text(RoutingFormat.decisionCaption(for: route))
            .font(.system(size: 12))
            .foregroundStyle(MagpieTheme.textSecondary)
            .lineSpacing(2)
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var stats: some View {
        HStack(spacing: 14) {
            stat(String(localized: "请求"), requestsCount, .all, MagpieTheme.textPrimary)
            stat(String(localized: "改写"), reroutedCount, .rerouted, MagpieTheme.textPrimary)
            stat(String(localized: "错误"), errorCount, .errors, errorCount > 0 ? MagpieTheme.red : MagpieTheme.textPrimary)
        }
    }

    private func stat(_ title: String, _ value: Int, _ status: RouteFilterStatus, _ color: Color) -> some View {
        Button {
            onFilter(status)
        } label: {
            VStack(alignment: .trailing, spacing: 0) {
                Text(RoutingStagePalette.count(value))
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(filterStatus == status ? color : MagpieTheme.textSecondary)
                Text(title)
                    .font(.system(size: 10))
                    .foregroundStyle(MagpieTheme.textMuted)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 舞台数据

struct RoutingStageAgent: Identifiable {
    let id: String
    let model: String?
}

enum RoutingStagePalette {
    // 原版 PALETTE：十二个同一明度的安静颜色，Claude 的陶土色排第一。
    private static let palette: [Color] = [
        Color(hex: "d97757"), Color(hex: "bd8638"), Color(hex: "a59234"),
        Color(hex: "849e4a"), Color(hex: "5aa66c"), Color(hex: "25a98f"),
        Color(hex: "00a6b0"), Color(hex: "2e9fc9"), Color(hex: "5e95d7"),
        Color(hex: "858ad7"), Color(hex: "a47fca"), Color(hex: "bb77b1")
    ]

    private static let known: [String: Int] = [
        "claude": 0, "codex": 9, "gemini": 7, "copilot": 10, "cursor": 5,
        "opencode": 2, "crush": 11, "goose": 3, "pi": 4, "omp": 11,
        "omo": 10, "dsh": 6, "commandcode": 1, "mimocode": 8, "deveco": 7
    ]

    static func color(for id: String) -> Color {
        let key = id.lowercased()
        let index: Int
        if let fixed = known[key] {
            index = fixed
        } else {
            var hash: UInt32 = 0
            for scalar in key.unicodeScalars {
                hash = hash &* 31 &+ scalar.value
            }
            index = Int(hash % UInt32(palette.count))
        }
        return palette[index % palette.count]
    }

    static func strategyShort(_ raw: String?) -> String? {
        switch raw {
        case "", nil, "smart": return String(localized: "额度")
        case "order": return String(localized: "按序")
        case "drain": return String(localized: "用完")
        case "rotate": return String(localized: "轮询")
        case "usage": return String(localized: "少用")
        case "pace": return String(localized: "到期")
        case "weight": return String(localized: "加权")
        case "free": return String(localized: "免费")
        case "fast", "fastest", "speed": return String(localized: "测速")
        case "cheap": return String(localized: "低价")
        case "expiring": return String(localized: "先到期")
        case "fit": return String(localized: "小窗")
        case "manual": return String(localized: "手动")
        default: return raw?.isEmpty == false ? raw : nil
        }
    }

    static func strategyDescription(_ raw: String?) -> String {
        switch raw {
        case "", nil, "smart":
            return String(localized: "额度优先：有余量的账号中额度最先重置的排第一，以免剩余额度在重置时作废。")
        case "order":
            return String(localized: "按序：按账号列表的顺序依次尝试，前面的账号不能应答时才往后走。")
        case "drain":
            return String(localized: "逐个用完：固定用完当前账号额度再切下一个，前面恢复也不抢回流量。")
        case "rotate":
            return String(localized: "轮询：在可用账号之间轮流分配请求，让每个账号的用量保持均衡。")
        case "usage":
            return String(localized: "少用优先：优先选择当前用量最低、余量最多的账号。")
        case "pace":
            return String(localized: "到期前用完：选择剩余额度与重置时间最匹配的账号，尽量不让额度闲置或提前用尽。")
        case "weight":
            return String(localized: "加权：按账号权重分配请求，权重高的账号承担更多调用。")
        case "free":
            return String(localized: "免费优先：优先使用不消耗配额或免费的成员。")
        case "fast", "fastest", "speed":
            return String(localized: "测速优先：优先选择最近首 token 与输出最快的账号。")
        case "cheap":
            return String(localized: "最低价优先：按当前价格与时段汇率选择最便宜的成员。")
        case "expiring":
            return String(localized: "免费额度先到期：先消耗即将重置或过期的免费额度，再用付费额度。")
        case "fit":
            return String(localized: "小上下文优先：选择能装下本次请求的最小上下文窗口模型，把大窗口留给长对话。")
        case "manual":
            return String(localized: "手动指定：所有请求固定发往选定成员。")
        default:
            return String(localized: "网关正在实时权衡账号，选择这次请求的去向。")
        }
    }

    static func contextShort(_ tokens: Int) -> String {
        if tokens >= 1_000_000 {
            let m = Double(tokens) / 1_000_000
            return m == m.rounded() ? "\(Int(m))M" : String(format: "%.1fM", m)
        }
        if tokens >= 1_000 {
            return "\(tokens / 1_000)K"
        }
        return "\(tokens)"
    }

    static func count(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        }
        if value >= 1_000 {
            return String(format: "%.1fK", Double(value) / 1_000)
        }
        return "\(value)"
    }

    static func amount(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(Int(value.rounded()))"
    }

    static func reset(_ raw: String) -> String? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = iso.date(from: raw)
        if date == nil {
            iso.formatOptions = [.withInternetDateTime]
            date = iso.date(from: raw)
        }
        guard let date else { return nil }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: date).day
        if let days, days >= 0, days <= 30 {
            return days == 0 ? String(localized: "今天") : String(localized: "\(days) 天后")
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: date)
    }
}

// MARK: - 舞台节点

private struct RoutingStageIdleNode: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(MagpieTheme.textMuted)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 8)
            .padding(.vertical, 14)
            .background(MagpieTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(MagpieTheme.border, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            )
    }
}

private struct RoutingStageAgentNode: View {
    let agent: RoutingStageAgent
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            MagpieIconView(icon: agent.id, name: agent.id, size: 26, cornerRadius: 6)
                .padding(.bottom, 3)

            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(agent.id)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MagpieTheme.textPrimary)
                    .lineLimit(1)
            }

            if let model = agent.model, !model.isEmpty {
                Text(model)
                    .font(.system(size: 11))
                    .foregroundStyle(MagpieTheme.textMuted)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(MagpieTheme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(MagpieTheme.border, lineWidth: 1)
        )
    }
}

private struct RoutingStageHubNode: View {
    let subtitle: String
    let chip: String?

    var body: some View {
        VStack(spacing: 2) {
            MagpieLogoView(size: 26, showText: false, isAnimated: false)
                .padding(.bottom, 3)

            Text("magpie")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(MagpieTheme.textPrimary)

            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(MagpieTheme.textMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            if let chip {
                Text(chip)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(MagpieTheme.card)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 1)
                    .background(MagpieTheme.textPrimary, in: Capsule())
                    .padding(.top, 5)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(MagpieTheme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(MagpieTheme.textPrimary, lineWidth: 1)
        )
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(MagpieTheme.cardSecondary)
        )
    }
}

// MARK: - 候选账号列

private struct RoutingStageAccountsColumn: View {
    let group: GatewayGroupRefDTO?
    let accounts: [GatewayWeighedDTO]
    @Binding var expanded: Bool
    let masked: Bool
    let chosenID: String?
    let isPending: Bool
    let accent: Color

    private var shown: [GatewayWeighedDTO] { accounts }
    private var chosenIndex: Int? {
        if let chosenID, let index = shown.firstIndex(where: { $0.id == chosenID }) { return index }
        return shown.firstIndex(where: { $0.fallback != true }) ?? shown.indices.first
    }

    var body: some View {
        VStack(spacing: 7) {
            if accounts.isEmpty {
                Text(String(localized: "等待网关的路由记录"))
                    .font(.system(size: 12))
                    .foregroundStyle(MagpieTheme.textMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(MagpieTheme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(MagpieTheme.border, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    )
            } else {
                if let group {
                    header(group)
                }
                if expanded {
                    ForEach(Array(shown.enumerated()), id: \.offset) { index, account in
                        RoutingStageAccountRow(
                            account: account,
                            masked: masked,
                            isOn: index == chosenIndex,
                            isLive: isPending && index == chosenIndex,
                            accent: accent
                        )
                        .routingStageAnchor("account-\(index)")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func header(_ group: GatewayGroupRefDTO) -> some View {
        HStack(spacing: 7) {
            MagpieIconView(
                icon: accounts.first?.icon ?? group.id,
                name: group.displayName,
                size: 18,
                cornerRadius: 4
            )

            Text(group.displayName)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(MagpieTheme.textPrimary)
                .lineLimit(1)

            Text(group.ref ?? accounts.first?.model ?? "")
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(MagpieTheme.textMuted)
                .lineLimit(1)
                .layoutPriority(-1)

            Spacer(minLength: 4)

            let groupRouting = group.routing ?? ""
            let accountRouting = accounts
                .first(where: { !($0.routing ?? "").isEmpty })?
                .routing
            let routing = groupRouting.isEmpty ? (accountRouting ?? "smart") : groupRouting
            if let strategy = RoutingStagePalette.strategyShort(routing) {
                Text(strategy)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(MagpieTheme.textSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .overlay(
                        Capsule().stroke(MagpieTheme.border, lineWidth: 1)
                    )
            }

            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(MagpieTheme.textMuted)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(MagpieTheme.cardSecondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(MagpieTheme.border, style: StrokeStyle(lineWidth: 1, dash: expanded ? [] : [4, 3]))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.snappy(duration: 0.2)) { expanded.toggle() }
            MagpieHaptics.light()
        }
    }
}

private struct RoutingStageAccountRow: View {
    let account: GatewayWeighedDTO
    let masked: Bool
    let isOn: Bool
    let isLive: Bool
    let accent: Color

    private var displayName: String {
        RoutingFormat.maskString(account.who ?? account.name ?? account.id, isMasked: masked)
    }

    private var statusText: String {
        if let why = account.why, !why.isEmpty { return why }
        if account.isResting { return account.restReason ?? String(localized: "休息中") }
        if account.aside == true { return String(localized: "本次未参与") }
        var parts: [String] = []
        if let used = account.used {
            if let amount = account.amount, let limit = account.limit {
                let unit = account.unit.map { " \($0)" } ?? ""
                parts.append("\(RoutingStagePalette.amount(amount))/\(RoutingStagePalette.amount(limit))\(unit)")
            }
            parts.append(String(localized: "剩余 \(max(0, 100 - Int(used.rounded())))%"))
            if let due = account.due, let reset = RoutingStagePalette.reset(due) {
                parts.append(String(localized: "\(reset)重置"))
            }
        } else if let balance = account.balance, !balance.isEmpty {
            parts.append(balance)
        }
        if let ctx = account.context, ctx > 0 {
            parts.append(String(localized: "窗口 \(RoutingStagePalette.contextShort(ctx))"))
        }
        if let tps = account.lateTps, tps > 0 {
            parts.append(String(format: "%.0f tok/s", tps))
        }
        if parts.isEmpty { return String(localized: "可用") }
        return parts.joined(separator: " · ")
    }

    private var statusColor: Color {
        if account.isResting { return MagpieTheme.red }
        if account.aside == true { return MagpieTheme.textMuted }
        return MagpieTheme.textMuted
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(isOn ? MagpieTheme.textPrimary : Color.clear)
                    .overlay(
                        Circle().stroke(
                            isOn ? MagpieTheme.textPrimary : MagpieTheme.textMuted.opacity(0.7),
                            lineWidth: 1.5
                        )
                    )
                    .frame(width: 8, height: 8)
                    .padding(.top, 4)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        MagpieIconView(
                            icon: account.icon ?? account.provider,
                            name: account.name ?? account.provider ?? "account",
                            size: 16,
                            cornerRadius: 4
                        )

                        Text(displayName)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(MagpieTheme.textPrimary)
                            .lineLimit(1)

                        if let plan = account.plan, !plan.isEmpty {
                            Text(plan)
                                .font(.system(size: 11))
                                .foregroundStyle(MagpieTheme.textMuted)
                                .lineLimit(1)
                        }

                        if let model = account.model, !model.isEmpty {
                            Text(model)
                                .font(.system(size: 9.5, design: .monospaced))
                                .foregroundStyle(MagpieTheme.textSecondary)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .fill(MagpieTheme.cardSecondary)
                                )
                                .lineLimit(1)
                        }

                        if account.ultra == true {
                            Text("ULTRA")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(MagpieTheme.purple)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(MagpieTheme.purple.opacity(0.14), in: Capsule())
                        } else if account.fast == true {
                            Text("FAST")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(MagpieTheme.cyan)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(MagpieTheme.cyan.opacity(0.14), in: Capsule())
                        }

                        if account.fallback == true {
                            Text(String(localized: "备选"))
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(MagpieTheme.textMuted)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .overlay(
                                    Capsule().stroke(MagpieTheme.border, lineWidth: 1)
                                )
                        }
                    }

                    if isLive {
                        Text(String(localized: "回答中…"))
                            .font(.system(size: 11.5))
                            .foregroundStyle(accent)
                    } else {
                        Text(statusText)
                            .font(.system(size: 11.5))
                            .foregroundStyle(statusColor)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 0)
            }

            if let used = account.used {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(MagpieTheme.cardSecondary)
                        Capsule()
                            .fill(isOn ? MagpieTheme.textPrimary : MagpieTheme.textMuted.opacity(0.55))
                            .frame(width: max(geo.size.width * min(max(used / 100, 0), 1), 2))
                    }
                }
                .frame(height: 3)
                .padding(.leading, 18)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(MagpieTheme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isOn ? MagpieTheme.textPrimary : MagpieTheme.border, lineWidth: isOn ? 1 : 0.8)
        )
        .opacity(account.aside == true ? 0.5 : 1)
    }
}

// MARK: - 舞台虚线

struct RoutingStageAnchorKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

extension View {
    func routingStageAnchor(_ id: String) -> some View {
        background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: RoutingStageAnchorKey.self,
                    value: [id: geo.frame(in: .named("routing-stage"))]
                )
            }
        )
    }
}

private struct RoutingStageWires: View {
    let anchors: [String: CGRect]
    let colors: [String: Color]
    let accent: Color
    let animated: Bool

    var body: some View {
        if animated {
            TimelineView(AnimationTimelineSchedule(minimumInterval: 1.0 / 10.0)) { timeline in
                canvas(phase: -CGFloat(timeline.date.timeIntervalSinceReferenceDate * 4))
            }
        } else {
            canvas(phase: 0)
        }
    }

    private func canvas(phase: CGFloat) -> some View {
        Canvas { context, _ in
            guard !anchors.isEmpty else { return }
            let style = StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [3, 5], dashPhase: phase)

            let hub = anchors["hub"]
            let accounts = anchors["accounts"]
            let agentKeys = anchors.keys
                .filter { $0.hasPrefix("agent-") }
                .sorted()

            if let hub {
                for key in agentKeys {
                    guard let agent = anchors[key] else { continue }
                    let start = CGPoint(x: agent.maxX, y: agent.midY)
                    let end = CGPoint(x: hub.minX, y: hub.midY)
                    var path = Path()
                    path.move(to: start)
                    path.addCurve(
                        to: end,
                        control1: CGPoint(x: start.x + (end.x - start.x) * 0.45, y: start.y),
                        control2: CGPoint(x: start.x + (end.x - start.x) * 0.55, y: end.y)
                    )
                    context.stroke(path, with: .color(colors[key] ?? accent), style: style)
                }
            }

            guard let hub, let accounts else { return }
            let accountKeys = anchors.keys
                .filter { $0.hasPrefix("account-") }
                .sorted()

            if accounts.minX < hub.midX {
                let laneX = accounts.minX - 10
                let lastY = accountKeys.compactMap { anchors[$0]?.midY }.max() ?? accounts.midY
                var trunk = Path()
                trunk.move(to: CGPoint(x: hub.midX, y: hub.maxY))
                trunk.addCurve(
                    to: CGPoint(x: laneX, y: hub.maxY + 16),
                    control1: CGPoint(x: hub.midX, y: hub.maxY + 10),
                    control2: CGPoint(x: laneX, y: hub.maxY + 6)
                )
                trunk.addLine(to: CGPoint(x: laneX, y: lastY))
                context.stroke(trunk, with: .color(accent.opacity(0.75)), style: style)

                for key in accountKeys {
                    guard let row = anchors[key] else { continue }
                    var stub = Path()
                    stub.move(to: CGPoint(x: laneX, y: row.midY))
                    stub.addLine(to: CGPoint(x: row.minX, y: row.midY))
                    context.stroke(stub, with: .color(accent.opacity(0.75)), style: style)
                }
            } else {
                for key in accountKeys {
                    guard let row = anchors[key] else { continue }
                    let start = CGPoint(x: hub.maxX, y: hub.midY)
                    let end = CGPoint(x: row.minX, y: row.midY)
                    var path = Path()
                    path.move(to: start)
                    path.addCurve(
                        to: end,
                        control1: CGPoint(x: start.x + 20, y: start.y),
                        control2: CGPoint(x: end.x - 20, y: end.y)
                    )
                    context.stroke(path, with: .color(accent.opacity(0.75)), style: style)
                }
            }
        }
    }
}

// MARK: - 飞舞的 magpie（沿虚线往返）

/// 在舞台虚线上飞行的小 magpie logo：出站从 Agent 飞向枢纽，再从枢纽飞向候选账号；
/// 返程从账号飞回枢纽。路径使用与虚线一致的控制点，鸟身随切线轻微倾斜。
private struct RoutingStageFliers: View {
    let flights: [RoutingFlight]

    static func makeFlights(
        anchors: [String: CGRect],
        colors: [String: Color],
        accent: Color
    ) -> [RoutingFlight] {
        guard let hub = anchors["hub"] else { return [] }
        var out: [RoutingFlight] = []

        let agentKeys = anchors.keys.filter { $0.hasPrefix("agent-") }.sorted()
        for (index, key) in agentKeys.enumerated() {
            guard let agent = anchors[key] else { continue }
            let start = CGPoint(x: agent.maxX, y: agent.midY)
            let end = CGPoint(x: hub.minX, y: hub.midY)
            let cubic = RoutingCubic(
                p0: start,
                p1: CGPoint(x: start.x + (end.x - start.x) * 0.45, y: start.y),
                p2: CGPoint(x: start.x + (end.x - start.x) * 0.55, y: end.y),
                p3: end
            )
            out.append(
                RoutingFlight(
                    id: "agent-\(index)",
                    segments: [cubic],
                    color: colors[key] ?? accent,
                    duration: 1.55,
                    delay: Double(index) * 0.42,
                    cycle: 2.35,
                    reversed: false
                )
            )
        }

        let accountKeys = anchors.keys.filter { $0.hasPrefix("account-") }.sorted()
        if let account = accountKeys.first.flatMap({ anchors[$0] }),
           let accounts = anchors["accounts"] {
            let start = CGPoint(x: hub.midX, y: hub.maxY)
            let laneX = accounts.minX - 10
            let rowEnd = CGPoint(x: account.minX, y: account.midY)
            let segments: [RoutingCubic]

            if accounts.minX < hub.midX {
                let curve = RoutingCubic(
                    p0: start,
                    p1: CGPoint(x: hub.midX, y: hub.maxY + 10),
                    p2: CGPoint(x: laneX, y: hub.maxY + 6),
                    p3: CGPoint(x: laneX, y: hub.maxY + 16)
                )
                segments = [
                    curve,
                    .line(from: curve.p3, to: CGPoint(x: laneX, y: account.midY)),
                    .line(from: CGPoint(x: laneX, y: account.midY), to: rowEnd)
                ]
            } else {
                segments = [
                    RoutingCubic(
                        p0: start,
                        p1: CGPoint(x: start.x, y: start.y + 24),
                        p2: CGPoint(x: rowEnd.x - 20, y: rowEnd.y),
                        p3: rowEnd
                    )
                ]
            }

            out.append(
                RoutingFlight(
                    id: "outbound",
                    segments: segments,
                    color: accent,
                    duration: 1.35,
                    delay: 0.55,
                    cycle: 2.9,
                    reversed: false
                )
            )
            out.append(
                RoutingFlight(
                    id: "inbound",
                    segments: segments,
                    color: accent.opacity(0.72),
                    duration: 1.35,
                    delay: 1.95,
                    cycle: 2.9,
                    reversed: true
                )
            )
        }

        return out
    }

    var body: some View {
        TimelineView(AnimationTimelineSchedule(minimumInterval: 1.0 / 15.0)) { timeline in
            let now = timeline.date.timeIntervalSinceReferenceDate
            ZStack(alignment: .topLeading) {
                ForEach(flights) { flight in
                    if let pose = flight.pose(at: now) {
                        flyingBird(flight: flight, pose: pose, now: now)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func flyingBird(flight: RoutingFlight, pose: RoutingFlightPose, now: TimeInterval) -> some View {
        let bob = CGFloat(sin(now * 9 + flight.delay * 5) * 1.4)
        let bank = max(min(pose.angle * 0.22, CGFloat.pi / 10), -CGFloat.pi / 10)
        let flapProg = (now + flight.delay).truncatingRemainder(dividingBy: 0.42) / 0.42

        return OriginalFlyingMagpie(color: flight.color, progress: flapProg, isReturn: flight.reversed)
            .scaleEffect(x: pose.dx >= 0 ? 1 : -1, y: 1)
            .rotationEffect(.radians(bank))
            .shadow(color: flight.color.opacity(0.38), radius: 3)
            .opacity(pose.opacity)
            .position(x: pose.point.x, y: pose.point.y + bob)
    }
}

private struct RoutingFlight: Identifiable {
    let id: String
    let segments: [RoutingCubic]
    let color: Color
    let duration: TimeInterval
    let delay: TimeInterval
    let cycle: TimeInterval
    let reversed: Bool

    func pose(at now: TimeInterval) -> RoutingFlightPose? {
        let local = ((now + delay).truncatingRemainder(dividingBy: cycle)) / duration
        guard local >= 0, local <= 1 else { return nil }
        let t = reversed ? 1 - local : local
        guard let current = point(at: t) else { return nil }
        let ahead = point(at: min(t + 0.012, 1)) ?? current
        let behind = point(at: max(t - 0.012, 0)) ?? current
        let dx = ahead.x - behind.x
        let dy = ahead.y - behind.y
        let fade = min(min(CGFloat(local) / 0.08, (1 - CGFloat(local)) / 0.08), 1)
        return RoutingFlightPose(
            point: current,
            angle: atan2(dy, dx),
            dx: dx,
            opacity: max(fade, 0)
        )
    }

    private func point(at t: CGFloat) -> CGPoint? {
        guard !segments.isEmpty else { return nil }
        let clamped = min(max(t, 0), 1)
        let scaled = clamped * CGFloat(segments.count)
        let index = min(Int(scaled), segments.count - 1)
        let local = scaled - CGFloat(index)
        return segments[index].point(at: local)
    }
}

private struct RoutingFlightPose {
    let point: CGPoint
    let angle: CGFloat
    let dx: CGFloat
    let opacity: CGFloat
}

private struct RoutingCubic {
    let p0: CGPoint
    let p1: CGPoint
    let p2: CGPoint
    let p3: CGPoint

    static func line(from: CGPoint, to: CGPoint) -> RoutingCubic {
        RoutingCubic(
            p0: from,
            p1: CGPoint(x: from.x + (to.x - from.x) / 3, y: from.y + (to.y - from.y) / 3),
            p2: CGPoint(x: from.x + (to.x - from.x) * 2 / 3, y: from.y + (to.y - from.y) * 2 / 3),
            p3: to
        )
    }

    func point(at t: CGFloat) -> CGPoint {
        let u = 1 - t
        let x = u * u * u * p0.x + 3 * u * u * t * p1.x + 3 * u * t * t * p2.x + t * t * t * p3.x
        let y = u * u * u * p0.y + 3 * u * u * t * p1.y + 3 * u * t * t * p2.y + t * t * t * p3.y
        return CGPoint(x: x, y: y)
    }
}

// MARK: - 原版 Web 路由飞鸟 (.rt-flier / routing.js / routing.css 1:1 对齐)

/// Web 原版 FLIER:
/// - 面向右侧，喙尖叼着当前请求的 packet 能量点（能量点中心与舞台虚线点 1:1 重合）
/// - 远侧翅膀与近侧翅膀自肩部按 rtflap 0.42s 周期真实扑动（scaleY: 1.0 -> -0.62，伴随 -8° 扇动倾角）
/// - 躯干、白色腹部、近侧翅膀白条纹与喙部 1:1 纯量级对齐 Web SVG
private struct OriginalFlyingMagpie: View {
    let color: Color
    let progress: Double // 0...1 (0.42s 周期)
    var isReturn: Bool = false

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)

            let p = min(max(CGFloat(progress), 0), 1)
            let (nearScaleY, nearSkew) = flapTransform(t: p)

            let farP = CGFloat((progress + 0.0714).truncatingRemainder(dividingBy: 1.0))
            let (farScaleY, farSkew) = flapTransform(t: farP)

            // 基础变换：内部 (x, y) 先平移 (-6.5, 3.2)，再放大 1.2 倍，并对齐到 center
            let baseTransform = CGAffineTransform(translationX: -6.5, y: 3.2)
                .concatenating(CGAffineTransform(scaleX: 1.2, y: 1.2))
                .concatenating(CGAffineTransform(translationX: center.x, y: center.y))

            // 1. 远侧翅膀 (.wing.far, opacity 0.45)
            let farShoulder = CGPoint(x: -11.5, y: -3.3)
            let farWingTransform = wingTransform(shoulder: farShoulder, scaleY: farScaleY, skew: farSkew)
                .concatenating(baseTransform)
            var farWingPath = Path()
            farWingPath.move(to: CGPoint(x: -14.5, y: -3.4))
            farWingPath.addCurve(to: CGPoint(x: -8.6, y: -18.6), control1: CGPoint(x: -16.5, y: -9.5), control2: CGPoint(x: -14.2, y: -15.0))
            farWingPath.addCurve(to: CGPoint(x: -9.2, y: -3.2), control1: CGPoint(x: -9.4, y: -12.6), control2: CGPoint(x: -9.6, y: -7.4))
            farWingPath.closeSubpath()
            context.fill(farWingPath.applying(farWingTransform), with: .color(color.opacity(0.45)))

            // 2. 尾巴 (.tail)
            var tailPath = Path()
            tailPath.move(to: CGPoint(x: -31.5, y: 3.1))
            tailPath.addLine(to: CGPoint(x: -18.6, y: -1.8))
            tailPath.addLine(to: CGPoint(x: -17.4, y: 1.2))
            tailPath.addLine(to: CGPoint(x: -30.8, y: 4.6))
            tailPath.closeSubpath()
            context.fill(tailPath.applying(baseTransform), with: .color(color))

            // 3. 躯干 (.body)
            var bodyPath = Path()
            bodyPath.addEllipse(in: CGRect(x: -12.2 - 7.6, y: -1.4 - 3.9, width: 15.2, height: 7.8))
            bodyPath.addEllipse(in: CGRect(x: -4.9 - 3.1, y: -3.7 - 3.1, width: 6.2, height: 6.2))
            bodyPath.move(to: CGPoint(x: -2.3, y: -4.8))
            bodyPath.addLine(to: CGPoint(x: 1.4, y: -3.3))
            bodyPath.addLine(to: CGPoint(x: -2.3, y: -2.2))
            bodyPath.closeSubpath()
            context.fill(bodyPath.applying(baseTransform), with: .color(color))

            // 4. 白色腹部 (.belly)
            var bellyPath = Path()
            bellyPath.addEllipse(in: CGRect(x: -12.8 - 4.3, y: 0.4 - 1.6, width: 8.6, height: 3.2))
            context.fill(bellyPath.applying(baseTransform), with: .color(MagpieTheme.card))

            // 5. 近侧翅膀 (.wing.near)
            let nearShoulder = CGPoint(x: -12.0, y: -3.0)
            let nearWingTransform = wingTransform(shoulder: nearShoulder, scaleY: nearScaleY, skew: nearSkew)
                .concatenating(baseTransform)

            var nearWingPath = Path()
            nearWingPath.move(to: CGPoint(x: -15.6, y: -3.2))
            nearWingPath.addCurve(to: CGPoint(x: -8.4, y: -20.4), control1: CGPoint(x: -17.8, y: -10.2), control2: CGPoint(x: -15.2, y: -16.4))
            nearWingPath.addCurve(to: CGPoint(x: -8.8, y: -2.8), control1: CGPoint(x: -9.3, y: -13.6), control2: CGPoint(x: -9.4, y: -7.8))
            nearWingPath.closeSubpath()
            context.fill(nearWingPath.applying(nearWingTransform), with: .color(color))

            var barPath = Path()
            barPath.move(to: CGPoint(x: -14.6, y: -5.6))
            barPath.addCurve(to: CGPoint(x: -10.4, y: -17.2), control1: CGPoint(x: -15.4, y: -10.4), control2: CGPoint(x: -13.8, y: -14.4))
            context.stroke(
                barPath.applying(nearWingTransform),
                with: .color(MagpieTheme.card),
                style: StrokeStyle(lineWidth: 1.3 * 1.2, lineCap: .round)
            )

            // 6. 喙尖能量球 (.pkt) - 中心正好在 center (0, 0)
            let dotRect = CGRect(x: center.x - 4.5, y: center.y - 4.5, width: 9, height: 9)
            if isReturn {
                context.fill(Path(ellipseIn: dotRect), with: .color(MagpieTheme.card))
                context.stroke(Path(ellipseIn: dotRect), with: .color(color), style: StrokeStyle(lineWidth: 2.25))
            } else {
                context.fill(Path(ellipseIn: dotRect), with: .color(color))
            }
        }
        .frame(width: 90, height: 44)
    }

    private func flapTransform(t: CGFloat) -> (scaleY: CGFloat, skew: CGFloat) {
        if t <= 0.55 {
            let u = t / 0.55
            let s = u * u * (3.0 - 2.0 * u)
            let scaleY = 1.0 - 1.62 * s
            let skew = (-8.0 * .pi / 180.0) * s
            return (scaleY, skew)
        } else {
            let u = (t - 0.55) / 0.45
            let s = u * u * (3.0 - 2.0 * u)
            let scaleY = -0.62 + 1.62 * s
            let skew = (-8.0 * .pi / 180.0) * (1.0 - s)
            return (scaleY, skew)
        }
    }

    private func wingTransform(shoulder: CGPoint, scaleY: CGFloat, skew: CGFloat) -> CGAffineTransform {
        CGAffineTransform(translationX: -shoulder.x, y: -shoulder.y)
            .concatenating(CGAffineTransform(a: 1.0, b: 0.0, c: tan(skew), d: scaleY, tx: 0.0, ty: 0.0))
            .concatenating(CGAffineTransform(translationX: shoulder.x, y: shoulder.y))
    }
}
