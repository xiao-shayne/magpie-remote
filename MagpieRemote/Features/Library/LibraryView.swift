import SwiftUI

/// Library（扩展库）页：读取真实的 `/api/library`，管理共享技能、MCP 服务器与指令。
/// 与官方 Web UI 的 Library 页面结构一致，并采用原生 Apple 交互。
struct LibraryView: View {
    @Environment(AppModel.self) private var app
    @State private var viewModel = LibraryViewModel()
    @State private var piRTK = PiRTKViewModel()
    @State private var tab: LibraryTab = LibraryView.initialTab

    /// DEBUG 联调：`MAGPIE_DEV_LIB_TAB=memory` 直接打开某个 Library 分区。
    private static var initialTab: LibraryTab {
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment["MAGPIE_DEV_LIB_TAB"],
           let value = LibraryTab(rawValue: raw) {
            return value
        }
        #endif
        return .skills
    }
    @State private var searchText = ""
    @State private var selectedSkill: LibrarySkillDTO?
    @State private var selectedServer: LibraryServerDTO?
    @State private var showingAddServer = false
    @State private var showingMarket = false
    @State private var sharedDraft = ""
    @State private var instructionAgents: Set<String> = []
    @State private var primedRevision = -1
    @State private var showingDiscardConfirm = false

    enum LibraryTab: String, CaseIterable, Identifiable {
        case skills
        case servers
        case instructions
        case memory
        case pi
        case rtk
        case bili

        var id: String { rawValue }

        var title: String {
            switch self {
            case .skills: return String(localized: "技能")
            case .servers: return String(localized: "MCP 服务")
            case .instructions: return String(localized: "指令")
            case .memory: return String(localized: "记忆")
            case .pi: return "Pi"
            case .rtk: return "RTK"
            case .bili: return "billion"
            }
        }

        var icon: String {
            switch self {
            case .skills: return "sparkles"
            case .servers: return "server.rack"
            case .instructions: return "text.alignleft"
            case .memory: return "brain"
            case .pi: return "terminal"
            case .rtk: return "arrow.triangle.branch"
            case .bili: return "rectangle.stack.fill"
            }
        }
    }

    private var library: LibraryDTO? { viewModel.library }
    private var skills: [LibrarySkillDTO] { library?.skills ?? [] }
    private var servers: [LibraryServerDTO] { library?.servers ?? [] }
    private var agents: [LibraryAgentDTO] { viewModel.activeAgents }

    private var filteredSkills: [LibrarySkillDTO] {
        guard !searchText.isEmpty else { return skills }
        let q = searchText.lowercased()
        return skills.filter {
            $0.name.lowercased().contains(q)
                || $0.description.lowercased().contains(q)
                || ($0.note?.lowercased().contains(q) ?? false)
        }
    }

    private var filteredServers: [LibraryServerDTO] {
        guard !searchText.isEmpty else { return servers }
        let q = searchText.lowercased()
        return servers.filter {
            $0.name.lowercased().contains(q)
                || $0.commandLine.lowercased().contains(q)
                || ($0.note?.lowercased().contains(q) ?? false)
        }
    }

    private var instructions: LibraryInstructionsDTO? { library?.instructions }

    private var instructionAgentList: [LibraryInstructionsAgentDTO] {
        instructions?.agents ?? []
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    summaryBar
                    tabBar

                    if let error = viewModel.errorMessage {
                        errorBanner(error)
                    }

                    switch tab {
                    case .skills:
                        skillsSection
                    case .servers:
                        serversSection
                    case .instructions:
                        instructionsSection
                    case .memory:
                        MemorySection()
                    case .pi:
                        LibraryPiSection()
                            .environment(piRTK)
                    case .rtk:
                        LibraryRTKSection()
                            .environment(piRTK)
                    case .bili:
                        LibraryBiliSection()
                            .environment(piRTK)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .padding(.bottom, 96)
            }
            .magpiePageBackground()
            .navigationTitle(String(localized: "Library"))
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .searchable(text: $searchText, prompt: String(localized: "搜索技能或 MCP 服务…"))
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        if let client = app.client {
                            Task { await viewModel.sync(client: client) }
                        }
                    } label: {
                        if viewModel.isWorking {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                    }
                    .disabled(viewModel.isWorking)
                    .accessibilityLabel(String(localized: "同步到全部 Agent"))
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            if let client = app.client {
                                Task { await viewModel.load(client: client) }
                            }
                        } label: {
                            Label(String(localized: "重新读取库"), systemImage: "arrow.clockwise")
                        }

                        if tab == .servers {
                            Button {
                                showingAddServer = true
                            } label: {
                                Label(String(localized: "添加 MCP 服务器"), systemImage: "plus")
                            }
                        }

                        if tab == .skills {
                            Divider()
                            Button {
                                if let client = app.client {
                                    Task { await viewModel.checkSkills(client: client) }
                                }
                            } label: {
                                Label(String(localized: "检查技能更新"), systemImage: "arrow.triangle.2.circlepath")
                            }
                            Button {
                                if let client = app.client {
                                    Task { await viewModel.updateAllSkills(client: client) }
                                }
                            } label: {
                                Label(String(localized: "更新全部技能"), systemImage: "arrow.down.circle")
                            }
                        }

                        if tab != .instructions {
                            Divider()
                            Button {
                                showingMarket = true
                            } label: {
                                Label(String(localized: "浏览 Library 市场…"), systemImage: "storefront")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .refreshable {
                if let client = app.client { await viewModel.load(client: client) }
            }
            .task {
                if let client = app.client, viewModel.library == nil {
                    await viewModel.load(client: client)
                }
            }
            .onChange(of: viewModel.revision) {
                primeInstructionsIfNeeded()
            }
            .onAppear {
                primeInstructionsIfNeeded()
            }
            .sheet(item: $selectedSkill) { skill in
                LibrarySkillDetailSheet(
                    skill: skill,
                    agents: agents,
                    displayName: { viewModel.agentName($0) },
                    displayIcon: { viewModel.agentIcon($0) },
                    onSaveAgents: { names in
                        guard let client = app.client else { return }
                        await viewModel.setSkillAgents(client: client, name: skill.name, agents: names)
                    },
                    onToggleHere: { on in
                        guard let client = app.client else { return }
                        await viewModel.setSkillHere(client: client, name: skill.name, on: on)
                    },
                    onRemove: {
                        guard let client = app.client else { return false }
                        await viewModel.removeSkill(client: client, name: skill.name)
                        return true
                    }
                )
            }
            .sheet(item: $selectedServer) { server in
                LibraryServerDetailSheet(
                    server: server,
                    agents: agents,
                    displayName: { viewModel.agentName($0) },
                    displayIcon: { viewModel.agentIcon($0) },
                    onSaveAgents: { names in
                        guard let client = app.client else { return }
                        await viewModel.setServerAgents(client: client, name: server.name, agents: names)
                    },
                    onRemove: {
                        guard let client = app.client else { return false }
                        await viewModel.removeServer(client: client, name: server.name)
                        return true
                    }
                )
            }
            .sheet(isPresented: $showingAddServer) {
                LibraryAddServerSheet(agents: agents) { name, transport, command, args, url, assigned in
                    guard let client = app.client else { return false }
                    return await viewModel.saveServer(
                        client: client,
                        old: "",
                        name: name,
                        transport: transport,
                        command: command,
                        args: args,
                        url: url,
                        agents: assigned
                    )
                }
            }
            .sheet(isPresented: $showingMarket) {
                LibraryMarketSheet(initialKind: tab == .servers ? "servers" : "skills")
                    .environment(viewModel)
            }
        }
    }

    // MARK: - 概览信息栏
    private var summaryBar: some View {
        HStack(spacing: 8) {
            statChip("\(skills.count)", String(localized: "技能"), icon: "sparkles")
            statChip("\(servers.count)", String(localized: "MCP"), icon: "server.rack")
            statChip("\(instructionAgentList.filter { $0.on == true }.count)", String(localized: "指令"), icon: "text.alignleft")

            Spacer()

            if viewModel.isWorking {
                ProgressView().controlSize(.small)
            } else if let action = viewModel.lastAction {
                Text(action)
                    .font(.caption2)
                    .foregroundStyle(MagpieTheme.green)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .magpieCard(padding: 0, cornerRadius: 14)
    }

    private func statChip(_ value: String, _ title: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .rounded))
            Text(title)
                .font(.system(size: 9, weight: .medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(MagpieTheme.pill)
        .foregroundStyle(MagpieTheme.textSecondary)
        .clipShape(Capsule())
    }

    // MARK: - Tab
    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(LibraryTab.allCases) { item in
                    Button {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                            tab = item
                        }
                        MagpieHaptics.light()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: item.icon)
                                .font(.system(size: 11, weight: .semibold))
                            Text(item.title)
                                .font(.system(size: 13, weight: .semibold))
                            if let count = count(for: item) {
                                Text("\(count)")
                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(tab == item ? Color.white.opacity(0.22) : MagpieTheme.pill)
                                    .clipShape(Capsule())
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(tab == item ? MagpieTheme.accent : MagpieTheme.card, in: Capsule())
                        .foregroundStyle(tab == item ? .white : MagpieTheme.textSecondary)
                        .overlay(
                            Capsule().stroke(
                                tab == item ? Color.white.opacity(0.2) : MagpieTheme.borderSubtle,
                                lineWidth: 0.6
                            )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollClipDisabled()
    }

    private func count(for tab: LibraryTab) -> Int? {
        switch tab {
        case .skills: return skills.count
        case .servers: return servers.count
        case .instructions: return instructionAgentList.count
        case .memory: return nil
        case .pi: return piRTK.piView?.pis.count
        case .rtk: return piRTK.rtk?.agents?.count
        case .bili: return piRTK.bili?.agents?.count
        }
    }

    // MARK: - 技能
    private var skillsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Skill Router 顶栏（对齐 upstream dea4c2a5）
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(MagpieTheme.purple.opacity(0.14))
                        .frame(width: 34, height: 34)
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(MagpieTheme.purple)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "Skill Router"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(MagpieTheme.textPrimary)
                    Text(String(localized: "按需向 Agent 路由技能，节省上下文"))
                        .font(.caption2)
                        .foregroundStyle(MagpieTheme.textMuted)
                }
                Spacer(minLength: 8)
                Toggle("", isOn: Binding(
                    get: { library?.skillRouter ?? false },
                    set: { on in
                        guard let client = app.client else { return }
                        Task { await viewModel.setSkillRouter(client: client, on: on) }
                    }
                ))
                .labelsHidden()
                .tint(MagpieTheme.green)
                .disabled(viewModel.isWorking)
            }
            .magpieCard(padding: 12)

            MagpieSectionLabel(
                title: String(localized: "技能"),
                detail: String(localized: "点击查看并分配 Agent")
            )

            if filteredSkills.isEmpty {
                emptyState(
                    icon: "sparkles",
                    title: String(localized: "还没有技能"),
                    subtitle: String(localized: "在 Web 端安装技能后，会在这里统一管理并同步给所有 Agent。")
                )
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(filteredSkills) { skill in
                        Button {
                            selectedSkill = skill
                        } label: {
                            skillCard(skill)
                        }
                        .buttonStyle(MagpiePressableStyle())
                    }
                }
            }
        }
    }

    private func skillCard(_ skill: LibrarySkillDTO) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            skill.isOff
                                ? AnyShapeStyle(MagpieTheme.pill)
                                : AnyShapeStyle(LinearGradient(
                                    colors: [MagpieTheme.accent.opacity(0.9), MagpieTheme.purple.opacity(0.65)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ))
                        )
                        .frame(width: 38, height: 38)

                    Image(systemName: "sparkles")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(skill.isOff ? MagpieTheme.textMuted : .white)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(skill.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(MagpieTheme.textPrimary)
                            .lineLimit(1)

                        if skill.isOff {
                            MagpieStatusChip(text: String(localized: "本机停用"), color: MagpieTheme.textMuted)
                        }
                        if skill.edited == true {
                            MagpieStatusChip(text: String(localized: "已修改"), color: MagpieTheme.amber)
                        }
                    }

                    if !skill.description.isEmpty {
                        Text(skill.description)
                            .font(.caption2)
                            .foregroundStyle(MagpieTheme.textSecondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }

                Spacer(minLength: 4)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MagpieTheme.textMuted.opacity(0.7))
            }

            HStack(spacing: 6) {
                if let kind = skill.kind, !kind.isEmpty {
                    Text(kind.uppercased())
                        .font(.system(size: 8, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(MagpieTheme.pill)
                        .foregroundStyle(MagpieTheme.textMuted)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }

                agentChips(skill.agents ?? [])

                Spacer()

                Text("\((skill.agents ?? []).count) 个 Agent")
                    .font(.caption2)
                    .foregroundStyle(MagpieTheme.textMuted)
            }
        }
        .magpieLiquidCard(padding: 12, cornerRadius: 18)
    }

    private func agentChips(_ ids: [String]) -> some View {
        HStack(spacing: -4) {
            ForEach(Array(ids.prefix(4)), id: \.self) { id in
                MagpieIconView(
                    icon: viewModel.agentIcon(id),
                    name: viewModel.agentName(id),
                    size: 18,
                    cornerRadius: 5
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(MagpieTheme.card, lineWidth: 1.5)
                )
            }
            if ids.count > 4 {
                Text("+\(ids.count - 4)")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(MagpieTheme.textMuted)
                    .padding(.leading, 4)
            }
        }
    }

    // MARK: - MCP
    private var serversSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // MCP Router 顶栏（对齐 upstream 32dc676e + servers/hub-tools + servers/hub-code）
            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(MagpieTheme.cyan.opacity(0.14))
                            .frame(width: 34, height: 34)
                        Image(systemName: "point.3.connected.trianglepath.dotted")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(MagpieTheme.cyan)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "MCP Router"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(MagpieTheme.textPrimary)
                        Text(String(localized: "统一入口路由所有 MCP 服务，支持按需加载与 run_code"))
                            .font(.caption2)
                            .foregroundStyle(MagpieTheme.textMuted)
                    }
                    Spacer(minLength: 8)
                    Toggle("", isOn: Binding(
                        get: { library?.mcpHub ?? false },
                        set: { on in
                            guard let client = app.client else { return }
                            Task { await viewModel.setMCPHub(client: client, on: on) }
                        }
                    ))
                    .labelsHidden()
                    .tint(MagpieTheme.green)
                    .disabled(viewModel.isWorking)
                }

                if library?.mcpHub == true {
                    Divider().background(MagpieTheme.borderSubtle)

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(localized: "按需暴露工具"))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(MagpieTheme.textPrimary)
                            Text(String(localized: "开启时只在需要时列出工具，减少上下文占用"))
                                .font(.caption2)
                                .foregroundStyle(MagpieTheme.textMuted)
                        }
                        Spacer(minLength: 8)
                        Toggle("", isOn: Binding(
                            get: { !(app.state?.settings?.routerAllTools ?? false) },
                            set: { onDemand in
                                guard let client = app.client else { return }
                                Task {
                                    await viewModel.setHubAllTools(client: client, allTools: !onDemand)
                                    await app.refresh()
                                }
                            }
                        ))
                        .labelsHidden()
                        .tint(MagpieTheme.green)
                        .disabled(viewModel.isWorking)
                    }

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(localized: "代码模式 (run_code)"))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(MagpieTheme.textPrimary)
                            Text(String(localized: "允许 Agent 用脚本组合调用 MCP 与技能"))
                                .font(.caption2)
                                .foregroundStyle(MagpieTheme.textMuted)
                        }
                        Spacer(minLength: 8)
                        Toggle("", isOn: Binding(
                            get: { !(app.state?.settings?.routerNoCode ?? false) },
                            set: { on in
                                guard let client = app.client else { return }
                                Task {
                                    await viewModel.setHubCode(client: client, on: on)
                                    await app.refresh()
                                }
                            }
                        ))
                        .labelsHidden()
                        .tint(MagpieTheme.green)
                        .disabled(viewModel.isWorking)
                    }
                }
            }
            .magpieCard(padding: 12)

            HStack {
                MagpieSectionLabel(
                    title: String(localized: "MCP 服务"),
                    detail: String(localized: "stdio / HTTP / SSE")
                )
                Spacer()
                Button {
                    showingAddServer = true
                } label: {
                    Label(String(localized: "添加"), systemImage: "plus")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(MagpieTheme.accent)
            }

            if filteredServers.isEmpty {
                emptyState(
                    icon: "server.rack",
                    title: String(localized: "还没有 MCP 服务"),
                    subtitle: String(localized: "添加一个服务器，所有选中的 Agent 都会获得同一份配置。")
                )
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(filteredServers) { server in
                        Button {
                            selectedServer = server
                        } label: {
                            serverCard(server)
                        }
                        .buttonStyle(MagpiePressableStyle())
                    }
                }
            }
        }
    }

    private func serverCard(_ server: LibraryServerDTO) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [MagpieTheme.cyan.opacity(0.9), Color(hex: "2563eb").opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 38, height: 38)
                    Image(systemName: "server.rack")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(server.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(MagpieTheme.textPrimary)
                            .lineLimit(1)
                        Text(server.transportName)
                            .font(.system(size: 8, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(MagpieTheme.pill)
                            .foregroundStyle(MagpieTheme.textMuted)
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }

                    Text(server.commandLine)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(MagpieTheme.textMuted)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MagpieTheme.textMuted.opacity(0.7))
            }

            HStack(spacing: 6) {
                agentChips(server.agents ?? [])
                Spacer()
                Text("\((server.agents ?? []).count) 个 Agent")
                    .font(.caption2)
                    .foregroundStyle(MagpieTheme.textMuted)
            }
        }
        .magpieLiquidCard(padding: 12, cornerRadius: 18)
    }

    // MARK: - 指令
    private var instructionsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    MagpieSectionLabel(
                        title: String(localized: "共享指令"),
                        detail: String(localized: "写入每个启用的 Agent")
                    )
                    Spacer()
                    Button {
                        saveInstructions()
                    } label: {
                        Text(String(localized: "保存"))
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(MagpiePrimaryButtonStyle(tint: MagpieTheme.accent))
                    .disabled(viewModel.isWorking)
                }

                TextEditor(text: $sharedDraft)
                    .font(.system(size: 12, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 170)
                    .padding(10)
                    .background(MagpieTheme.cardSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(MagpieTheme.borderSubtle, lineWidth: 1)
                    )
                    .overlay(alignment: .topLeading) {
                        if sharedDraft.isEmpty {
                            Text(String(localized: "例如：始终使用简体中文回答，代码注释保持英文。"))
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(MagpieTheme.textMuted.opacity(0.7))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 18)
                                .allowsHitTesting(false)
                        }
                    }

                Text(String(localized: "magpie 只会写入自己管理的那一段；你在 Agent 文件中手写的内容保持不变。"))
                    .font(.caption2)
                    .foregroundStyle(MagpieTheme.textMuted)
            }
            .magpieCard()

            VStack(alignment: .leading, spacing: 8) {
                MagpieSectionLabel(title: String(localized: "接收指令的 Agent"))

                VStack(spacing: 0) {
                    ForEach(Array(instructionAgentList.enumerated()), id: \.element.id) { index, agent in
                        HStack(spacing: 11) {
                            MagpieIconView(icon: agent.icon, name: agent.displayName, size: 28, cornerRadius: 7)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(agent.displayName)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(MagpieTheme.textPrimary)
                                if let path = agent.path, !path.isEmpty {
                                    Text(shortPath(path))
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(MagpieTheme.textMuted)
                                        .lineLimit(1)
                                }
                            }

                            Spacer()

                            Toggle("", isOn: Binding(
                                get: { instructionAgents.contains(agent.agent) },
                                set: { on in
                                    var next = instructionAgents
                                    if on { next.insert(agent.agent) } else { next.remove(agent.agent) }
                                    instructionAgents = next
                                    saveInstructions(agents: Array(next))
                                }
                            ))
                            .labelsHidden()
                            .tint(MagpieTheme.green)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)

                        if index < instructionAgentList.count - 1 {
                            Divider()
                                .background(MagpieTheme.borderSubtle)
                                .padding(.leading, 55)
                        }
                    }
                }
                .magpieCard(padding: 0)
            }
        }
    }

    private func primeInstructionsIfNeeded() {
        guard primedRevision != viewModel.revision, let instructions else { return }
        primedRevision = viewModel.revision
        sharedDraft = instructions.shared ?? ""
        instructionAgents = Set(instructionAgentList.filter { $0.on == true }.map(\.agent))
    }

    private func saveInstructions(agents: [String]? = nil) {
        guard let client = app.client else { return }
        let names = agents ?? Array(instructionAgents)
        Task {
            _ = await viewModel.saveInstructions(client: client, shared: sharedDraft, agents: names)
        }
    }

    private func shortPath(_ path: String) -> String {
        guard let home = library?.home, !home.isEmpty, path.hasPrefix(home) else { return path }
        return "~" + String(path.dropFirst(home.count))
    }

    // MARK: - 通用
    private func emptyState(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 34))
                .foregroundStyle(MagpieTheme.textMuted.opacity(0.65))
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(MagpieTheme.textPrimary)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(MagpieTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .magpieCard()
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(message)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .font(.caption)
        .foregroundStyle(MagpieTheme.red)
        .frame(maxWidth: .infinity, alignment: .leading)
        .magpieCard(padding: 12)
    }
}

// MARK: - 技能详情
private struct LibrarySkillDetailSheet: View {
    let skill: LibrarySkillDTO
    let agents: [LibraryAgentDTO]
    let displayName: (String) -> String
    let displayIcon: (String) -> String?
    let onSaveAgents: ([String]) async -> Void
    let onToggleHere: (Bool) async -> Void
    let onRemove: () async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String>
    @State private var isOff: Bool
    @State private var working = false
    @State private var showingRemoveConfirm = false

    init(
        skill: LibrarySkillDTO,
        agents: [LibraryAgentDTO],
        displayName: @escaping (String) -> String,
        displayIcon: @escaping (String) -> String?,
        onSaveAgents: @escaping ([String]) async -> Void,
        onToggleHere: @escaping (Bool) async -> Void,
        onRemove: @escaping () async -> Bool
    ) {
        self.skill = skill
        self.agents = agents
        self.displayName = displayName
        self.displayIcon = displayIcon
        self.onSaveAgents = onSaveAgents
        self.onToggleHere = onToggleHere
        self.onRemove = onRemove
        _selected = State(initialValue: Set(skill.agents ?? []))
        _isOff = State(initialValue: skill.isOff)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    header

                    if !skill.description.isEmpty {
                        Text(skill.description)
                            .font(.subheadline)
                            .foregroundStyle(MagpieTheme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .magpieCard()
                    }

                    if let note = skill.note, !note.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            MagpieSectionLabel(title: String(localized: "备注"))
                            Text(note)
                                .font(.caption)
                                .foregroundStyle(MagpieTheme.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .magpieCard()
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        MagpieSectionLabel(title: String(localized: "分配给 Agent"))
                        VStack(spacing: 0) {
                            ForEach(Array(agents.enumerated()), id: \.element.id) { index, agent in
                                agentRow(agent)
                                if index < agents.count - 1 {
                                    Divider()
                                        .background(MagpieTheme.borderSubtle)
                                        .padding(.leading, 50)
                                }
                            }
                        }
                        .magpieCard(padding: 0)
                    }

                    Button(role: .destructive) {
                        showingRemoveConfirm = true
                    } label: {
                        Label(String(localized: "从库中移除技能"), systemImage: "trash")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(MagpieTheme.red)
                    .background(MagpieTheme.redSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .padding(16)
            }
            .magpiePageBackground()
            .navigationTitle(skill.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "完成")) { dismiss() }
                }
            }
            .alert(String(localized: "移除这个技能？"), isPresented: $showingRemoveConfirm) {
                Button(String(localized: "移除"), role: .destructive) {
                    working = true
                    Task {
                        let removed = await onRemove()
                        working = false
                        if removed { dismiss() }
                    }
                }
                Button(String(localized: "取消"), role: .cancel) {}
            } message: {
                Text(String(localized: "库中的副本会被移到备份目录，Agent 已同步的链接会在下次同步时移除。"))
            }
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [MagpieTheme.accent, MagpieTheme.purple.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 46, height: 46)
                    Image(systemName: "sparkles")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(skill.name)
                        .font(.headline)
                        .foregroundStyle(MagpieTheme.textPrimary)
                    HStack(spacing: 5) {
                        if let kind = skill.kind, !kind.isEmpty {
                            Text(kind.uppercased())
                        }
                        if let source = skill.source, !source.isEmpty {
                            Text("·")
                            Text(source)
                                .lineLimit(1)
                        }
                    }
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(MagpieTheme.textMuted)
                }

                Spacer()

                if working {
                    ProgressView().controlSize(.small)
                }
            }

            Divider().background(MagpieTheme.borderSubtle)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "在本机启用"))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(MagpieTheme.textPrimary)
                    Text(String(localized: "只影响这台服务器，不改变其他电脑的分配"))
                        .font(.caption2)
                        .foregroundStyle(MagpieTheme.textMuted)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { !isOff },
                    set: { on in
                        isOff = !on
                        Task { await onToggleHere(on) }
                    }
                ))
                .labelsHidden()
                .tint(MagpieTheme.green)
            }
        }
        .magpieCard()
    }

    private func agentRow(_ agent: LibraryAgentDTO) -> some View {
        Button {
            var next = selected
            if next.contains(agent.id) { next.remove(agent.id) } else { next.insert(agent.id) }
            selected = next
            Task { await onSaveAgents(Array(next).sorted()) }
            MagpieHaptics.light()
        } label: {
            HStack(spacing: 11) {
                MagpieIconView(icon: agent.icon, name: agent.displayName, size: 26, cornerRadius: 7)
                Text(agent.displayName)
                    .font(.subheadline)
                    .foregroundStyle(MagpieTheme.textPrimary)
                Spacer()
                Image(systemName: selected.contains(agent.id) ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(selected.contains(agent.id) ? MagpieTheme.accent : MagpieTheme.textMuted.opacity(0.5))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - MCP 详情
private struct LibraryServerDetailSheet: View {
    let server: LibraryServerDTO
    let agents: [LibraryAgentDTO]
    let displayName: (String) -> String
    let displayIcon: (String) -> String?
    let onSaveAgents: ([String]) async -> Void
    let onRemove: () async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String>
    @State private var showingRemoveConfirm = false
    @State private var working = false

    init(
        server: LibraryServerDTO,
        agents: [LibraryAgentDTO],
        displayName: @escaping (String) -> String,
        displayIcon: @escaping (String) -> String?,
        onSaveAgents: @escaping ([String]) async -> Void,
        onRemove: @escaping () async -> Bool
    ) {
        self.server = server
        self.agents = agents
        self.displayName = displayName
        self.displayIcon = displayIcon
        self.onSaveAgents = onSaveAgents
        self.onRemove = onRemove
        _selected = State(initialValue: Set(server.agents ?? []))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [MagpieTheme.cyan, Color(hex: "2563eb").opacity(0.75)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 46, height: 46)
                                Image(systemName: "server.rack")
                                    .font(.system(size: 19, weight: .semibold))
                                    .foregroundStyle(.white)
                            }

                            VStack(alignment: .leading, spacing: 3) {
                                Text(server.name)
                                    .font(.headline)
                                    .foregroundStyle(MagpieTheme.textPrimary)
                                Text(server.transportName)
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(MagpieTheme.textMuted)
                            }
                            Spacer()
                            if working { ProgressView().controlSize(.small) }
                        }

                        Divider().background(MagpieTheme.borderSubtle)

                        Text(server.commandLine)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(MagpieTheme.textSecondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if let note = server.note, !note.isEmpty {
                            Text(note)
                                .font(.caption)
                                .foregroundStyle(MagpieTheme.textMuted)
                        }
                    }
                    .magpieCard()

                    VStack(alignment: .leading, spacing: 8) {
                        MagpieSectionLabel(title: String(localized: "分配给 Agent"))
                        VStack(spacing: 0) {
                            ForEach(Array(agents.enumerated()), id: \.element.id) { index, agent in
                                Button {
                                    var next = selected
                                    if next.contains(agent.id) { next.remove(agent.id) } else { next.insert(agent.id) }
                                    selected = next
                                    Task { await onSaveAgents(Array(next).sorted()) }
                                    MagpieHaptics.light()
                                } label: {
                                    HStack(spacing: 11) {
                                        MagpieIconView(icon: agent.icon, name: agent.displayName, size: 26, cornerRadius: 7)
                                        Text(agent.displayName)
                                            .font(.subheadline)
                                            .foregroundStyle(MagpieTheme.textPrimary)
                                        Spacer()
                                        Image(systemName: selected.contains(agent.id) ? "checkmark.circle.fill" : "circle")
                                            .font(.system(size: 18))
                                            .foregroundStyle(selected.contains(agent.id) ? MagpieTheme.accent : MagpieTheme.textMuted.opacity(0.5))
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 11)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)

                                if index < agents.count - 1 {
                                    Divider()
                                        .background(MagpieTheme.borderSubtle)
                                        .padding(.leading, 50)
                                }
                            }
                        }
                        .magpieCard(padding: 0)
                    }

                    Button(role: .destructive) {
                        showingRemoveConfirm = true
                    } label: {
                        Label(String(localized: "从库中移除服务器"), systemImage: "trash")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(MagpieTheme.red)
                    .background(MagpieTheme.redSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .padding(16)
            }
            .magpiePageBackground()
            .navigationTitle(String(localized: "MCP 服务器"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "完成")) { dismiss() }
                }
            }
            .alert(String(localized: "移除这个服务器？"), isPresented: $showingRemoveConfirm) {
                Button(String(localized: "移除"), role: .destructive) {
                    working = true
                    Task {
                        let removed = await onRemove()
                        working = false
                        if removed { dismiss() }
                    }
                }
                Button(String(localized: "取消"), role: .cancel) {}
            } message: {
                Text(String(localized: "服务器会从所有 Agent 的配置中移除。"))
            }
        }
    }
}

// MARK: - 添加 MCP
private struct LibraryAddServerSheet: View {
    let agents: [LibraryAgentDTO]
    let onSave: (String, String, String, [String], String, [String]) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var transport = "stdio"
    @State private var command = ""
    @State private var arguments = ""
    @State private var url = ""
    @State private var selected: Set<String> = []
    @State private var working = false
    @State private var errorMessage: String? = nil

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && (transport == "stdio"
                ? !command.trimmingCharacters(in: .whitespaces).isEmpty
                : !url.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(String(localized: "名称（例如 github）"), text: $name)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    Picker(String(localized: "传输方式"), selection: $transport) {
                        Text("stdio").tag("stdio")
                        Text("HTTP").tag("http")
                        Text("SSE").tag("sse")
                    }

                    if transport == "stdio" {
                        TextField(String(localized: "命令（例如 npx）"), text: $command)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .font(.system(.body, design: .monospaced))
                        TextField(String(localized: "参数，以空格分隔"), text: $arguments)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .font(.system(.body, design: .monospaced))
                    } else {
                        TextField(String(localized: "服务器 URL"), text: $url)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            .font(.system(.body, design: .monospaced))
                    }
                } header: {
                    Text(String(localized: "服务器"))
                }

                Section {
                    ForEach(agents) { agent in
                        Button {
                            if selected.contains(agent.id) { selected.remove(agent.id) } else { selected.insert(agent.id) }
                        } label: {
                            HStack(spacing: 10) {
                                MagpieIconView(icon: agent.icon, name: agent.displayName, size: 24, cornerRadius: 6)
                                Text(agent.displayName)
                                    .foregroundStyle(MagpieTheme.textPrimary)
                                Spacer()
                                Image(systemName: selected.contains(agent.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selected.contains(agent.id) ? MagpieTheme.accent : MagpieTheme.textMuted.opacity(0.5))
                            }
                        }
                    }
                } header: {
                    Text(String(localized: "分配给 Agent"))
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(MagpieTheme.red)
                    }
                }
            }
            .navigationTitle(String(localized: "添加 MCP 服务器"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "取消")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save()
                    } label: {
                        if working { ProgressView().controlSize(.small) } else { Text(String(localized: "添加")) }
                    }
                    .disabled(!canSave || working)
                }
            }
        }
    }

    private func save() {
        working = true
        errorMessage = nil
        Task {
            let args = arguments
                .split(whereSeparator: { $0 == " " || $0 == "\n" })
                .map(String.init)
            let ok = await onSave(
                name.trimmingCharacters(in: .whitespaces),
                transport,
                command.trimmingCharacters(in: .whitespaces),
                args,
                url.trimmingCharacters(in: .whitespaces),
                Array(selected).sorted()
            )
            working = false
            if ok {
                dismiss()
            } else {
                errorMessage = String(localized: "保存失败，请检查名称是否重复或命令是否有效。")
            }
        }
    }
}
