import SwiftUI
import UIKit

/// 历史会话页：1:1 对齐官方 Web / 客户端设计。
/// 支持 Agent 品牌标识、Token 开销、花费、检索以及完整 Transcript 对话流查看。
struct SessionsView: View {
    @Environment(AppModel.self) private var app
    @Namespace private var zoomNamespace
    @State private var viewModel = SessionsViewModel()
    @State private var searchText = ""
    @State private var showingManage = SessionsView.devOpensManage

    /// DEBUG 联调：`MAGPIE_DEV_SESSIONS_MANAGE=1` 启动即打开会话管理。
    private static var devOpensManage: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.environment["MAGPIE_DEV_SESSIONS_MANAGE"] == "1"
        #else
        return false
        #endif
    }
    @State private var selectedAgent = ""

    private var agents: [String] {
        Array(Set(viewModel.sessions.map(\.agent))).sorted()
    }

    private var filteredSessions: [SessionDTO] {
        var list = viewModel.sessions
        if !selectedAgent.isEmpty {
            list = list.filter { $0.agent == selectedAgent }
        }
        guard !searchText.isEmpty else { return list }
        return list.filter {
            $0.displayTitle.localizedCaseInsensitiveContains(searchText)
                || $0.agent.localizedCaseInsensitiveContains(searchText)
                || $0.id.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var totalTokens: Int {
        filteredSessions.reduce(0) { $0 + ($1.input ?? 0) + ($1.output ?? 0) }
    }

    private var totalCost: Double {
        filteredSessions.reduce(0) { $0 + ($1.cost ?? 0) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if let error = viewModel.errorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text(error)
                        }
                        .font(.subheadline)
                        .foregroundStyle(MagpieTheme.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .magpieCard()
                    }

                    statsCard
                    agentFilter

                    if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        saidSearchSection
                    }

                    if filteredSessions.isEmpty && viewModel.saidHits.isEmpty && !viewModel.isSearchingSaid {
                        emptyState
                    } else if !filteredSessions.isEmpty {
                        if !viewModel.saidHits.isEmpty {
                            MagpieSectionLabel(
                                title: String(localized: "匹配标题的会话"),
                                detail: "\(filteredSessions.count)"
                            )
                        }
                        MagpieGlassGroup(spacing: 10) {
                            LazyVStack(spacing: 10) {
                                ForEach(filteredSessions) { session in
                                    NavigationLink(value: session) {
                                        SessionCard(session: session)
                                    }
                                    .buttonStyle(.plain)
                                    .matchedTransitionSource(id: session.id, in: zoomNamespace)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .padding(.bottom, 96)
            }
            .magpiePageBackground()
            .searchable(text: $searchText, prompt: String(localized: "搜索会话标题、对话内容或 Agent…"))
            .task(id: "\(searchText)|\(selectedAgent)") {
                let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                if q.isEmpty {
                    viewModel.saidHits = []
                    return
                }
                try? await Task.sleep(for: .milliseconds(300))
                if Task.isCancelled { return }
                if let client = app.client {
                    await viewModel.searchSaid(client: client, query: q, agent: selectedAgent)
                }
            }
            .navigationTitle(String(localized: "Sessions"))
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .navigationDestination(for: SessionDTO.self) { session in
                SessionDetailView(session: session)
                    .environment(viewModel)
                    .navigationTransition(.zoom(sourceID: session.id, in: zoomNamespace))
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            if let client = app.client {
                                Task { await viewModel.load(client: client) }
                            }
                        } label: {
                            Label(String(localized: "刷新"), systemImage: "arrow.clockwise")
                        }
                        Button {
                            showingManage = true
                        } label: {
                            Label(String(localized: "会话管理…"), systemImage: "slider.horizontal.3")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.body.weight(.medium))
                    }
                }
            }
            .sheet(isPresented: $showingManage) {
                SessionsManageSheet()
            }
            .overlay {
                if viewModel.isLoading && viewModel.sessions.isEmpty {
                    ProgressView(String(localized: "加载会话中…"))
                }
            }
            .task {
                if let client = app.client, viewModel.sessions.isEmpty {
                    await viewModel.load(client: client)
                }
            }
            .refreshable {
                if let client = app.client {
                    await viewModel.load(client: client)
                }
            }
        }
    }

    private var statsCard: some View {
        HStack(spacing: 0) {
            sessionStat(String(localized: "会话"), "\(filteredSessions.count)", tint: MagpieTheme.accent)
            divider
            sessionStat(String(localized: "Tokens"), UsageDTO.formatTokens(totalTokens), tint: MagpieTheme.purple)
            divider
            sessionStat(String(localized: "费用"), String(format: "$%.2f", totalCost), tint: MagpieTheme.green)
            divider
            sessionStat(String(localized: "Agents"), "\(agents.count)", tint: MagpieTheme.cyan)
        }
        .magpieLiquidCard(padding: 13, cornerRadius: 18)
    }

    private func sessionStat(_ title: String, _ value: String, tint: Color) -> some View {
        VStack(spacing: 3) {
            MagpieGradientNumber(text: value, tint: tint, size: 18)
            Text(title)
                .font(.system(size: 9.5))
                .foregroundStyle(MagpieTheme.textMuted)
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle()
            .fill(MagpieTheme.borderSubtle)
            .frame(width: 1, height: 24)
    }

    private var agentFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                agentChip("", String(localized: "全部"))
                ForEach(agents, id: \.self) { agent in
                    agentChip(agent, viewModel.sessions.first { $0.agent == agent }?.displayAgent ?? agent)
                }
            }
        }
        .scrollClipDisabled()
    }

    private func agentChip(_ id: String, _ title: String) -> some View {
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                selectedAgent = id
            }
            MagpieHaptics.light()
        } label: {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(selectedAgent == id ? MagpieTheme.accentSoft : MagpieTheme.pill)
                .foregroundStyle(selectedAgent == id ? MagpieTheme.accent : MagpieTheme.textSecondary)
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(
                        selectedAgent == id ? MagpieTheme.accent.opacity(0.3) : MagpieTheme.borderSubtle,
                        lineWidth: 0.7
                    )
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var saidSearchSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                MagpieSectionLabel(
                    title: String(localized: "对话内容匹配"),
                    detail: viewModel.saidHits.isEmpty ? nil : "\(viewModel.saidHits.count)\(viewModel.saidCut ? "+" : "")"
                )
                Spacer()
                if viewModel.isSearchingSaid {
                    ProgressView().controlSize(.small)
                }
            }

            if !viewModel.saidHits.isEmpty {
                LazyVStack(spacing: 8) {
                    ForEach(viewModel.saidHits) { item in
                        NavigationLink(value: item.asSessionDTO()) {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 7) {
                                    MagpieIconView(icon: item.agent, name: item.agent, size: 18, cornerRadius: 5)
                                    Text(item.displayTitle)
                                        .font(.system(size: 13.5, weight: .semibold))
                                        .foregroundStyle(MagpieTheme.textPrimary)
                                        .lineLimit(1)
                                    Spacer(minLength: 4)
                                    if let role = item.hit.role, !role.isEmpty {
                                        MagpieStatusChip(text: role, color: MagpieTheme.cyan)
                                    }
                                }

                                let before = item.hit.before ?? ""
                                let match = item.hit.match ?? ""
                                let after = item.hit.after ?? ""
                                Text("\(Text(before).foregroundStyle(MagpieTheme.textMuted))\(Text(match).foregroundStyle(MagpieTheme.accent).bold())\(Text(after).foregroundStyle(MagpieTheme.textMuted))")
                                    .font(.caption)
                                    .lineLimit(3)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .magpieLiquidCard(padding: 11, cornerRadius: 16)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 72, height: 72)
                    .overlay(Circle().stroke(.white.opacity(0.16), lineWidth: 0.8))
                    .shadow(color: MagpieTheme.accent.opacity(0.1), radius: 10, y: 4)
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 28))
                    .foregroundStyle(MagpieTheme.textMuted)
            }
            Text(String(localized: "暂无会话历史"))
                .font(.headline)
                .foregroundStyle(MagpieTheme.textPrimary)
            Text(String(localized: "当有 Agent 通过 magpie 网关发起调用时，历史记录将自动归集在此。"))
                .font(.subheadline)
                .foregroundStyle(MagpieTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

// MARK: - 原版风格 Session 卡片
private struct SessionCard: View {
    let session: SessionDTO

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                MagpieIconView(icon: session.agent, name: session.displayAgent, size: 20, cornerRadius: 5)

                Text(session.displayAgent)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MagpieTheme.textPrimary)

                Spacer()

                if let last = session.last {
                    Text(String(last.prefix(16)).replacingOccurrences(of: "T", with: " "))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(MagpieTheme.textMuted)
                }
            }

            Text(session.displayTitle)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(MagpieTheme.textPrimary)
                .lineLimit(2)

            Divider().background(MagpieTheme.borderSubtle)

            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Image(systemName: "number")
                    Text(session.formattedTokens)
                }
                .font(.caption2.weight(.medium))
                .foregroundStyle(MagpieTheme.textMuted)

                HStack(spacing: 4) {
                    Image(systemName: "dollarsign")
                    Text(session.formattedCost)
                }
                .font(.caption2.weight(.medium))
                .foregroundStyle(MagpieTheme.green)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(MagpieTheme.textMuted)
            }
        }
        .magpieLiquidCard(padding: 12, cornerRadius: 18)
    }
}

// MARK: - 会话详细对话流查看器 (Transcript View)
private struct SessionDetailView: View {
    let session: SessionDTO
    @Environment(AppModel.self) private var app
    @Environment(SessionsViewModel.self) private var viewModel
    @State private var transcript: TranscriptDTO?
    @State private var isLoadingTranscript = false
    @State private var isExporting = false
    @State private var exportPath: String?
    @State private var carryResult: SessionCarryResultDTO?
    @State private var actionError: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // 顶部会话元数据指标卡
                headerMetricsCard

                // 对话流列表
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(String(localized: "完整对话流 (Transcript)"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(MagpieTheme.textMuted)
                        Spacer()
                        if isLoadingTranscript {
                            ProgressView().controlSize(.small)
                        }
                    }

                    if let transcript, !transcript.parts.isEmpty {
                        LazyVStack(spacing: 12) {
                            ForEach(transcript.parts) { part in
                                messageBubble(part)
                            }
                        }
                    } else if !isLoadingTranscript {
                        fallbackOverview
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .magpiePageBackground()
        .navigationTitle(String(localized: "会话详情"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        copyMarkdown()
                    } label: {
                        Label(String(localized: "复制 Markdown"), systemImage: "doc.on.doc")
                    }

                    Button {
                        exportToServer()
                    } label: {
                        Label(String(localized: "导出到服务器 Downloads"), systemImage: "externaldrive.badge.arrow.down")
                    }

                    if let carry = session.carry, !carry.isEmpty {
                        Menu {
                            ForEach(carry) { item in
                                Button(item.agent) {
                                    carrySession(to: item.agent)
                                }
                            }
                        } label: {
                            Label(String(localized: "转换为其他 Agent"), systemImage: "arrow.triangle.swap")
                        }
                    }
                } label: {
                    if isExporting {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
                .disabled(isExporting)
            }
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
            String(localized: "已转换为新会话"),
            isPresented: Binding(
                get: { carryResult != nil },
                set: { if !$0 { carryResult = nil } }
            )
        ) {
            Button(String(localized: "复制启动命令")) {
                if let command = carryResult?.command { UIPasteboard.general.string = command }
                carryResult = nil
            }
            Button(String(localized: "完成"), role: .cancel) { carryResult = nil }
        } message: {
            Text(carryResult?.command ?? carryResult?.id ?? "")
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
        .task {
            loadTranscript()
        }
    }

    /// 官方 `/api/sessions/markdown`：把整段会话导出为 Markdown 文本。
    private func copyMarkdown() {
        guard let client = app.client else { return }
        isExporting = true
        Task {
            defer { isExporting = false }
            if let text = await viewModel.fetchMarkdown(
                client: client,
                agent: session.agent,
                id: session.id
            ), !text.isEmpty {
                UIPasteboard.general.string = text
                MagpieHaptics.success()
            } else {
                MagpieHaptics.medium()
                actionError = viewModel.errorMessage ?? String(localized: "读取 Markdown 失败")
            }
        }
    }

    private func exportToServer() {
        guard let client = app.client else { return }
        isExporting = true
        Task {
            defer { isExporting = false }
            if let path = await viewModel.exportMarkdown(
                client: client,
                agent: session.agent,
                id: session.id
            ) {
                exportPath = path
                MagpieHaptics.success()
            } else {
                actionError = viewModel.errorMessage ?? String(localized: "导出失败")
            }
        }
    }

    private func carrySession(to target: String) {
        guard let client = app.client else { return }
        isExporting = true
        Task {
            defer { isExporting = false }
            if let result = await viewModel.carry(
                client: client,
                agent: session.agent,
                id: session.id,
                to: target
            ) {
                carryResult = result
                MagpieHaptics.success()
            } else {
                actionError = viewModel.errorMessage ?? String(localized: "转换失败")
            }
        }
    }

    private var headerMetricsCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                MagpieIconView(icon: session.agent, name: session.displayAgent, size: 38, cornerRadius: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.displayAgent)
                        .font(.headline)
                        .foregroundStyle(MagpieTheme.textPrimary)
                    Text(session.id)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(MagpieTheme.textMuted)
                }
                Spacer()
            }

            Divider().background(MagpieTheme.borderSubtle)

            HStack {
                metricCol(title: String(localized: "总消耗"), value: session.formattedTokens, color: MagpieTheme.accent)
                Spacer()
                metricCol(title: String(localized: "预估费用"), value: session.formattedCost, color: MagpieTheme.green)
                Spacer()
                if let last = session.last {
                    metricCol(title: String(localized: "时间"), value: String(last.prefix(10)), color: MagpieTheme.textMuted)
                }
            }
        }
        .magpieCard()
    }

    private func metricCol(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(MagpieTheme.textMuted)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
        }
    }

    // 单个消息片段
    @ViewBuilder
    private func messageBubble(_ part: TranscriptPartDTO) -> some View {
        if part.role == "user" {
            HStack {
                Spacer(minLength: 40)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(part.text)
                        .font(.system(size: 14))
                        .foregroundStyle(.white)
                        .padding(12)
                        .background(MagpieTheme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
        } else if part.kind == "thinking" {
            DisclosureGroup {
                Text(part.text)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(MagpieTheme.textSecondary)
                    .padding(.top, 4)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "brain.head.profile")
                        .font(.caption)
                    Text(String(localized: "思考过程 (Thinking)"))
                        .font(.caption.weight(.medium))
                }
                .foregroundStyle(MagpieTheme.textMuted)
            }
            .padding(10)
            .background(MagpieTheme.pill.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        } else if part.kind == "tool_use" || part.kind == "tool_result" {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "wrench.and.screwdriver.fill")
                        .font(.caption2)
                    Text(part.name ?? String(localized: "Tool Call"))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                    Spacer()
                    Text(part.kind)
                        .font(.system(size: 9, weight: .medium))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(MagpieTheme.pill)
                        .clipShape(Capsule())
                }
                .foregroundStyle(MagpieTheme.accent)

                Text(part.text)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(MagpieTheme.textPrimary)
                    .lineLimit(8)
            }
            .padding(10)
            .background(MagpieTheme.cardSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(MagpieTheme.borderSubtle, lineWidth: 1)
            )
        } else {
            // Assistant 文本气泡
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        MagpieIconView(icon: session.agent, name: session.displayAgent, size: 16, cornerRadius: 4)
                        Text(session.displayAgent)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(MagpieTheme.textMuted)
                    }

                    Text(part.text)
                        .font(.system(size: 14))
                        .foregroundStyle(MagpieTheme.textPrimary)
                }
                .padding(12)
                .background(MagpieTheme.card)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(MagpieTheme.borderSubtle, lineWidth: 1)
                )
                Spacer(minLength: 40)
            }
        }
    }

    private var fallbackOverview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "首条提问 / 标题"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(MagpieTheme.textMuted)
            Text(session.displayTitle)
                .font(.body)
                .foregroundStyle(MagpieTheme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .magpieCard()
    }

    private func loadTranscript() {
        guard let client = app.client else { return }
        isLoadingTranscript = true
        Task {
            defer { isLoadingTranscript = false }
            self.transcript = await viewModel.fetchTranscript(client: client, agent: session.agent, id: session.id)
        }
    }
}
