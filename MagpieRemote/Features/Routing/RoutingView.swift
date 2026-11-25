import SwiftUI

/// 路由管理与实时决策中心（1:1 复刻 Web 路由引擎与原生 Liquid Glass 体验）
/// 支持实时毫秒级长轮询流、按请求/按会话/按密钥三种分组、历史回溯、流动决策舞台及候选权衡链路。
struct RoutingView: View {
    @Environment(AppModel.self) private var app
    @AppStorage("magpie_mask_accounts") private var maskAccounts = false

    @State private var viewModel = RoutingViewModel()
    @State private var selectedRoute: GatewayRouteDTO?
    @State private var searchText = ""
    @State private var expandedSessionIDs: Set<String> = []
    @State private var expandedKeyIDs: Set<String> = []
    @State private var showingGroupsSheet = false

    // MARK: - 过滤后路由列表
    private var filteredRoutes: [GatewayRouteDTO] {
        var list = viewModel.routes

        // 状态筛选
        switch viewModel.filterStatus {
        case .all:
            break
        case .errors:
            list = list.filter { $0.isError }
        case .rerouted:
            list = list.filter { ($0.order?.count ?? 0) > 1 || $0.moved != nil }
        case .pending:
            list = list.filter { $0.isPending }
        }

        // 搜索文本过滤
        guard !searchText.isEmpty else { return list }
        let q = searchText.lowercased()
        return list.filter {
            ($0.model?.lowercased().contains(q) ?? false)
                || ($0.provider?.lowercased().contains(q) ?? false)
                || ($0.agent?.lowercased().contains(q) ?? false)
                || ($0.group?.displayName.lowercased().contains(q) ?? false)
                || ($0.sessionTitle?.lowercased().contains(q) ?? false)
                || ($0.effectiveSessionID.lowercased().contains(q))
                || ($0.callerKeyName?.lowercased().contains(q) ?? false)
        }
    }

    /// 当前最聚焦的路由记录（优先取正在调度的，其次取最新的）
    private var activeFocusRoute: GatewayRouteDTO? {
        viewModel.pendingRoutes.first ?? viewModel.routes.first
    }

    var body: some View {
        MagpieNavigationContainer {
            ScrollView {
                VStack(spacing: 12) {
                    // 1. 顶部决策流动舞台 (1:1 Web Stage 拓扑流向、候选梯队与 3 大响应式 KPI)
                    stageHero

                    // 2. 整合后的精简控制栏 (日期选择下拉 + 分组模式切换)
                    compactControlsBar

                    // 3. 错误提示横幅
                    if let error = viewModel.errorMessage {
                        errorBanner(error)
                    }

                    // 4. 主内容区（按模式呈现 By Request / By Session / By Key）
                    mainContentSection
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .padding(.bottom, 96)
            }
            .magpiePageBackground()
            .navigationTitle(String(localized: "Routing"))
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $searchText, prompt: String(localized: "搜索模型、提供方、Agent 或会话…"))
            .toolbar {
                // 1. 账号脱敏遮蔽开关 (Web 1:1 Hide accounts)
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

                // 2. 快捷跳往路由组
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingGroupsSheet = true
                    } label: {
                        Image(systemName: "square.3.layers.3d")
                            .font(.body.weight(.medium))
                    }
                    .accessibilityLabel(String(localized: "路由组"))
                }

                // 3. 刷新按钮
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        if let client = app.client {
                            Task { await viewModel.refresh(client: client) }
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel(String(localized: "刷新路由"))
                }
            }
            .refreshable {
                if let client = app.client {
                    await viewModel.refresh(client: client)
                }
            }
            .task {
                if let client = app.client {
                    viewModel.startRealtimeTrace(client: client)
                }
            }
            .onDisappear {
                viewModel.stopPolling()
            }
            .sheet(item: $selectedRoute) { route in
                RoutingRouteDetailSheet(route: route, isMasked: maskAccounts)
            }
            .sheet(isPresented: $showingGroupsSheet) {
                NavigationStack {
                    GroupsView()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button(String(localized: "完成")) {
                                    showingGroupsSheet = false
                                }
                            }
                        }
                }
            }
        }
    }

    // MARK: - 1. 顶部决策流动舞台 (Stage Hero - 1:1 对齐 Web 原版流动舞台)
    private var stageHero: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(String(localized: "路由"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MagpieTheme.textPrimary)

                MagpiePulseDot(color: viewModel.pendingRoutes.isEmpty ? MagpieTheme.green : MagpieTheme.accent)

                Text(viewModel.selectedDay == nil
                     ? String(localized: "实时 · 网关正在做的决定")
                     : String(localized: "历史归档"))
                    .font(.system(size: 11))
                    .foregroundStyle(MagpieTheme.textMuted)

                Spacer(minLength: 4)

                if let updated = viewModel.lastUpdated {
                    Text(RoutingFormat.time(updated))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(MagpieTheme.textMuted)
                }
            }
            .padding(.horizontal, 2)

            RoutingStageCard(
                route: activeFocusRoute,
                routes: viewModel.routes,
                requestsCount: viewModel.totals?.requests ?? viewModel.routes.count,
                reroutedCount: viewModel.totals?.rerouted ?? viewModel.reroutedCount,
                errorCount: viewModel.totals?.errors ?? viewModel.errorCount,
                isHistory: viewModel.selectedDay != nil,
                masked: maskAccounts,
                activeURL: app.activeURL,
                filterStatus: viewModel.filterStatus,
                onFilter: { status in
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        viewModel.filterStatus = (viewModel.filterStatus == status && status != .all) ? .all : status
                    }
                }
            )
        }
    }

    // MARK: - 2. 整合后的精简控制栏 (日期选择菜单 + 分组模式切换)
    private var compactControlsBar: some View {
        HStack(spacing: 8) {
            // 日期下拉菜单 (对齐 Web 官方 rt-day-more 机制，极其节省空间)
            Menu {
                Button {
                    if let client = app.client {
                        Task { await viewModel.selectDay(nil, client: client) }
                    }
                } label: {
                    Label(String(localized: "实时流 (Live)"), systemImage: viewModel.selectedDay == nil ? "checkmark" : "")
                }

                if !viewModel.availableDays.isEmpty {
                    Divider()
                    ForEach(viewModel.availableDays, id: \.self) { day in
                        Button {
                            if let client = app.client {
                                Task { await viewModel.selectDay(day, client: client) }
                            }
                        } label: {
                            Label(day, systemImage: viewModel.selectedDay == day ? "checkmark" : "")
                        }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Circle()
                        .fill(viewModel.selectedDay == nil ? MagpieTheme.green : MagpieTheme.accent)
                        .frame(width: 6, height: 6)
                    Text(viewModel.selectedDay ?? String(localized: "实时流 (Live)"))
                        .font(.system(size: 11.5, weight: .semibold, design: viewModel.selectedDay != nil ? .monospaced : .default))
                        .foregroundStyle(MagpieTheme.textPrimary)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(MagpieTheme.textMuted)
                }
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(MagpieTheme.card)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(MagpieTheme.borderSubtle, lineWidth: 0.8)
                )
            }

            Spacer()

            // 模式选择器 (按请求 / 按会话 / 按密钥)
            HStack(spacing: 2) {
                ForEach(RoutingViewMode.allCases) { mode in
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                            viewModel.viewMode = mode
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: mode.icon)
                                .font(.system(size: 9.5))
                            Text(mode.title)
                                .font(.system(size: 11, weight: .medium))
                        }
                        .padding(.horizontal, 8)
                        .frame(height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(viewModel.viewMode == mode ? MagpieTheme.card : Color.clear)
                        )
                        .foregroundStyle(viewModel.viewMode == mode ? MagpieTheme.textPrimary : MagpieTheme.textMuted)
                        .shadow(color: viewModel.viewMode == mode ? Color.black.opacity(0.06) : Color.clear, radius: 2, x: 0, y: 1)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(MagpieTheme.pill)
            )
        }
    }

    // MARK: - 3. 错误横幅
    private func errorBanner(_ msg: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(MagpieTheme.red)
            Text(msg)
                .font(.caption)
                .foregroundStyle(MagpieTheme.red)
            Spacer()
        }
        .padding(12)
        .background(MagpieTheme.red.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - 4. 主内容区
    @ViewBuilder
    private var mainContentSection: some View {
        if filteredRoutes.isEmpty {
            emptyState
        } else {
            switch viewModel.viewMode {
            case .byRequest:
                requestsListSection
            case .bySession:
                sessionsGroupSection
            case .byKey:
                keysGroupSection
            }
        }
    }

    // MARK: - By Request 列表
    private var requestsListSection: some View {
        LazyVStack(spacing: 10) {
            ForEach(filteredRoutes) { route in
                Button {
                    selectedRoute = route
                } label: {
                    routeCard(route)
                }
                .buttonStyle(MagpiePressableStyle())
            }
        }
    }

    // MARK: - 单卡片路由详情 (高保真 Glass Card)
    private func routeCard(_ route: GatewayRouteDTO) -> some View {
        HStack(spacing: 0) {
            // 左侧状态指示光条
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(statusColor(route))
                .frame(width: 3.5)
                .padding(.vertical, 6)
                .padding(.leading, 8)
                .shadow(
                    color: statusColor(route).opacity(route.isPending ? 0.9 : 0.25),
                    radius: route.isPending ? 6 : 2
                )

            VStack(alignment: .leading, spacing: 8) {
                // 第一行：Agent + 模型 + 时间 + 状态
                HStack(spacing: 8) {
                    MagpieIconView(icon: route.agent, name: route.agent ?? "agent", size: 26, cornerRadius: 7)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(route.model ?? String(localized: "未知模型"))
                            .font(.system(size: 13.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(MagpieTheme.textPrimary)
                            .lineLimit(1)

                        if let title = route.sessionTitle, !title.isEmpty {
                            Text(title)
                                .font(.system(size: 11))
                                .foregroundStyle(MagpieTheme.textMuted)
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    statusBadge(route)
                }

                // 第二行：改派路径与策略标签
                if let moved = route.moved {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.triangle.swap")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(MagpieTheme.amber)
                        Text(String(localized: "改派转移至: \(RoutingFormat.maskString(moved.to ?? "备用渠道", isMasked: maskAccounts))"))
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(MagpieTheme.amber)
                        if let why = moved.why, !why.isEmpty {
                            Text("· \(why)")
                                .font(.system(size: 10))
                                .foregroundStyle(MagpieTheme.textMuted)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(MagpieTheme.amber.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                } else if let group = route.group {
                    HStack(spacing: 4) {
                        Image(systemName: "square.3.layers.3d")
                            .font(.system(size: 9))
                        Text(group.displayName)
                        Text("·")
                        Text(RoutingFormat.strategyName(group.routing))
                        Spacer()
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(MagpieTheme.accent)
                }

                // 第三行：提供商与调用时间
                HStack(spacing: 8) {
                    Text(RoutingFormat.maskString(route.provider ?? "—", isMasked: maskAccounts))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(MagpieTheme.textSecondary)

                    if let keyName = route.callerKeyName, !keyName.isEmpty {
                        Text(RoutingFormat.maskString(keyName, isMasked: maskAccounts))
                            .font(.system(size: 9.5, design: .monospaced))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(MagpieTheme.pill)
                            .foregroundStyle(MagpieTheme.textMuted)
                            .clipShape(Capsule())
                    }

                    Spacer()

                    if let d = route.date {
                        Text(RoutingFormat.time(d))
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(MagpieTheme.textMuted)
                    }
                }

                // 第四行：5大核心指标矩阵 (耗时、TTFT、速度、Tokens、费用)
                HStack(spacing: 12) {
                    metricChip(title: String(localized: "耗时"), value: RoutingFormat.latency(route.millis))
                    if let ttft = route.ttft, ttft > 0 {
                        metricChip(title: "TTFT", value: "\(ttft)ms")
                    }
                    if let speed = route.outputSpeed {
                        metricChip(title: String(localized: "速度"), value: String(format: "%.0f t/s", speed))
                    }
                    metricChip(title: "Tokens", value: RoutingFormat.tokens(route.tokens))
                    metricChip(title: String(localized: "费用"), value: RoutingFormat.cost(route.cost))

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(MagpieTheme.textMuted.opacity(0.5))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
        }
        .magpieCard(padding: 0)
    }

    private func metricChip(title: String, value: String) -> some View {
        HStack(spacing: 3) {
            Text(title)
                .font(.system(size: 9.5))
                .foregroundStyle(MagpieTheme.textMuted)
            Text(value)
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(MagpieTheme.textSecondary)
        }
    }

    private func statusBadge(_ route: GatewayRouteDTO) -> some View {
        Group {
            if route.isPending {
                HStack(spacing: 4) {
                    MagpiePulseDot(color: MagpieTheme.accent)
                    Text(String(localized: "调度中"))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2.5)
                .background(Capsule().fill(MagpieTheme.accentSoft))
                .foregroundStyle(MagpieTheme.accent)
                .font(.system(size: 10, weight: .bold))
            } else if route.isError {
                Text(RoutingFormat.statusText(route))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(Capsule().fill(MagpieTheme.red.opacity(0.16)))
                    .foregroundStyle(MagpieTheme.red)
                    .font(.system(size: 10, weight: .bold))
            } else if route.canceled == true {
                Text(String(localized: "已取消"))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(Capsule().fill(MagpieTheme.amber.opacity(0.16)))
                    .foregroundStyle(MagpieTheme.amber)
                    .font(.system(size: 10, weight: .bold))
            } else {
                Text(String(localized: "成功"))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(Capsule().fill(MagpieTheme.green.opacity(0.16)))
                    .foregroundStyle(MagpieTheme.green)
                    .font(.system(size: 10, weight: .bold))
            }
        }
    }

    private func statusColor(_ route: GatewayRouteDTO) -> Color {
        if route.isPending { return MagpieTheme.accent }
        if route.isError { return MagpieTheme.red }
        if route.canceled == true { return MagpieTheme.amber }
        return MagpieTheme.green
    }

    // MARK: - By Session 列表
    private var sessionsGroupSection: some View {
        LazyVStack(spacing: 12) {
            ForEach(viewModel.sessionGroups) { group in
                sessionGroupCard(group)
            }
        }
    }

    private func sessionGroupCard(_ group: SessionRouteGroup) -> some View {
        let isExpanded = expandedSessionIDs.contains(group.id)

        return VStack(spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                    if isExpanded {
                        expandedSessionIDs.remove(group.id)
                    } else {
                        expandedSessionIDs.insert(group.id)
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    MagpieIconView(icon: group.agent, name: group.agent, size: 30, cornerRadius: 8)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(MagpieTheme.textPrimary)
                            .lineLimit(1)

                        HStack(spacing: 6) {
                            Text("\(group.routes.count) 次请求")
                            Text("·")
                            Text(RoutingFormat.tokens(group.totalTokens))
                            Text("·")
                            Text(RoutingFormat.cost(group.totalCost))
                        }
                        .font(.caption2)
                        .foregroundStyle(MagpieTheme.textMuted)
                    }

                    Spacer()

                    if group.hasPending {
                        MagpiePulseDot(color: MagpieTheme.accent)
                    }

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(MagpieTheme.textMuted)
                }
                .padding(12)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider().background(MagpieTheme.borderSubtle)

                VStack(spacing: 6) {
                    ForEach(group.routes) { r in
                        Button {
                            selectedRoute = r
                        } label: {
                            routeMiniRow(r)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(10)
            }
        }
        .magpieCard(padding: 0)
    }

    // MARK: - By Key 列表
    private var keysGroupSection: some View {
        LazyVStack(spacing: 12) {
            ForEach(viewModel.keyGroups) { group in
                keyGroupCard(group)
            }
        }
    }

    private func keyGroupCard(_ group: KeyRouteGroup) -> some View {
        let isExpanded = expandedKeyIDs.contains(group.id)

        return VStack(spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                    if isExpanded {
                        expandedKeyIDs.remove(group.id)
                    } else {
                        expandedKeyIDs.insert(group.id)
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(MagpieTheme.amber.opacity(0.18))
                            .frame(width: 30, height: 30)
                        Image(systemName: "key.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(MagpieTheme.amber)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(RoutingFormat.maskString(group.id, isMasked: maskAccounts))
                            .font(.system(size: 13.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(MagpieTheme.textPrimary)
                            .lineLimit(1)

                        HStack(spacing: 6) {
                            Text("\(group.routes.count) 次请求")
                            Text("·")
                            Text(RoutingFormat.tokens(group.totalTokens))
                            Text("·")
                            Text(RoutingFormat.cost(group.totalCost))
                        }
                        .font(.caption2)
                        .foregroundStyle(MagpieTheme.textMuted)
                    }

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(MagpieTheme.textMuted)
                }
                .padding(12)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider().background(MagpieTheme.borderSubtle)

                VStack(spacing: 6) {
                    ForEach(group.routes) { r in
                        Button {
                            selectedRoute = r
                        } label: {
                            routeMiniRow(r)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(10)
            }
        }
        .magpieCard(padding: 0)
    }

    private func routeMiniRow(_ route: GatewayRouteDTO) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor(route))
                .frame(width: 6, height: 6)

            Text(route.model ?? "—")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(MagpieTheme.textPrimary)
                .lineLimit(1)

            Text(RoutingFormat.maskString(route.provider ?? "", isMasked: maskAccounts))
                .font(.system(size: 10.5))
                .foregroundStyle(MagpieTheme.textMuted)

            Spacer()

            Text(RoutingFormat.latency(route.millis))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(MagpieTheme.textSecondary)

            Text(RoutingFormat.cost(route.cost))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(MagpieTheme.textSecondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(MagpieTheme.pill.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(MagpieTheme.pill)
                    .frame(width: 52, height: 52)

                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(MagpieTheme.textMuted)
            }
            .padding(.bottom, 2)

            Text(String(localized: "暂无匹配的路由决策记录"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(MagpieTheme.textPrimary)

            Text(String(localized: "当任何 AI Agent (Claude Code / Codex / Cursor 等) 通过网关发起调用时，此处将实时展示完整的路由链路。"))
                .font(.caption2)
                .foregroundStyle(MagpieTheme.textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)

            if viewModel.filterStatus != .all || !searchText.isEmpty {
                Button {
                    withAnimation {
                        viewModel.filterStatus = .all
                        searchText = ""
                    }
                } label: {
                    Text(String(localized: "重置筛选条件"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(MagpieTheme.accent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(MagpieTheme.accentSoft, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .magpieCard(cornerRadius: 16)
    }
}

// MARK: - 单次路由决策详细信息面板 (Route Detail Sheet)
struct RoutingRouteDetailSheet: View {
    let route: GatewayRouteDTO
    var isMasked: Bool = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // 头部基本信息
                    headerCard

                    // 核心数据指标矩阵
                    metricsGrid

                    // 网关权衡链路（候选账号与决策顺序）
                    if let order = route.order, !order.isEmpty {
                        candidateOrderSection(order)
                    }

                    // 缓存与 Token 统计
                    tokenUsageSection

                    // 元数据与调用上下文
                    metaInfoSection

                    // 错误信息（若有）
                    if let error = route.error, !error.isEmpty {
                        errorSection(error)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .magpiePageBackground()
            .navigationTitle(String(localized: "路由决策详情"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "完成")) {
                        dismiss()
                    }
                }
            }
        }
    }

    private var headerCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                MagpieIconView(icon: route.agent, name: route.agent ?? "agent", size: 40, cornerRadius: 10)

                VStack(alignment: .leading, spacing: 3) {
                    Text(route.model ?? String(localized: "未知模型"))
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundStyle(MagpieTheme.textPrimary)

                    HStack(spacing: 6) {
                        Text(RoutingFormat.maskString(route.provider ?? "—", isMasked: isMasked))
                        if let group = route.group {
                            Text("·")
                            Text(group.displayName)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(MagpieTheme.textSecondary)
                }

                Spacer()

                if route.isPending {
                    MagpieStatusChip(text: String(localized: "调度中"), color: MagpieTheme.accent)
                } else if route.isError {
                    MagpieStatusChip(text: RoutingFormat.statusText(route), color: MagpieTheme.red, icon: "xmark")
                } else {
                    MagpieStatusChip(text: String(localized: "成功"), color: MagpieTheme.green, icon: "checkmark")
                }
            }

            if let sessionTitle = route.sessionTitle, !sessionTitle.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.caption)
                        .foregroundStyle(MagpieTheme.textMuted)
                    Text(sessionTitle)
                        .font(.caption)
                        .foregroundStyle(MagpieTheme.textSecondary)
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(MagpieTheme.cardSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .magpieCard()
    }

    private var metricsGrid: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                detailMetricTile(
                    title: String(localized: "耗时"),
                    value: RoutingFormat.latency(route.millis),
                    icon: "stopwatch",
                    tint: MagpieTheme.accent
                )
                detailMetricTile(
                    title: "TTFT",
                    value: route.ttft != nil ? "\(route.ttft!)ms" : "—",
                    icon: "bolt.fill",
                    tint: MagpieTheme.amber
                )
            }

            HStack(spacing: 8) {
                detailMetricTile(
                    title: String(localized: "吞吐速度"),
                    value: route.outputSpeed != nil ? String(format: "%.1f t/s", route.outputSpeed!) : "—",
                    icon: "speedometer",
                    tint: MagpieTheme.cyan
                )
                detailMetricTile(
                    title: String(localized: "预估费用"),
                    value: RoutingFormat.cost(route.cost),
                    icon: "dollarsign.circle",
                    tint: MagpieTheme.green
                )
            }
        }
    }

    private func detailMetricTile(title: String, value: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(MagpieTheme.textMuted)
            }
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(MagpieTheme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(MagpieTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(MagpieTheme.borderSubtle, lineWidth: 0.8)
        )
    }

    private func candidateOrderSection(_ order: [GatewayWeighedDTO]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            MagpieSectionLabel(title: String(localized: "网关权衡与尝试顺序"), detail: String(localized: "\(order.count) 个候选"))

            VStack(spacing: 8) {
                ForEach(Array(order.enumerated()), id: \.element.id) { index, cand in
                    let isTarget = (cand.provider == route.provider) || (cand.name == route.provider)

                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(isTarget ? MagpieTheme.green.opacity(0.16) : MagpieTheme.pill)
                                .frame(width: 24, height: 24)

                            Text("\(index + 1)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(isTarget ? MagpieTheme.green : MagpieTheme.textMuted)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(RoutingFormat.maskString(cand.displayLabel, isMasked: isMasked))
                                    .font(.system(size: 13, weight: isTarget ? .bold : .medium))
                                    .foregroundStyle(MagpieTheme.textPrimary)

                                if isTarget {
                                    Text(String(localized: "最终命中"))
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(MagpieTheme.green)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1.5)
                                        .background(Capsule().fill(MagpieTheme.greenSoft))
                                }
                                if cand.ultra == true {
                                    Text("ULTRA")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(MagpieTheme.purple)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1.5)
                                        .background(Capsule().fill(MagpieTheme.purple.opacity(0.14)))
                                } else if cand.fast == true {
                                    Text("FAST")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(MagpieTheme.cyan)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1.5)
                                        .background(Capsule().fill(MagpieTheme.cyan.opacity(0.14)))
                                }
                                if let ctx = cand.context, ctx > 0 {
                                    Text(RoutingStagePalette.contextShort(ctx))
                                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(MagpieTheme.textSecondary)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1.5)
                                        .background(Capsule().fill(MagpieTheme.cardSecondary))
                                }
                            }

                            if let why = cand.why, !why.isEmpty {
                                Text(why)
                                    .font(.caption2)
                                    .foregroundStyle(MagpieTheme.textMuted)
                            }
                        }

                        Spacer()

                        if let balance = cand.balance, !balance.isEmpty {
                            Text(balance)
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(MagpieTheme.textSecondary)
                        }
                    }
                    .padding(10)
                    .background(isTarget ? MagpieTheme.greenSoft.opacity(0.3) : MagpieTheme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(isTarget ? MagpieTheme.green.opacity(0.3) : MagpieTheme.borderSubtle, lineWidth: 0.8)
                    )
                }
            }
        }
        .magpieCard()
    }

    private var tokenUsageSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            MagpieSectionLabel(title: String(localized: "Token 消耗与缓存"))

            VStack(spacing: 8) {
                detailRow(label: String(localized: "总 Tokens"), value: RoutingFormat.tokens(route.tokens))
                detailRow(label: String(localized: "输出 Tokens"), value: RoutingFormat.tokens(route.out))

                let cache = route.cacheStats
                detailRow(label: String(localized: "Prompt 缓存读取"), value: RoutingFormat.tokens(cache.read))
                detailRow(label: String(localized: "Prompt 缓存写入"), value: RoutingFormat.tokens(cache.write))
                if let rate = cache.rate {
                    detailRow(label: String(localized: "缓存命中率"), value: String(format: "%.1f%%", rate * 100))
                }
            }
        }
        .magpieCard()
    }

    private var metaInfoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            MagpieSectionLabel(title: String(localized: "调用上下文与元数据"))

            VStack(spacing: 8) {
                if let t = route.time {
                    detailRow(label: String(localized: "请求时间"), value: t)
                }
                if let id = route.id as Int64? {
                    detailRow(label: String(localized: "请求序列号"), value: "#\(id)")
                }
                if let key = route.callerKeyName, !key.isEmpty {
                    detailRow(label: String(localized: "网关密钥"), value: RoutingFormat.maskString(key, isMasked: isMasked))
                }
                if let sess = route.session, !sess.isEmpty {
                    detailRow(label: String(localized: "会话 ID"), value: sess)
                }
                if let served = route.served, !served.isEmpty {
                    detailRow(label: String(localized: "应答服务节点"), value: served)
                }
                if let wire = route.effectiveWireModel {
                    detailRow(label: String(localized: "上游实际模型"), value: wire)
                }
            }
        }
        .magpieCard()
    }

    private func errorSection(_ err: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.octagon.fill")
                    .foregroundStyle(MagpieTheme.red)
                Text(String(localized: "错误响应"))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(MagpieTheme.red)
            }

            Text(err)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(MagpieTheme.red)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(MagpieTheme.red.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .magpieCard()
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(MagpieTheme.textMuted)
            Spacer()
            Text(value)
                .font(.caption.weight(.medium))
                .foregroundStyle(MagpieTheme.textPrimary)
        }
    }
}
