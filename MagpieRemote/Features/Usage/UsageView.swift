import SwiftUI
import Charts
import UIKit

/// Usage：对齐官方 Web 的分页结构 —— 总览、请求账本、会话、上下文。
/// 统计、账本、热力图、上下文全部来自 `/api/usage*`、`/api/sessions`、`/api/context`。
struct UsageView: View {
    @Environment(AppModel.self) private var app
    @AppStorage("magpie_mask_accounts") private var maskAccounts = false

    @State private var viewModel = UsageViewModel()
    @State private var isCheckingIn = false
    @State private var overviewSort = "tokens"
    @State private var heatMetric = "calls"
    @State private var selectedRequest: UsageLedgerRowDTO?
    @State private var showingClearConfirm = false
    @State private var exportPath: String?
    @State private var actionError: String?

    // 各种折叠状态
    @State private var isAgentsExpanded = true
    @State private var isModelsExpanded = true
    @State private var isAccountsExpanded = true
    @State private var isKeysExpanded = true
    @State private var isHeatmapExpanded = true

    private let periods: [(String, String)] = [
        ("today", String(localized: "今天")),
        ("last:24h", String(localized: "24 小时")),
        ("7d", String(localized: "7 天")),
        ("30d", String(localized: "30 天")),
        ("all", String(localized: "全部"))
    ]

    private var loadKey: String {
        "\(viewModel.tab.rawValue)|\(viewModel.period)"
    }

    var body: some View {
        MagpieNavigationContainer {
            ScrollView {
                VStack(spacing: 12) {
                    // 1. 顶部整合工具栏 (4 大视图 Tab 切换 + 时间周期与预估费用徽标)
                    usageNavHeader

                    if let error = viewModel.errorMessage {
                        errorBanner(error)
                    }

                    switch viewModel.tab {
                    case .overview:
                        overviewSection
                    case .requests:
                        requestsSection
                    case .sessions:
                        sessionsSection
                    case .context:
                        contextSection
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .padding(.bottom, 96)
            }
            .magpiePageBackground()
            .navigationTitle(String(localized: "Usage"))
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                // 1. 账号隐私打码开关 (与 Routing 统一)
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        maskAccounts.toggle()
                        MagpieHaptics.light()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: maskAccounts ? "eye.slash.fill" : "eye")
                                .font(.system(size: 12, weight: .semibold))
                            Text(maskAccounts ? String(localized: "已打码") : String(localized: "隐藏账号"))
                                .font(.system(size: 11.5, weight: .medium))
                        }
                        .foregroundStyle(maskAccounts ? MagpieTheme.accent : MagpieTheme.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(maskAccounts ? MagpieTheme.accent.opacity(0.14) : MagpieTheme.card)
                        )
                        .overlay(
                            Capsule()
                                .stroke(maskAccounts ? MagpieTheme.accent.opacity(0.3) : MagpieTheme.borderSubtle, lineWidth: 0.8)
                        )
                    }
                    .accessibilityLabel(String(localized: "截图脱敏模式"))
                }

                // 2. 更多操作菜单
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            if let client = app.client {
                                Task { await viewModel.reloadForTab(client: client) }
                            }
                        } label: {
                            Label(String(localized: "刷新"), systemImage: "arrow.clockwise")
                        }

                        Button {
                            exportLedger()
                        } label: {
                            Label(String(localized: "导出账本 CSV 到服务器…"), systemImage: "tablecells")
                        }

                        Button {
                            copyLedgerCSV()
                        } label: {
                            Label(String(localized: "复制账本 CSV"), systemImage: "doc.on.doc")
                        }

                        Divider()

                        Button(role: .destructive) {
                            showingClearConfirm = true
                        } label: {
                            Label(String(localized: "清除用量统计…"), systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .disabled(viewModel.isLoading || viewModel.isLedgerLoading || viewModel.isOperating)
                }
            }
            .confirmationDialog(
                String(localized: "清除全部用量统计？"),
                isPresented: $showingClearConfirm,
                titleVisibility: .visible
            ) {
                Button(String(localized: "清除"), role: .destructive) {
                    clearUsage()
                }
                Button(String(localized: "取消"), role: .cancel) {}
            } message: {
                Text(String(localized: "此前的调用将不再计入用量页与图表；账本文件仍保留在服务器上，Key 的预算仍按它们计数。"))
            }
            .alert(
                String(localized: "已导出"),
                isPresented: Binding(
                    get: { exportPath != nil },
                    set: { if !$0 { exportPath = nil } }
                )
            ) {
                Button(String(localized: "复制路径")) {
                    if let path = exportPath { UIPasteboard.general.string = path }
                    exportPath = nil
                }
                Button(String(localized: "完成"), role: .cancel) { exportPath = nil }
            } message: {
                Text(exportPath ?? "")
            }
            .alert(
                String(localized: "操作失败"),
                isPresented: Binding(
                    get: { actionError != nil },
                    set: { if !$0 { actionError = nil } }
                )
            ) {
                Button(String(localized: "好"), role: .cancel) { actionError = nil }
            } message: {
                Text(actionError ?? "")
            }
            .task(id: loadKey) {
                guard let client = app.client else { return }
                await viewModel.reloadForTab(client: client)
                if viewModel.tab == .requests {
                    viewModel.startTraffic(client: client)
                } else {
                    viewModel.stopTraffic()
                }
            }
            .onDisappear {
                viewModel.stopTraffic()
            }
            .refreshable {
                if let client = app.client {
                    await viewModel.reloadForTab(client: client)
                }
            }
            .overlay {
                if viewModel.isLoading && viewModel.usage == nil && viewModel.tab == .overview {
                    ProgressView(String(localized: "正在统计用量…"))
                }
            }
            .sheet(item: $selectedRequest) { row in
                UsageRequestDetailSheet(row: row, isMasked: maskAccounts)
            }
        }
    }

    // MARK: - 工具动作
    private func clearUsage() {
        guard let client = app.client else { return }
        Task {
            if await viewModel.clearUsage(client: client) {
                MagpieHaptics.success()
            } else {
                actionError = viewModel.errorMessage ?? String(localized: "清除失败")
            }
        }
    }

    private func exportLedger() {
        guard let client = app.client else { return }
        Task {
            if let result = await viewModel.exportLedger(client: client) {
                exportPath = result.path ?? String(localized: "已导出 \(result.rows ?? 0) 行")
                MagpieHaptics.success()
            } else {
                actionError = viewModel.errorMessage ?? String(localized: "导出失败")
            }
        }
    }

    private func copyLedgerCSV() {
        guard let client = app.client else { return }
        Task {
            if let csv = await viewModel.fetchLedgerCSV(client: client), !csv.isEmpty {
                UIPasteboard.general.string = csv
                MagpieHaptics.success()
            } else {
                actionError = viewModel.errorMessage ?? String(localized: "读取 CSV 失败")
            }
        }
    }

    // MARK: - 整合顶部导航与工具栏 (Usage Nav Header)
    private var usageNavHeader: some View {
        VStack(spacing: 8) {
            // 行 1: 4 大视图 Tab 切换条 (总览 / 请求 / 会话 / 上下文)
            HStack(spacing: 4) {
                ForEach(UsageViewModel.UsageTab.allCases) { item in
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                            viewModel.tab = item
                        }
                        MagpieHaptics.light()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: item.icon)
                                .font(.system(size: 10, weight: .semibold))
                            Text(item.title)
                                .font(.system(size: 11.5, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(viewModel.tab == item ? MagpieTheme.card : Color.clear)
                        )
                        .foregroundStyle(viewModel.tab == item ? MagpieTheme.textPrimary : MagpieTheme.textMuted)
                        .shadow(color: viewModel.tab == item ? Color.black.opacity(0.06) : Color.clear, radius: 3, x: 0, y: 1.5)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(2.5)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(MagpieTheme.pill)
            )

            // 行 2: 时间周期选择胶囊 + 预估费用微徽标与单点刷新
            HStack(spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(periods, id: \.0) { item in
                            Button {
                                viewModel.period = item.0
                                MagpieHaptics.light()
                            } label: {
                                Text(item.1)
                                    .font(.system(size: 11, weight: .semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4.5)
                                    .background(viewModel.period == item.0 ? MagpieTheme.accent : MagpieTheme.pill, in: Capsule())
                                    .foregroundStyle(viewModel.period == item.0 ? .white : MagpieTheme.textSecondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .scrollClipDisabled()

                Spacer(minLength: 4)

                // 预估费用微徽标与刷新按钮
                HStack(spacing: 4) {
                    if let usage = viewModel.usage {
                        HStack(spacing: 2) {
                            Text("≈")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(MagpieTheme.green)
                            Text(usage.formattedCost)
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(MagpieTheme.green)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3.5)
                        .background(MagpieTheme.greenSoft, in: Capsule())
                    }

                    Button {
                        if let client = app.client {
                            Task { await viewModel.reloadForTab(client: client) }
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(MagpieTheme.textMuted)
                            .padding(5)
                            .background(MagpieTheme.pill, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isLoading)
                }
            }
        }
    }

    // MARK: - 总览 (Overview)
    @ViewBuilder
    private var overviewSection: some View {
        if let usage = viewModel.usage {
            // 1. 订阅配额卡片优先展示 (Web Allowances 官方最前列！)
            if !viewModel.quotas.isEmpty {
                quotasSection
            }

            // 2. 4大核心指标看板
            metricsGrid(usage)

            // 3. Token 构成与分布图表
            tokenChartCard(usage)

            // 4. 多维折叠明细列表 (Agents, Models, Accounts, Gateway Keys)
            if let groups = usage.agents, !groups.isEmpty {
                groupCard(
                    String(localized: "Agents"),
                    icon: "terminal.fill",
                    tint: MagpieTheme.accent,
                    groups: groups,
                    isExpanded: $isAgentsExpanded
                )
            }
            if let groups = usage.models, !groups.isEmpty {
                groupCard(
                    String(localized: "Models"),
                    icon: "cpu.fill",
                    tint: MagpieTheme.purple,
                    groups: groups,
                    isExpanded: $isModelsExpanded
                )
            }
            if let groups = usage.accounts, !groups.isEmpty {
                groupCard(
                    String(localized: "账号"),
                    icon: "person.crop.circle.fill",
                    tint: MagpieTheme.cyan,
                    groups: groups,
                    isExpanded: $isAccountsExpanded
                )
            }
            if let groups = usage.callerKeys, !groups.isEmpty {
                groupCard(
                    String(localized: "Gateway Keys"),
                    icon: "key.fill",
                    tint: MagpieTheme.amber,
                    groups: groups,
                    isExpanded: $isKeysExpanded
                )
            }
        } else if viewModel.isLoading {
            ProgressView().padding(.vertical, 40)
        } else {
            emptyState(
                icon: "chart.bar.xaxis",
                title: String(localized: "暂无用量统计"),
                subtitle: String(localized: "发起几次 Agent 调用后，用量统计将在此实时更新。")
            )
        }
    }

    private var warmableAgents: [String] {
        var list: [String] = []
        if viewModel.quotas.contains(where: { $0.provider == "codex" }) { list.append("codex") }
        if viewModel.quotas.contains(where: { $0.provider == "claude" }) { list.append("claude") }
        return list
    }

    // MARK: - 配额与余量卡片 (Web 1:1 Allowances / Quotas)
    private var quotasSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                MagpieSectionLabel(title: String(localized: "订阅额度与余量"), detail: String(localized: "\(viewModel.quotas.count) 个账户"))
                Spacer()
                if viewModel.isWarmingAll {
                    ProgressView().controlSize(.small)
                } else if warmableAgents.count > 1 {
                    Menu {
                        Button(String(localized: "预热全部 (Codex + Claude)")) {
                            if let client = app.client {
                                Task { await viewModel.warmAll(client: client, agents: warmableAgents) }
                            }
                        }
                        Button(String(localized: "仅预热 Codex")) {
                            if let client = app.client {
                                Task { await viewModel.warmAll(client: client, agents: ["codex"]) }
                            }
                        }
                        Button(String(localized: "仅预热 Claude")) {
                            if let client = app.client {
                                Task { await viewModel.warmAll(client: client, agents: ["claude"]) }
                            }
                        }
                    } label: {
                        Label(String(localized: "预热账号"), systemImage: "flame.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(MagpieTheme.amber)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3.5)
                            .background(MagpieTheme.amber.opacity(0.14), in: Capsule())
                    }
                } else if let onlyAgent = warmableAgents.first {
                    Button {
                        if let client = app.client {
                            Task { await viewModel.warmAll(client: client, agents: [onlyAgent]) }
                        }
                    } label: {
                        Label(String(localized: "预热账号"), systemImage: "flame.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(MagpieTheme.amber)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3.5)
                            .background(MagpieTheme.amber.opacity(0.14), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                if viewModel.isRefreshingQuota {
                    ProgressView().controlSize(.small)
                }
            }

            if let warmMsg = viewModel.warmAllMessage {
                Text(warmMsg)
                    .font(.caption)
                    .foregroundStyle(MagpieTheme.textSecondary)
            }

            VStack(spacing: 8) {
                ForEach(Array(viewModel.quotas.enumerated()), id: \.offset) { _, quota in
                    quotaCard(quota)
                }
            }
        }
    }

    private func quotaSubtitle(_ quota: QuotaItemDTO) -> String {
        guard let user = quota.user, !user.isEmpty else { return quota.provider }
        return "\(quota.provider) · \(RoutingFormat.maskString(user, isMasked: maskAccounts))"
    }

    private func quotaCard(_ quota: QuotaItemDTO) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                MagpieIconView(icon: quota.icon ?? quota.provider, name: quota.name, size: 24, cornerRadius: 6)

                VStack(alignment: .leading, spacing: 1) {
                    Text(RoutingFormat.maskString(quota.name, isMasked: maskAccounts))
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundStyle(MagpieTheme.textPrimary)
                        .lineLimit(1)

                    Text(quotaSubtitle(quota))
                        .font(.system(size: 9.5))
                        .foregroundStyle(MagpieTheme.textMuted)
                }

                Spacer(minLength: 4)

                // 快捷刷新单项配额
                Button {
                    if let client = app.client {
                        Task { await viewModel.refreshQuota(client: client, provider: quota.provider) }
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(MagpieTheme.textMuted)
                }
                .buttonStyle(.plain)
            }

            if let readError = quota.readError, !readError.isEmpty {
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9.5))
                    Text(readError)
                        .font(.system(size: 10))
                        .lineLimit(2)
                }
                .foregroundStyle(MagpieTheme.amber)
            }

            if let balance = quota.balance, !balance.isEmpty {
                HStack(spacing: 3) {
                    Text(String(localized: "余额:"))
                        .font(.system(size: 9.5))
                        .foregroundStyle(MagpieTheme.textMuted)
                    Text(balance)
                        .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(MagpieTheme.green)
                }
            }

            if let windows = quota.windows, !windows.isEmpty {
                VStack(spacing: 5) {
                    ForEach(Array(windows.enumerated()), id: \.offset) { _, win in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(win.name)
                                    .font(.system(size: 9))
                                    .foregroundStyle(MagpieTheme.textSecondary)
                                    .lineLimit(1)
                                Spacer()
                                Text(String(format: "%.0f%%", win.percentUsed))
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundStyle(win.percentUsed > 80 ? MagpieTheme.amber : MagpieTheme.accent)
                            }

                            // 进度槽
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                                        .fill(MagpieTheme.pill)
                                        .frame(height: 3.5)

                                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                                        .fill(win.percentUsed > 80 ? MagpieTheme.amber.gradient : MagpieTheme.accent.gradient)
                                        .frame(width: max(geo.size.width * CGFloat(min(win.percentUsed / 100.0, 1.0)), 2), height: 3.5)
                                }
                            }
                            .frame(height: 3.5)

                            if let reset = win.resetsAt, !reset.isEmpty {
                                Text("重置: \(reset)")
                                    .font(.system(size: 8))
                                    .foregroundStyle(MagpieTheme.textMuted)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MagpieTheme.card)
        .magpieLiquidSurface(cornerRadius: 14)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(MagpieTheme.borderSubtle, lineWidth: 0.8)
        )
    }

    // MARK: - 4大核心指标看板 (Metrics Grid)
    private func metricsGrid(_ usage: UsageDTO) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                MetricCard(
                    title: String(localized: "Tokens 总计"),
                    value: UsageDTO.formatTokens(usage.totalTokens),
                    sub: "\(UsageDTO.formatTokens(usage.input ?? 0)) in · \(UsageDTO.formatTokens(usage.output ?? 0)) out",
                    icon: "number",
                    color: MagpieTheme.accent
                )
                MetricCard(
                    title: String(localized: "预估费用"),
                    value: usage.formattedCost,
                    sub: usage.unpriced == nil ? nil : String(localized: "\(usage.unpriced!) 未定价调用"),
                    icon: "dollarsign.circle.fill",
                    color: MagpieTheme.green
                )
            }

            HStack(spacing: 8) {
                MetricCard(
                    title: String(localized: "调用次数"),
                    value: usage.formattedCalls,
                    sub: (usage.errors ?? 0) > 0 ? String(localized: "\(usage.errors!) 报错 · \(usage.retried ?? 0) 重试") : String(localized: "全部成功"),
                    icon: "arrow.triangle.swap",
                    color: (usage.errors ?? 0) > 0 ? MagpieTheme.red : MagpieTheme.purple
                )

                let cacheSum = (usage.cache_read ?? 0) + (usage.cache_write ?? 0)
                MetricCard(
                    title: String(localized: "Prompt 缓存"),
                    value: UsageDTO.formatTokens(cacheSum),
                    sub: String(localized: "读取 \(UsageDTO.formatTokens(usage.cache_read ?? 0))"),
                    icon: "bolt.badge.clock.fill",
                    color: MagpieTheme.cyan
                )
            }
        }
    }

    // MARK: - 分类排行榜折叠面板
    private func groupCard(
        _ title: String,
        icon: String,
        tint: Color,
        groups: [UsageGroupDTO],
        isExpanded: Binding<Bool>
    ) -> some View {
        let sorted = sortedGroups(groups)
        let maxTokens = max(sorted.first?.totalTokens ?? 1, 1)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                        isExpanded.wrappedValue.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isExpanded.wrappedValue ? "chevron.down" : "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(MagpieTheme.textMuted)

                        Image(systemName: icon)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(tint)

                        Text(title)
                            .font(.system(size: 13.5, weight: .bold))
                            .foregroundStyle(MagpieTheme.textPrimary)

                        Text("(\(groups.count))")
                            .font(.caption2)
                            .foregroundStyle(MagpieTheme.textMuted)
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                if isExpanded.wrappedValue {
                    Menu {
                        Picker(String(localized: "排序"), selection: $overviewSort) {
                            Text(String(localized: "按 Tokens")).tag("tokens")
                            Text(String(localized: "按费用")).tag("cost")
                            Text(String(localized: "按调用数")).tag("calls")
                            Text(String(localized: "按名称")).tag("name")
                        }
                    } label: {
                        HStack(spacing: 2) {
                            Text(sortTitle)
                            Image(systemName: "arrow.up.arrow.down")
                                .font(.system(size: 8, weight: .bold))
                        }
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(MagpieTheme.textMuted)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(MagpieTheme.pill, in: Capsule())
                    }
                }
            }

            if isExpanded.wrappedValue {
                VStack(spacing: 0) {
                    ForEach(Array(sorted.prefix(10).enumerated()), id: \.offset) { item in
                        let index = item.offset
                        let group = item.element
                        let ratio = min(max(Double(group.totalTokens) / Double(maxTokens), 0.05), 1.0)

                        VStack(spacing: 6) {
                            HStack(spacing: 10) {
                                MagpieIconView(icon: group.icon ?? group.provider, name: group.displayName, size: 28, cornerRadius: 7)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(RoutingFormat.maskString(group.displayName, isMasked: maskAccounts))
                                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                                        .foregroundStyle(MagpieTheme.textPrimary)
                                        .lineLimit(1)
                                    if let sub = group.sub, !sub.isEmpty {
                                        Text(RoutingFormat.maskString(sub, isMasked: maskAccounts))
                                            .font(.caption2)
                                            .foregroundStyle(MagpieTheme.textMuted)
                                            .lineLimit(1)
                                    }
                                }

                                Spacer(minLength: 4)

                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(UsageDTO.formatTokens(group.totalTokens))
                                        .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                                        .foregroundStyle(MagpieTheme.textPrimary)
                                    HStack(spacing: 4) {
                                        Text("\(group.calls ?? 0) 次 · \(group.formattedCost)")
                                        if let tps = group.effectiveTPS, tps > 0 {
                                            Text(String(format: "· %.0f tok/s", tps))
                                                .foregroundStyle(MagpieTheme.cyan)
                                        }
                                    }
                                    .font(.caption2)
                                    .foregroundStyle(MagpieTheme.textMuted)
                                }
                            }

                            // 占比进度条 (Web 对齐)
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                                        .fill(MagpieTheme.pill)
                                        .frame(height: 3)

                                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                                        .fill(tint.gradient)
                                        .frame(width: geo.size.width * ratio, height: 3)
                                }
                            }
                            .frame(height: 3)
                            .padding(.leading, 38)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)

                        if index < min(sorted.count, 10) - 1 {
                            Divider()
                                .background(MagpieTheme.borderSubtle)
                                .padding(.leading, 48)
                        }
                    }
                }
                .magpieCard(padding: 0)
            }
        }
    }

    private var sortTitle: String {
        switch overviewSort {
        case "cost": return String(localized: "费用")
        case "calls": return String(localized: "调用")
        case "name": return String(localized: "名称")
        default: return String(localized: "Tokens")
        }
    }

    private func sortedGroups(_ groups: [UsageGroupDTO]) -> [UsageGroupDTO] {
        groups.sorted { a, b in
            switch overviewSort {
            case "cost":
                return (a.cost ?? 0) > (b.cost ?? 0)
            case "calls":
                return (a.calls ?? 0) > (b.calls ?? 0)
            case "name":
                return a.displayName.localizedStandardCompare(b.displayName) == .orderedAscending
            default:
                return a.totalTokens > b.totalTokens
            }
        }
    }

    private func tokenChartCard(_ usage: UsageDTO) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            MagpieSectionLabel(title: String(localized: "Token 构成分布"))

            VStack(alignment: .leading, spacing: 12) {
                TokenDistributionChart(usage: usage)
                    .frame(height: 130)

                HStack {
                    legendItem(color: MagpieTheme.amber, label: String(localized: "输入"), value: usage.input ?? 0)
                    Spacer()
                    legendItem(color: MagpieTheme.purple, label: String(localized: "输出"), value: usage.output ?? 0)
                    Spacer()
                    legendItem(color: MagpieTheme.cyan, label: String(localized: "缓存读取"), value: usage.cache_read ?? 0)
                    Spacer()
                    legendItem(color: MagpieTheme.textSecondary, label: String(localized: "缓存写入"), value: usage.cache_write ?? 0)
                }
            }
            .magpieCard()
        }
    }

    private func legendItem(color: Color, label: String, value: Int) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(MagpieTheme.textMuted)
                Text(UsageDTO.formatTokens(value))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MagpieTheme.textPrimary)
            }
        }
    }

    // MARK: - 请求账本 (Requests / Ledger 官方核心对齐！)
    private var requestsSection: some View {
        VStack(spacing: 14) {
            // 实时网络吞吐条
            if !viewModel.trafficText.isEmpty {
                HStack(spacing: 6) {
                    MagpiePulseDot(color: MagpieTheme.green)
                    Text(viewModel.trafficText)
                        .font(.system(size: 11, design: .monospaced))
                    Spacer()
                    Text(String(localized: "实时流量"))
                        .font(.system(size: 9.5, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(MagpieTheme.greenSoft)
                        .foregroundStyle(MagpieTheme.green)
                        .clipShape(Capsule())
                }
                .foregroundStyle(MagpieTheme.textMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .magpieCard(padding: 10)
            }

            // 1. Web 1:1 对齐的核心 KPI 综合统计条 (renderLedgerDash)
            ledgerKpiStrip

            // 2. 筛选与搜索工具条 (Sess Tools)
            requestFilters

            // 3. 53 周日历用量热力图 (可折叠)
            heatmapCard

            // 3.5 提供方与模型测速统计（upstream provider_speeds）
            if let speeds = viewModel.ledger?.providerSpeeds, !speeds.isEmpty {
                providerSpeedsCard(speeds)
            }

            // 4. 账本流水请求列表
            ledgerList
        }
    }

    private func providerSpeedsCard(_ speeds: [UsageProviderSpeedDTO]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            MagpieSectionLabel(
                title: String(localized: "模型与提供方实测速度"),
                detail: "\(speeds.count)"
            )
            VStack(spacing: 0) {
                ForEach(Array(speeds.prefix(12).enumerated()), id: \.element.id) { index, item in
                    HStack(spacing: 10) {
                        MagpieIconView(icon: item.icon ?? item.provider, name: item.displayProvider, size: 24, cornerRadius: 6)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.displayName)
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundStyle(MagpieTheme.textPrimary)
                                .lineLimit(1)
                            HStack(spacing: 5) {
                                Text(RoutingFormat.maskString(item.displayProvider, isMasked: maskAccounts))
                                if let tries = item.tries, tries > 0 {
                                    Text("· \(tries) 次")
                                }
                                if let failed = item.failed, failed > 0 {
                                    Text(String(localized: "· \(failed) 失败"))
                                        .foregroundStyle(MagpieTheme.red)
                                }
                                if let swapped = item.swapped, swapped > 0 {
                                    Text(String(localized: "· \(swapped) 换型"))
                                        .foregroundStyle(MagpieTheme.amber)
                                }
                            }
                            .font(.caption2)
                            .foregroundStyle(MagpieTheme.textMuted)
                            .lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        VStack(alignment: .trailing, spacing: 2) {
                            if let tps = item.tps, tps > 0 {
                                Text(String(format: "%.1f tok/s", tps))
                                    .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                                    .foregroundStyle(MagpieTheme.cyan)
                            }
                            if let ttft = item.ttftMs, ttft > 0 {
                                Text("TTFT \(ttft)ms")
                                    .font(.system(size: 9.5, design: .monospaced))
                                    .foregroundStyle(MagpieTheme.textMuted)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                    if index < min(speeds.count, 12) - 1 {
                        Divider().background(MagpieTheme.borderSubtle).padding(.leading, 46)
                    }
                }
            }
            .magpieCard(padding: 0)
        }
    }

    // MARK: - 1:1 Web 对齐的 KPI 统计面板 (renderLedgerDash)
    private var ledgerKpiStrip: some View {
        let calls = viewModel.ledgerTotalCalls
        let errors = viewModel.ledgerErrorCalls
        let retried = viewModel.ledgerRetriedCalls
        let cost = viewModel.ledger?.cost ?? viewModel.usage?.cost
        let cacheHit = viewModel.ledgerCacheHitRate

        return VStack(spacing: 10) {
            // 第一排：Tokens 与 请求数
            HStack(spacing: 8) {
                // Tokens 卡片
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "Tokens"))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(MagpieTheme.textMuted)
                    Text(UsageDTO.formatTokens(viewModel.ledgerTotalTokens))
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundStyle(MagpieTheme.textPrimary)
                    Text("\(UsageDTO.formatTokens(viewModel.ledgerInputTokens)) in · \(UsageDTO.formatTokens(viewModel.ledgerOutputTokens)) out")
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(MagpieTheme.textMuted)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(MagpieTheme.card)
                .magpieLiquidSurface(cornerRadius: 12)

                // 请求数与成功率 (附带可点击过滤按钮)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(String(localized: "Requests"))
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(MagpieTheme.textMuted)
                        Spacer()
                        if let rate = viewModel.ledgerSuccessRate {
                            Text(String(format: String(localized: "%.1f%% 成功"), rate * 100))
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(MagpieTheme.green)
                        }
                    }

                    Text("\(calls)")
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundStyle(MagpieTheme.textPrimary)

                    HStack(spacing: 5) {
                        if errors > 0 {
                            Button {
                                viewModel.ledgerFailedOnly.toggle()
                                if viewModel.ledgerFailedOnly { viewModel.ledgerRetriedOnly = false }
                                applyFilters()
                            } label: {
                                Text("\(errors) 失败")
                                    .font(.system(size: 9.5, weight: .bold))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1.5)
                                    .background(viewModel.ledgerFailedOnly ? MagpieTheme.red : MagpieTheme.red.opacity(0.16))
                                    .foregroundStyle(viewModel.ledgerFailedOnly ? .white : MagpieTheme.red)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        } else {
                            Text(String(localized: "无报错"))
                                .font(.system(size: 9.5))
                                .foregroundStyle(MagpieTheme.green)
                        }

                        if retried > 0 {
                            Button {
                                viewModel.ledgerRetriedOnly.toggle()
                                if viewModel.ledgerRetriedOnly { viewModel.ledgerFailedOnly = false }
                                applyFilters()
                            } label: {
                                Text("\(retried) 重试")
                                    .font(.system(size: 9.5, weight: .bold))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1.5)
                                    .background(viewModel.ledgerRetriedOnly ? MagpieTheme.amber : MagpieTheme.amber.opacity(0.16))
                                    .foregroundStyle(viewModel.ledgerRetriedOnly ? .white : MagpieTheme.amber)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(MagpieTheme.card)
                .magpieLiquidSurface(cornerRadius: 12)
            }

            // 第二排：预估费用与缓存命中率
            HStack(spacing: 8) {
                // 预估花费
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "预估花费"))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(MagpieTheme.textMuted)
                    Text(cost != nil ? String(format: "$%.2f", cost!) : "—")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(MagpieTheme.green)
                    Text(String(localized: "有效定价模型"))
                        .font(.system(size: 9.5))
                        .foregroundStyle(MagpieTheme.textMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(MagpieTheme.card)
                .magpieLiquidSurface(cornerRadius: 12)

                // 缓存命中率 (带进度槽)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(String(localized: "缓存命中率"))
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(MagpieTheme.textMuted)
                        Spacer()
                        Text(cacheHit != nil ? String(format: "%.1f%%", cacheHit! * 100) : "—")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(MagpieTheme.cyan)
                    }

                    ProgressView(value: min(cacheHit ?? 0.0, 1.0), total: 1.0)
                        .tint(MagpieTheme.cyan)
                        .padding(.vertical, 2)

                    Text(String(localized: "Prompt 缓存复用率"))
                        .font(.system(size: 9.5))
                        .foregroundStyle(MagpieTheme.textMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(MagpieTheme.card)
                .magpieLiquidSurface(cornerRadius: 12)
            }
        }
    }

    // MARK: - 筛选工具条
    private var requestFilters: some View {
        VStack(spacing: 9) {
            // 搜索框
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(MagpieTheme.textMuted)
                TextField(String(localized: "搜索模型、提供方、会话…"), text: $viewModel.ledgerQuery)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit { applyFilters() }
                if !viewModel.ledgerQuery.isEmpty {
                    Button {
                        viewModel.ledgerQuery = ""
                        applyFilters()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(MagpieTheme.textMuted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .background(MagpieTheme.card.opacity(0.7), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(MagpieTheme.borderSubtle, lineWidth: 0.8)
            )

            // 快捷药丸筛选横轴
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    // 全部
                    filterChip(
                        String(localized: "全部"),
                        active: !viewModel.ledgerFailedOnly && !viewModel.ledgerRetriedOnly,
                        tint: MagpieTheme.accent
                    ) {
                        viewModel.ledgerFailedOnly = false
                        viewModel.ledgerRetriedOnly = false
                        applyFilters()
                    }

                    // 仅失败
                    filterChip(
                        String(localized: "仅失败"),
                        active: viewModel.ledgerFailedOnly,
                        tint: MagpieTheme.red
                    ) {
                        viewModel.ledgerFailedOnly.toggle()
                        if viewModel.ledgerFailedOnly { viewModel.ledgerRetriedOnly = false }
                        applyFilters()
                    }

                    // 仅重试
                    filterChip(
                        String(localized: "仅重试"),
                        active: viewModel.ledgerRetriedOnly,
                        tint: MagpieTheme.amber
                    ) {
                        viewModel.ledgerRetriedOnly.toggle()
                        if viewModel.ledgerRetriedOnly { viewModel.ledgerFailedOnly = false }
                        applyFilters()
                    }

                    // 提供商菜单
                    Menu {
                        Button(String(localized: "全部提供方")) { viewModel.ledgerProvider = ""; applyFilters() }
                        ForEach(viewModel.ledgerProviders) { provider in
                            Button(RoutingFormat.maskString(provider.displayName, isMasked: maskAccounts)) {
                                viewModel.ledgerProvider = provider.id
                                applyFilters()
                            }
                        }
                    } label: {
                        filterMenuLabel(
                            viewModel.ledgerProvider.isEmpty
                                ? String(localized: "提供方")
                                : (viewModel.ledgerProviders.first { $0.id == viewModel.ledgerProvider }?.displayName ?? viewModel.ledgerProvider),
                            active: !viewModel.ledgerProvider.isEmpty
                        )
                    }

                    // Agent 菜单
                    Menu {
                        Button(String(localized: "全部 Agent")) { viewModel.ledgerAgent = ""; applyFilters() }
                        ForEach(viewModel.ledgerAgents) { agent in
                            Button(agent.displayName) {
                                viewModel.ledgerAgent = agent.id
                                applyFilters()
                            }
                        }
                    } label: {
                        filterMenuLabel(
                            viewModel.ledgerAgent.isEmpty
                                ? String(localized: "Agent")
                                : (viewModel.ledgerAgents.first { $0.id == viewModel.ledgerAgent }?.displayName ?? viewModel.ledgerAgent),
                            active: !viewModel.ledgerAgent.isEmpty
                        )
                    }

                    Spacer(minLength: 0)
                }
            }
            .scrollClipDisabled()
        }
    }

    private func filterChip(_ title: String, active: Bool, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: .semibold))
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(active ? tint.opacity(0.18) : MagpieTheme.pill)
                .foregroundStyle(active ? tint : MagpieTheme.textSecondary)
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(active ? tint.opacity(0.35) : MagpieTheme.borderSubtle, lineWidth: 0.7)
                )
        }
        .buttonStyle(.plain)
    }

    private func filterMenuLabel(_ title: String, active: Bool) -> some View {
        HStack(spacing: 3) {
            Text(RoutingFormat.maskString(title, isMasked: maskAccounts))
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .bold))
        }
        .font(.system(size: 11.5, weight: .semibold))
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(active ? MagpieTheme.accentSoft : MagpieTheme.pill)
        .foregroundStyle(active ? MagpieTheme.accent : MagpieTheme.textSecondary)
        .clipShape(Capsule())
        .overlay(
            Capsule().stroke(active ? MagpieTheme.accent.opacity(0.35) : MagpieTheme.borderSubtle, lineWidth: 0.7)
        )
    }

    private func applyFilters() {
        guard let client = app.client else { return }
        Task {
            await viewModel.loadLedger(client: client, reset: true)
            await viewModel.loadHeatmap(client: client)
        }
    }

    // MARK: - 53 周日历用量热力图 (GitHub 风格)
    private var heatmapCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                        isHeatmapExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isHeatmapExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(MagpieTheme.textMuted)
                        MagpieSectionLabel(
                            title: String(localized: "用量热力图"),
                            detail: String(localized: "最近 53 周")
                        )
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                Picker("", selection: $heatMetric) {
                    Text(String(localized: "请求")).tag("calls")
                    Text(String(localized: "Tokens")).tag("tokens")
                    Text(String(localized: "费用")).tag("cost")
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .font(.caption2)
            }

            if isHeatmapExpanded {
                if viewModel.heatmap == nil {
                    if viewModel.isHeatmapLoading {
                        ProgressView().frame(maxWidth: .infinity).padding(.vertical, 16)
                    } else {
                        Text(String(localized: "热力图需要先加载请求数据。"))
                            .font(.caption2)
                            .foregroundStyle(MagpieTheme.textMuted)
                    }
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 3) {
                            ForEach(Array(heatWeeks.enumerated()), id: \.offset) { item in
                                VStack(spacing: 3) {
                                    ForEach(item.element) { cell in
                                        heatCell(cell)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .scrollClipDisabled()

                    HStack(spacing: 5) {
                        Text(String(localized: "少"))
                        ForEach([0.10, 0.3, 0.55, 0.8, 1.0], id: \.self) { level in
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(MagpieTheme.accent.opacity(level))
                                .frame(width: 10, height: 10)
                        }
                        Text(String(localized: "多"))
                        Spacer()
                        Text(heatMetricTitle)
                            .font(.caption2)
                            .foregroundStyle(MagpieTheme.textMuted)
                    }
                    .font(.caption2)
                    .foregroundStyle(MagpieTheme.textMuted)
                }
            }
        }
        .magpieCard()
    }

    private var heatMetricTitle: String {
        switch heatMetric {
        case "tokens": return String(localized: "按 Token 计数")
        case "cost": return String(localized: "按费用计数")
        default: return String(localized: "按请求数计数")
        }
    }

    private struct HeatCell: Identifiable {
        let id: Int
        let date: String
        let day: UsageHeatDayDTO?
    }

    private var heatWeeks: [[HeatCell]] {
        guard let heatmap = viewModel.heatmap,
              let from = heatmap.from, let to = heatmap.to else { return [] }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        guard var day = formatter.date(from: from),
              let end = formatter.date(from: to) else { return [] }

        let byDate = (heatmap.days ?? []).reduce(into: [String: UsageHeatDayDTO]()) { partial, day in
            partial[day.date] = day
        }
        var cells: [HeatCell] = []
        var index = 0
        let calendar = Calendar.current
        while day <= end {
            let key = formatter.string(from: day)
            cells.append(HeatCell(id: index, date: key, day: byDate[key]))
            index += 1
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return stride(from: 0, to: cells.count, by: 7).map {
            Array(cells[$0..<min($0 + 7, cells.count)])
        }
    }

    private var heatMax: Double {
        let days = viewModel.heatmap?.days ?? []
        let values = days.map { heatValue($0) }
        return max(values.max() ?? 0, 1)
    }

    private func heatValue(_ day: UsageHeatDayDTO?) -> Double {
        guard let day else { return 0 }
        switch heatMetric {
        case "tokens": return Double(day.tokens ?? 0)
        case "cost": return day.cost ?? 0
        default: return Double(day.calls ?? 0)
        }
    }

    private func heatCell(_ cell: HeatCell) -> some View {
        let value = heatValue(cell.day)
        let ratio = min(max(value / heatMax, 0), 1)
        return RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(value <= 0 ? MagpieTheme.pill : MagpieTheme.accent.opacity(0.14 + 0.86 * ratio))
            .frame(width: 10, height: 10)
            .help(heatHelp(cell, value: value))
    }

    private func heatHelp(_ cell: HeatCell, value: Double) -> String {
        let calls = cell.day?.calls ?? 0
        let tokens = cell.day?.tokens ?? 0
        let cost = cell.day?.cost
        return String(localized: "\(cell.date)\n\(calls) 请求 · \(UsageDTO.formatTokens(tokens)) tokens") +
            (cost.map { String(format: " · $%.2f", $0) } ?? "")
    }

    // MARK: - 账本请求列表 (Ledger List)
    private var ledgerList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                MagpieSectionLabel(
                    title: String(localized: "请求账本流水"),
                    detail: viewModel.ledgerTotal > 0 ? String(localized: "\(viewModel.ledgerTotal) 条记录") : nil
                )
                Spacer()
                if viewModel.isLedgerLoading {
                    ProgressView().controlSize(.small)
                }
            }

            if viewModel.ledgerRows.isEmpty {
                if viewModel.isLedgerLoading {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 24)
                } else {
                    emptyState(
                        icon: "list.bullet.rectangle",
                        title: String(localized: "没有匹配的请求"),
                        subtitle: String(localized: "调整时间范围或筛选条件后再试。")
                    )
                }
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(viewModel.ledgerRows) { row in
                        Button {
                            selectedRequest = row
                        } label: {
                            ledgerCard(row)
                        }
                        .buttonStyle(MagpiePressableStyle())
                    }
                }

                if viewModel.ledgerHasMore {
                    Button {
                        if let client = app.client {
                            Task { await viewModel.loadLedger(client: client, reset: false) }
                        }
                    } label: {
                        HStack {
                            if viewModel.isLedgerLoading {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "arrow.down.circle")
                            }
                            Text(String(localized: "加载更多记录"))
                        }
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(MagpieTheme.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(MagpieTheme.card)
                        .magpieLiquidSurface(cornerRadius: 12)
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isLedgerLoading)
                }
            }
        }
    }

    // MARK: - 单请求账本卡片 (Ledger Card)
    private func ledgerCard(_ row: UsageLedgerRowDTO) -> some View {
        HStack(spacing: 0) {
            // 左侧状态条
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(row.isError ? MagpieTheme.red : MagpieTheme.green)
                .frame(width: 3.5)
                .padding(.vertical, 6)
                .padding(.leading, 8)

            VStack(alignment: .leading, spacing: 6) {
                // 第一行：Agent + 模型 + 状态
                HStack(spacing: 8) {
                    MagpieIconView(icon: row.icon ?? row.agent, name: row.displayAgent, size: 24, cornerRadius: 6)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.model ?? String(localized: "未知模型"))
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundStyle(MagpieTheme.textPrimary)
                            .lineLimit(1)
                        if let wire = row.wire, !wire.isEmpty, wire != row.model {
                            Text("→ \(wire)")
                                .font(.system(size: 9.5, design: .monospaced))
                                .foregroundStyle(MagpieTheme.textMuted)
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    if let status = row.status {
                        Text(row.isError ? "HTTP \(status)" : "200 OK")
                            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Capsule().fill(row.isError ? MagpieTheme.red.opacity(0.16) : MagpieTheme.green.opacity(0.16)))
                            .foregroundStyle(row.isError ? MagpieTheme.red : MagpieTheme.green)
                    }
                }

                // 第二行：Agent · Provider · Caller Key
                HStack(spacing: 6) {
                    Text(row.displayAgent)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(MagpieTheme.textSecondary)
                    Text("·")
                        .font(.caption2)
                        .foregroundStyle(MagpieTheme.textMuted)
                    Text(RoutingFormat.maskString(row.displayProvider, isMasked: maskAccounts))
                        .font(.caption2)
                        .foregroundStyle(MagpieTheme.textMuted)

                    if let key = row.callerKeyLabel ?? row.callerKeyId, !key.isEmpty {
                        Text("[\(RoutingFormat.maskString(key, isMasked: maskAccounts))]")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(MagpieTheme.amber)
                    }

                    Spacer()

                    if let t = row.time {
                        Text(formatTimeOnly(t))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(MagpieTheme.textMuted)
                    }
                }

                // 第三行：延迟、Tokens 与花费
                HStack(spacing: 12) {
                    if let ms = row.millis, ms > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "stopwatch")
                                .font(.system(size: 9))
                            Text(RoutingFormat.latency(ms))
                                .font(.system(size: 10.5, design: .monospaced))
                        }
                        .foregroundStyle(MagpieTheme.textMuted)
                    }

                    if let ttft = row.ttft, ttft > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 8.5))
                            Text("\(ttft)ms")
                                .font(.system(size: 10, design: .monospaced))
                        }
                        .foregroundStyle(MagpieTheme.cyan)
                    }

                    HStack(spacing: 3) {
                        Image(systemName: "number")
                            .font(.system(size: 9))
                        Text(UsageDTO.formatTokens(row.totalTokens))
                            .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    }
                    .foregroundStyle(MagpieTheme.textSecondary)

                    Spacer()

                    Text(row.formattedCost)
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(MagpieTheme.green)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(MagpieTheme.textMuted.opacity(0.4))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
        }
        .magpieCard(padding: 0)
    }

    private func formatTimeOnly(_ isoString: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: isoString) {
            let out = DateFormatter()
            out.dateFormat = "HH:mm:ss"
            return out.string(from: d)
        }
        return isoString
    }

    // MARK: - 会话 (Sessions)
    private var sessionsSection: some View {
        VStack(spacing: 14) {
            HStack(spacing: 0) {
                kpi(String(localized: "会话总数"), "\(viewModel.sessions.count)", tint: MagpieTheme.accent)
                kpiDivider
                kpi(String(localized: "总 Tokens"), UsageDTO.formatTokens(viewModel.sessionTokenTotal), tint: MagpieTheme.purple)
                kpiDivider
                kpi(String(localized: "总费用"), String(format: "$%.2f", viewModel.sessionCostTotal), tint: MagpieTheme.green)
            }
            .magpieCard(padding: 12)

            if viewModel.sessions.isEmpty {
                if viewModel.isSessionsLoading {
                    ProgressView().padding(.vertical, 30)
                } else {
                    emptyState(
                        icon: "bubble.left.and.bubble.right",
                        title: String(localized: "暂无会话"),
                        subtitle: String(localized: "通过网关发起的会话将在此聚合并统计用量。")
                    )
                }
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(viewModel.sessions) { session in
                        sessionCard(session)
                    }
                }
            }
        }
    }

    private func sessionCard(_ session: SessionDTO) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                MagpieIconView(icon: session.agent, name: session.displayAgent, size: 28, cornerRadius: 7)

                VStack(alignment: .leading, spacing: 2) {
                    Text(session.displayTitle)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(MagpieTheme.textPrimary)
                        .lineLimit(1)
                    Text(session.displayAgent)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(MagpieTheme.textMuted)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "$%.3f", session.cost ?? 0.0))
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(MagpieTheme.green)
                    Text("\(session.formattedTokens) tokens")
                        .font(.caption2)
                        .foregroundStyle(MagpieTheme.textMuted)
                }
            }
        }
        .magpieCard(padding: 11)
    }

    private func kpi(_ title: String, _ value: String, tint: Color) -> some View {
        VStack(spacing: 3) {
            MagpieGradientNumber(text: value, tint: tint, size: 18)
            Text(title)
                .font(.system(size: 9.5))
                .foregroundStyle(MagpieTheme.textMuted)
        }
        .frame(maxWidth: .infinity)
    }

    private var kpiDivider: some View {
        Rectangle()
            .fill(MagpieTheme.borderSubtle)
            .frame(width: 1, height: 24)
    }

    // MARK: - 上下文 (Context)
    private var contextSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let agents = viewModel.context?.agents, !agents.isEmpty {
                MagpieSectionLabel(
                    title: String(localized: "上下文窗口利用率"),
                    detail: String(localized: "最近 30 天")
                )
                ForEach(agents.sorted { ($0.score ?? 0) > ($1.score ?? 0) }) { agent in
                    contextCard(agent)
                }
            } else if viewModel.isContextLoading {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 30)
            } else {
                emptyState(
                    icon: "rectangle.split.3x1",
                    title: String(localized: "还没有上下文数据"),
                    subtitle: String(localized: "网关记录到带 prompt 的请求后，这里会显示上下文占用、缓存命中与增长趋势。")
                )
            }

            if let tune = viewModel.tune, !(tune.agents ?? []).isEmpty {
                tuneSection(tune)
            }
        }
    }

    private func tuneSection(_ tune: TuneStateDTO) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            MagpieSectionLabel(
                title: "Tuned for you",
                detail: String(localized: "按最近 \(tune.days ?? 30) 天你自己的调用推算")
            )

            ForEach(tune.agents ?? []) { agent in
                if let advice = agent.advice, !advice.isEmpty {
                    tuneAgentCard(agent, advice: advice)
                }
            }
        }
    }

    private func tuneAgentCard(_ agent: TuneAgentDTO, advice: [TuneAdviceDTO]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                MagpieIconView(icon: agent.agent, name: agent.displayName, size: 30, cornerRadius: 7)
                VStack(alignment: .leading, spacing: 2) {
                    Text(agent.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(MagpieTheme.textPrimary)
                    Text(String(localized: "\(agent.calls ?? 0) 次调用参与推算"))
                        .font(.caption2)
                        .foregroundStyle(MagpieTheme.textMuted)
                }
                Spacer()
            }
            .padding(12)

            Divider().background(MagpieTheme.borderSubtle)

            VStack(spacing: 10) {
                ForEach(advice) { item in
                    tuneAdviceRow(agent: agent.agent, item: item)
                }
            }
            .padding(12)
        }
        .magpieCard(padding: 0)
    }

    private func tuneAdviceRow(agent: String, item: TuneAdviceDTO) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(item.knob)
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundStyle(MagpieTheme.textPrimary)
                        if let model = item.model, !model.isEmpty {
                            Text(model)
                                .font(.caption2)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(MagpieTheme.pill, in: Capsule())
                                .foregroundStyle(MagpieTheme.textSecondary)
                        }
                    }

                    if let why = item.why, !why.isEmpty {
                        Text(why)
                            .font(.caption)
                            .foregroundStyle(MagpieTheme.textMuted)
                    }
                }

                Spacer()

                if item.applied == true {
                    Button {
                        if let client = app.client {
                            Task { _ = await viewModel.undoTune(client: client, agent: agent, advice: item) }
                        }
                    } label: {
                        Text(String(localized: "已生效 · 撤销"))
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(MagpieTheme.pill, in: Capsule())
                            .foregroundStyle(MagpieTheme.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isOperating)
                } else if item.canTakeOver {
                    Button {
                        if let client = app.client {
                            Task { _ = await viewModel.takeOverTune(client: client, agent: agent) }
                        }
                    } label: {
                        Text(String(localized: "由 magpie 接管"))
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(MagpieTheme.amber, in: Capsule())
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isOperating)
                } else if item.proposedValue != nil {
                    Button {
                        if let client = app.client {
                            Task { _ = await viewModel.applyTune(client: client, agent: agent, advice: item) }
                        }
                    } label: {
                        Text(String(localized: "采用建议"))
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(MagpieTheme.accent, in: Capsule())
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isOperating)
                }
            }
        }
    }

    private func contextCard(_ agent: UsageContextAgentDTO) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                MagpieIconView(icon: agent.agent, name: agent.agent, size: 28, cornerRadius: 7)

                VStack(alignment: .leading, spacing: 2) {
                    Text(agent.agent)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(MagpieTheme.textPrimary)
                    Text(String(localized: "\(agent.requests ?? 0) 个请求 · \(agent.calls ?? 0) 次记录"))
                        .font(.caption2)
                        .foregroundStyle(MagpieTheme.textMuted)
                }

                Spacer()

                if let score = agent.score {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("\(score)")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(contextScoreColor(score))
                        Text(String(localized: "上下文得分"))
                            .font(.system(size: 8.5))
                            .foregroundStyle(MagpieTheme.textMuted)
                    }
                }
            }

            if let score = agent.score {
                ProgressView(value: Double(min(max(score, 0), 100)), total: 100)
                    .tint(contextScoreColor(score))
            }

            HStack(spacing: 0) {
                contextMetric(String(localized: "中位上下文"), UsageDTO.formatTokens(agent.median ?? 0))
                contextDivider
                contextMetric(String(localized: "P90"), UsageDTO.formatTokens(agent.p90 ?? 0))
                contextDivider
                contextMetric(String(localized: "缓存命中"), String(format: "%.0f%%", (agent.cache ?? 0) * 100))
                contextDivider
                contextMetric(String(localized: "增长"), UsageDTO.formatTokens(agent.growth ?? 0))
            }

            if let tags = agent.tags, !tags.isEmpty {
                Text(tags.map(\.key).joined(separator: " · "))
                    .font(.system(size: 9.5))
                    .foregroundStyle(MagpieTheme.textMuted)
                    .lineLimit(1)
            }
        }
        .magpieCard()
    }

    private func contextMetric(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(MagpieTheme.textPrimary)
            Text(title)
                .font(.system(size: 8.5))
                .foregroundStyle(MagpieTheme.textMuted)
        }
        .frame(maxWidth: .infinity)
    }

    private var contextDivider: some View {
        Rectangle()
            .fill(MagpieTheme.borderSubtle)
            .frame(width: 1, height: 22)
    }

    private func contextScoreColor(_ score: Int) -> Color {
        if score >= 80 { return MagpieTheme.green }
        if score >= 60 { return MagpieTheme.accent }
        return MagpieTheme.amber
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(MagpieTheme.red)
            Text(message)
                .font(.caption)
                .foregroundStyle(MagpieTheme.red)
            Spacer()
        }
        .padding(10)
        .background(MagpieTheme.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func emptyState(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(MagpieTheme.pill)
                    .frame(width: 48, height: 48)
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(MagpieTheme.textMuted)
            }
            Text(title)
                .font(.headline)
                .foregroundStyle(MagpieTheme.textPrimary)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(MagpieTheme.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .magpieCard()
    }
}

// MARK: - 核心指标卡 (MetricCard)
private struct MetricCard: View {
    let title: String
    let value: String
    var sub: String? = nil
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .font(.subheadline)
                Spacer()
            }

            MagpieGradientNumber(text: value, tint: color, size: 22)

            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(MagpieTheme.textPrimary)

            if let sub, !sub.isEmpty {
                Text(sub)
                    .font(.system(size: 9.5))
                    .foregroundStyle(MagpieTheme.textMuted)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .magpieCard(padding: 12, cornerRadius: 16)
    }
}

// MARK: - Token 构成图
private struct TokenSlice: Identifiable {
    let category: String
    let amount: Int
    let color: Color
    var id: String { category }
}

private struct TokenDistributionChart: View {
    let usage: UsageDTO

    private var slices: [TokenSlice] {
        [
            TokenSlice(category: String(localized: "输入"), amount: max(usage.input ?? 0, 1), color: MagpieTheme.amber),
            TokenSlice(category: String(localized: "输出"), amount: max(usage.output ?? 0, 1), color: MagpieTheme.purple),
            TokenSlice(category: String(localized: "缓存"), amount: max((usage.cache_read ?? 0) + (usage.cache_write ?? 0), 1), color: MagpieTheme.cyan)
        ]
    }

    var body: some View {
        Chart(slices) { slice in
            SectorMark(
                angle: .value("Tokens", slice.amount),
                innerRadius: .ratio(0.68),
                angularInset: 2.0
            )
            .foregroundStyle(slice.color)
            .cornerRadius(4)
        }
    }
}

// MARK: - 请求详情面板 (UsageRequestDetailSheet)
private struct UsageRequestDetailSheet: View {
    let row: UsageLedgerRowDTO
    var isMasked: Bool = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 9) {
                            Circle()
                                .fill(row.isError ? MagpieTheme.red : MagpieTheme.green)
                                .frame(width: 8, height: 8)
                            Text(row.model ?? String(localized: "未知模型"))
                                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                .foregroundStyle(MagpieTheme.textPrimary)
                                .lineLimit(1)
                            Spacer()
                            if let status = row.status {
                                Text("HTTP \(status)")
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(row.isError ? MagpieTheme.red : MagpieTheme.green)
                            }
                        }

                        if let error = row.error, !error.isEmpty {
                            Text(error)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(MagpieTheme.red)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        HStack(spacing: 0) {
                            metric(String(localized: "输入"), UsageDTO.formatTokens(row.input ?? 0))
                            divider
                            metric(String(localized: "输出"), UsageDTO.formatTokens(row.output ?? 0))
                            divider
                            metric(String(localized: "缓存"), UsageDTO.formatTokens((row.cacheRead ?? 0) + (row.cacheWrite ?? 0)))
                            divider
                            metric(String(localized: "费用"), row.formattedCost)
                        }
                    }
                    .magpieCard()

                    VStack(alignment: .leading, spacing: 9) {
                        MagpieSectionLabel(title: String(localized: "请求明细"))
                        info(String(localized: "Agent"), row.displayAgent)
                        info(String(localized: "提供方"), RoutingFormat.maskString(row.displayProvider, isMasked: isMasked))
                        info(String(localized: "模型"), row.model)
                        if let requested = row.requested, !requested.isEmpty, requested != row.model {
                            info(String(localized: "请求的模型"), requested)
                        }
                        info(String(localized: "会话 ID"), row.session)
                        info(String(localized: "调用 Key"), RoutingFormat.maskString(row.callerKeyLabel ?? row.callerKeyId ?? "", isMasked: isMasked))
                        info(String(localized: "耗时"), row.millis.map { "\($0)ms" })
                        info(String(localized: "时间"), row.time)
                        info(String(localized: "来源"), row.source)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .magpieCard()
                }
                .padding(16)
            }
            .magpiePageBackground()
            .navigationTitle(String(localized: "请求详情"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "完成")) { dismiss() }
                }
            }
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(MagpieTheme.textPrimary)
            Text(title)
                .font(.caption2)
                .foregroundStyle(MagpieTheme.textMuted)
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle()
            .fill(MagpieTheme.borderSubtle)
            .frame(width: 1, height: 24)
    }

    private func info(_ title: String, _ value: String?) -> some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundStyle(MagpieTheme.textMuted)
            Spacer()
            Text(value?.isEmpty == false ? value! : "—")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(MagpieTheme.textPrimary)
                .lineLimit(1)
        }
    }
}
