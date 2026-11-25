import SwiftUI

/// Masking（脱敏）页：数据全部来自真实的 `/api/masking/*` 接口。
/// 包含概览、规则开关、真实预览沙盒与请求级脱敏记录。
struct MaskingView: View {
    @Environment(AppModel.self) private var app
    @State private var viewModel = MaskingViewModel()
    @State private var sample = """
    curl https://api.example.com/v1 \\
      -H "Authorization: Bearer sk-ant-api03-demo-key-value" \\
      -d '{"email":"developer@example.com","phone":"+1 415 555 0132"}'
    """
    @State private var showingClearConfirm = false
    @State private var selectedRecord: MaskingRecordDTO?
    @State private var lastSearchedQuery = ""

    private var settings: SettingsDTO? { app.state?.settings }
    private var isOn: Bool { settings?.redact ?? false }

    var body: some View {
        MagpieNavigationContainer {
            ScrollView {
                VStack(spacing: 18) {
                    header
                    statsGrid
                    rulesCard
                    tryCard
                    recordsSection
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .magpiePageBackground()
            .searchable(text: $viewModel.query, prompt: String(localized: "搜索脱敏过的词或占位符…"))
            .task(id: viewModel.query) {
                guard viewModel.query != lastSearchedQuery else { return }
                try? await Task.sleep(for: .milliseconds(300))
                if Task.isCancelled { return }
                lastSearchedQuery = viewModel.query
                if let client = app.client {
                    await viewModel.reloadRecords(client: client)
                }
            }
            .navigationTitle(String(localized: "Masking"))
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Picker(String(localized: "统计范围"), selection: Binding(
                            get: { viewModel.days },
                            set: { newValue in
                                viewModel.days = newValue
                                Task { if let client = app.client { await viewModel.load(client: client) } }
                            }
                        )) {
                            Text(String(localized: "最近 7 天")).tag(7)
                            Text(String(localized: "最近 30 天")).tag(30)
                        }

                        Toggle(String(localized: "只看被拦截的请求"), isOn: Binding(
                            get: { viewModel.blockedOnly },
                            set: { newValue in
                                viewModel.blockedOnly = newValue
                                Task { if let client = app.client { await viewModel.load(client: client) } }
                            }
                        ))

                        Picker(String(localized: "类型"), selection: Binding(
                            get: { viewModel.kindFilter },
                            set: { newValue in
                                viewModel.kindFilter = newValue
                                Task { if let client = app.client { await viewModel.load(client: client) } }
                            }
                        )) {
                            Text(String(localized: "全部类型")).tag("")
                            ForEach(viewModel.summary?.kinds ?? []) { kind in
                                Text(MaskingFormat.kindName(kind.name)).tag(kind.name)
                            }
                        }

                        Picker(String(localized: "Agent"), selection: Binding(
                            get: { viewModel.agentFilter },
                            set: { newValue in
                                viewModel.agentFilter = newValue
                                Task { if let client = app.client { await viewModel.load(client: client) } }
                            }
                        )) {
                            Text(String(localized: "全部 Agent")).tag("")
                            ForEach(viewModel.summary?.agents ?? []) { item in
                                Text(item.name).tag(item.name)
                            }
                        }

                        Picker(String(localized: "提供方"), selection: Binding(
                            get: { viewModel.providerFilter },
                            set: { newValue in
                                viewModel.providerFilter = newValue
                                Task { if let client = app.client { await viewModel.load(client: client) } }
                            }
                        )) {
                            Text(String(localized: "全部提供方")).tag("")
                            ForEach(viewModel.summary?.providers ?? []) { item in
                                Text(item.name).tag(item.name)
                            }
                        }

                        Divider()

                        Button {
                            Task { if let client = app.client { await viewModel.load(client: client) } }
                        } label: {
                            Label(String(localized: "刷新"), systemImage: "arrow.clockwise")
                        }

                        Button(role: .destructive) {
                            showingClearConfirm = true
                        } label: {
                            Label(String(localized: "清空全部记录"), systemImage: "trash")
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
                if let client = app.client { await viewModel.load(client: client) }
            }
            .onChange(of: viewModel.days) {
                Task { if let client = app.client { await viewModel.load(client: client) } }
            }
            .alert(String(localized: "清空全部脱敏记录？"), isPresented: $showingClearConfirm) {
                Button(String(localized: "清空"), role: .destructive) {
                    Task { if let client = app.client { _ = await viewModel.clearRecords(client: client) } }
                }
                Button(String(localized: "取消"), role: .cancel) {}
            } message: {
                Text(String(localized: "记录只保存在服务器内存与本地文件中，清空后无法恢复。"))
            }
            .sheet(item: $selectedRecord) { record in
                MaskingRecordDetailView(
                    record: record,
                    onSent: { key in
                        guard let client = app.client else { return nil }
                        return await viewModel.fetchSent(client: client, key: key)
                    }
                ) { placeholder in
                    guard let client = app.client else { return false }
                    return await viewModel.allow(client: client, placeholder: placeholder)
                }
                .presentationDetents([.medium, .large])
            }
        }
    }

    // MARK: - 头部
    private var header: some View {
        VStack(spacing: 14) {
            MagpiePageHeader(
                title: String(localized: "脱敏与隐私"),
                subtitle: String(localized: "请求离开设备前，凭证与个人信息已被替换"),
                icon: isOn ? "shield.lefthalf.filled" : "shield.slash",
                tint: isOn ? MagpieTheme.green : MagpieTheme.amber
            )

            HStack(spacing: 10) {
                if isOn {
                    HStack(spacing: 4) {
                        MagpiePulseDot(color: MagpieTheme.green)
                        Text(String(localized: "防护已开启"))
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3.5)
                    .background(MagpieTheme.greenSoft, in: Capsule())
                    .foregroundStyle(MagpieTheme.green)
                } else {
                    MagpieStatusChip(
                        text: String(localized: "防护已关闭"),
                        color: MagpieTheme.amber,
                        icon: "exclamationmark.shield.fill"
                    )
                }

                if let since = viewModel.summary?.since, !since.isEmpty {
                    MagpieStatusChip(
                        text: String(localized: "自 \(since)"),
                        color: MagpieTheme.textSecondary,
                        icon: "calendar"
                    )
                }

                Spacer()
            }
        }
        .magpieCard()
    }

    // MARK: - 统计
    @ViewBuilder
    private var statsGrid: some View {
        if let summary = viewModel.summary {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                statCard(
                    String(localized: "检查的请求"),
                    value: "\(summary.requests)",
                    icon: "arrow.left.arrow.right",
                    tint: MagpieTheme.accent
                )
                statCard(
                    String(localized: "替换的值"),
                    value: "\(summary.n)",
                    icon: "eye.slash.fill",
                    tint: MagpieTheme.green
                )
                statCard(
                    String(localized: "不同的值"),
                    value: "\(summary.distinct)",
                    icon: "number",
                    tint: MagpieTheme.cyan
                )
                statCard(
                    String(localized: "被拦截的请求"),
                    value: "\(summary.blocked ?? 0)",
                    icon: "hand.raised.fill",
                    tint: (summary.blocked ?? 0) > 0 ? MagpieTheme.red : MagpieTheme.textMuted
                )
            }
        }
    }

    private func statCard(_ title: String, value: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
                Spacer()
            }
            MagpieGradientNumber(text: value, tint: tint, size: 25)
            Text(title)
                .font(.caption2)
                .foregroundStyle(MagpieTheme.textMuted)
        }
        .magpieLiquidCard(padding: 14, cornerRadius: 18)
    }

    // MARK: - 规则
    private var rulesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            MagpieSectionLabel(title: String(localized: "脱敏规则"), detail: String(localized: "即时生效"))

            VStack(spacing: 0) {
                ruleRow(
                    title: String(localized: "凭证与密钥"),
                    subtitle: String(localized: "API Key、私钥、Token、密码"),
                    icon: "key.fill",
                    isOn: Binding(
                        get: { settings?.redact ?? false },
                        set: { setSetting("redact", $0) }
                    )
                )

                divider

                ruleRow(
                    title: String(localized: "个人信息 (PII)"),
                    subtitle: String(localized: "邮箱、电话、证件与银行卡号"),
                    icon: "person.text.rectangle",
                    isOn: Binding(
                        get: { settings?.redactPersonal ?? false },
                        set: { setSetting("redactPersonal", $0) }
                    )
                )

                divider

                ruleRow(
                    title: String(localized: "保持密钥形状"),
                    subtitle: String(localized: "用同格式的假密钥替换，避免上游校验失败"),
                    icon: "signature",
                    isOn: Binding(
                        get: { settings?.redactShape ?? false },
                        set: { setSetting("redactShape", $0) }
                    )
                )

                divider

                ruleRow(
                    title: String(localized: "本地模型识别"),
                    subtitle: String(localized: "在服务器本地识别规则找不到的姓名与地址"),
                    icon: "brain.head.profile",
                    isOn: Binding(
                        get: { settings?.redactModel ?? false },
                        set: { setSetting("redactModel", $0) }
                    )
                )

                divider

                ruleRow(
                    title: String(localized: "自定义词忽略大小写"),
                    subtitle: String(localized: "开启后自定义敏感词表不区分大小写匹配"),
                    icon: "textformat",
                    isOn: Binding(
                        get: { settings?.redactWordsAnyCase ?? false },
                        set: { setSetting("redactWordsAnyCase", $0) }
                    )
                )
            }
            .magpieCard(padding: 0)
        }
    }

    private var divider: some View {
        Divider().background(MagpieTheme.borderSubtle).padding(.leading, 52)
    }

    private func ruleRow(title: String, subtitle: String, icon: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(MagpieTheme.accentSoft)
                    .frame(width: 30, height: 30)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MagpieTheme.accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(MagpieTheme.textPrimary)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(MagpieTheme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(MagpieTheme.green)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - 真实预览
    private var tryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                MagpieSectionLabel(title: String(localized: "试一试"), detail: nil)
                Spacer()
                Button {
                    Task { if let client = app.client { await viewModel.runPreview(client: client, text: sample) } }
                } label: {
                    if viewModel.isPreviewing {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(String(localized: "预览"))
                    }
                }
                .buttonStyle(MagpiePrimaryButtonStyle(tint: MagpieTheme.green))
            }

            TextEditor(text: $sample)
                .font(.system(size: 11, design: .monospaced))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 84)
                .padding(10)
                .background(MagpieTheme.cardSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(MagpieTheme.borderSubtle, lineWidth: 1)
                )

            if let preview = viewModel.preview {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Text(String(localized: "发送给厂商的内容"))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(MagpieTheme.textMuted)
                        Spacer()
                        if preview.off == true {
                            MagpieStatusChip(text: String(localized: "脱敏已关闭"), color: MagpieTheme.amber)
                        } else {
                            MagpieStatusChip(
                                text: String(localized: "\(preview.hits.count) 处替换"),
                                color: preview.hits.isEmpty ? MagpieTheme.textMuted : MagpieTheme.green
                            )
                        }
                    }

                    Text(preview.text.isEmpty ? String(localized: "（没有内容）") : preview.text)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(MagpieTheme.textPrimary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(
                            LinearGradient(
                                colors: [MagpieTheme.greenSoft.opacity(0.55), MagpieTheme.cardSecondary],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    if !preview.hits.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(preview.hits) { hit in
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(MaskingFormat.kindName(hit.kind))
                                            .font(.system(size: 9, weight: .bold))
                                        Text(MaskingFormat.byName(hit.by))
                                            .font(.system(size: 8))
                                            .opacity(0.75)
                                    }
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 4)
                                    .background(MagpieTheme.accentSoft)
                                    .foregroundStyle(MagpieTheme.accent)
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                }
                            }
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if let error = viewModel.previewError {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(MagpieTheme.red)
            }
        }
        .magpieCard()
    }

    // MARK: - 记录
    private var recordsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                MagpieSectionLabel(
                    title: String(localized: "最近记录"),
                    detail: viewModel.blockedOnly ? String(localized: "仅拦截") : nil
                )
                Spacer()
                if viewModel.isLoading && viewModel.records.isEmpty {
                    ProgressView().controlSize(.small)
                }
            }

            if let error = viewModel.errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(error)
                }
                .font(.caption)
                .foregroundStyle(MagpieTheme.red)
                .frame(maxWidth: .infinity, alignment: .leading)
                .magpieCard()
            }

            if viewModel.hasUnknownSearchValues && !viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                HStack(spacing: 7) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(MagpieTheme.amber)
                    Text(String(localized: "部分重启前的记录原文已不在内存中，无法按原词检索，仅支持按占位符匹配。"))
                        .font(.caption2)
                        .foregroundStyle(MagpieTheme.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .magpieCard(padding: 10)
            }

            if viewModel.records.isEmpty {
                emptyRecords
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(viewModel.records) { record in
                        Button {
                            selectedRecord = record
                        } label: {
                            recordRow(record)
                        }
                        .buttonStyle(MagpiePressableStyle())
                    }
                }

                if viewModel.hasMore {
                    Button {
                        Task { if let client = app.client { await viewModel.loadMore(client: client) } }
                    } label: {
                        HStack {
                            if viewModel.isLoadingMore {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "arrow.down.circle")
                            }
                            Text(String(localized: "加载更早的记录"))
                        }
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(MagpieTheme.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isLoadingMore)
                }
            }
        }
    }

    private func recordRow(_ record: MaskingRecordDTO) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(record.isBlocked ? MagpieTheme.redSoft : MagpieTheme.greenSoft)
                    .frame(width: 36, height: 36)
                Image(systemName: record.isBlocked ? "hand.raised.fill" : "eye.slash.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(record.isBlocked ? MagpieTheme.red : MagpieTheme.green)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(record.model?.isEmpty == false ? record.model! : (record.what ?? String(localized: "请求")))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(MagpieTheme.textPrimary)
                        .lineLimit(1)

                    if record.isBlocked {
                        MagpieStatusChip(text: String(localized: "已拦截"), color: MagpieTheme.red)
                    }
                }

                HStack(spacing: 5) {
                    if let agent = record.agent, !agent.isEmpty {
                        Text(agent)
                    }
                    if let provider = record.provider, !provider.isEmpty {
                        Text("·")
                        Text(provider)
                    }
                    Text("·")
                    Text(MaskingFormat.relative(record.date))
                }
                .font(.caption2)
                .foregroundStyle(MagpieTheme.textMuted)
                .lineLimit(1)

                if let hits = record.hits, !hits.isEmpty {
                    Text(String(localized: "命中：\(hits.joined(separator: ", "))"))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(MagpieTheme.accent)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 3) {
                Text("\(record.n)")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(record.isBlocked ? MagpieTheme.red : MagpieTheme.green)
                Text(String(localized: "处"))
                    .font(.system(size: 9))
                    .foregroundStyle(MagpieTheme.textMuted)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(MagpieTheme.textMuted.opacity(0.7))
        }
        .magpieCard(padding: 12)
    }

    private var emptyRecords: some View {
        VStack(spacing: 10) {
            Image(systemName: "shield.checkered")
                .font(.system(size: 34))
                .foregroundStyle(MagpieTheme.textMuted.opacity(0.7))
            Text(String(localized: "还没有脱敏记录"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(MagpieTheme.textPrimary)
            Text(String(localized: "当 Agent 的请求中包含密钥或个人信息时，记录会出现在这里。"))
                .font(.caption)
                .foregroundStyle(MagpieTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .magpieCard()
    }

    // MARK: - 写入设置
    private func setSetting(_ key: String, _ value: Bool) {
        guard let client = app.client else { return }
        MagpieHaptics.light()
        Task {
            if (try? await client.patchSettings(key: key, value: value)) != nil {
                await app.refresh()
                MagpieHaptics.success()
            }
        }
    }
}

// MARK: - 记录详情
private struct MaskingRecordDetailView: View {
    let record: MaskingRecordDTO
    let onSent: (String) async -> String?
    let onAllow: (String) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var allowed: Set<String> = []
    @State private var allowError: String? = nil
    @State private var sentBody: String?
    @State private var showingSent = false
    @State private var isLoadingSent = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    summaryCard

                    Button {
                        loadSent()
                    } label: {
                        HStack(spacing: 8) {
                            if isLoadingSent {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "paperplane.fill")
                            }
                            Text(String(localized: "查看发送给厂商的内容"))
                                .font(.caption.weight(.semibold))
                            Spacer()
                        }
                        .foregroundStyle(MagpieTheme.accent)
                        .padding(12)
                        .frame(maxWidth: .infinity)
                        .background(MagpieTheme.accentSoft.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isLoadingSent)

                    if let values = record.values, !values.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            MagpieSectionLabel(title: String(localized: "替换的值"))
                            VStack(spacing: 0) {
                                ForEach(Array(values.enumerated()), id: \.element.id) { index, value in
                                    valueRow(value)
                                    if index < values.count - 1 {
                                        Divider()
                                            .background(MagpieTheme.borderSubtle)
                                            .padding(.leading, 52)
                                    }
                                }
                            }
                            .magpieCard(padding: 0)
                        }
                    } else {
                        Text(String(localized: "这条记录没有保留具体值。"))
                            .font(.caption)
                            .foregroundStyle(MagpieTheme.textMuted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .magpieCard()
                    }

                    if let error = allowError {
                        Text(error)
                            .font(.caption2)
                            .foregroundStyle(MagpieTheme.red)
                    }
                }
                .padding(16)
            }
            .magpiePageBackground()
            .navigationTitle(String(localized: "脱敏详情"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "完成")) { dismiss() }
                }
            }
            .sheet(isPresented: $showingSent) {
                NavigationStack {
                    ScrollView {
                        Text(sentBody ?? String(localized: "服务器已不再保留这条请求的内容（重启后失效）。"))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(MagpieTheme.textPrimary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                    }
                    .magpiePageBackground()
                    .navigationTitle(String(localized: "发送给厂商的内容"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(String(localized: "完成")) { showingSent = false }
                        }
                    }
                }
                .presentationDetents([.medium, .large])
            }
        }
    }

    private func loadSent() {
        isLoadingSent = true
        Task {
            let body = await onSent(record.key)
            isLoadingSent = false
            sentBody = body
            showingSent = true
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(record.isBlocked ? MagpieTheme.redSoft : MagpieTheme.greenSoft)
                        .frame(width: 40, height: 40)
                    Image(systemName: record.isBlocked ? "hand.raised.fill" : "eye.slash.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(record.isBlocked ? MagpieTheme.red : MagpieTheme.green)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(record.what?.capitalized ?? String(localized: "请求"))
                        .font(.headline)
                        .foregroundStyle(MagpieTheme.textPrimary)
                    Text(MaskingFormat.relative(record.date))
                        .font(.caption2)
                        .foregroundStyle(MagpieTheme.textMuted)
                }

                Spacer()

                if record.isBlocked {
                    MagpieStatusChip(text: String(localized: "已拦截"), color: MagpieTheme.red)
                }
            }

            Divider().background(MagpieTheme.borderSubtle)

            infoRow(String(localized: "Agent"), record.agent)
            infoRow(String(localized: "提供方"), record.provider)
            infoRow(String(localized: "模型"), record.model)
            infoRow(String(localized: "替换次数"), "\(record.n)")
            if let took = record.took, took > 0 {
                infoRow(String(localized: "耗时"), String(format: "%.2f ms", Double(took) / 1000))
            }
        }
        .magpieCard()
    }

    private func infoRow(_ title: String, _ value: String?) -> some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundStyle(MagpieTheme.textMuted)
            Spacer()
            Text(value?.isEmpty == false ? value! : "—")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(MagpieTheme.textPrimary)
                .lineLimit(1)
        }
    }

    private func valueRow(_ value: MaskingValueDTO) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(color(for: value).opacity(0.13))
                    .frame(width: 30, height: 30)
                Image(systemName: icon(for: value))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(color(for: value))
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(MaskingFormat.kindName(value.k))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(MagpieTheme.textPrimary)

                    if value.action == "warn" {
                        MagpieStatusChip(text: String(localized: "明文放行"), color: MagpieTheme.amber)
                    } else if value.action == "block" {
                        MagpieStatusChip(text: String(localized: "拦截"), color: MagpieTheme.red)
                    }
                }

                HStack(spacing: 5) {
                    Text(value.p)
                        .font(.system(size: 10, design: .monospaced))
                    Text("·")
                    Text(MaskingFormat.byName(value.b))
                    Text("·")
                    Text("×\(value.n)")
                }
                .font(.caption2)
                .foregroundStyle(MagpieTheme.textMuted)
                .lineLimit(1)
            }

            Spacer(minLength: 6)

            if value.action != "warn", !allowed.contains(value.p) {
                Button {
                    Task {
                        if await onAllow(value.p) {
                            allowed.insert(value.p)
                            MagpieHaptics.success()
                        } else {
                            allowError = String(localized: "服务器已不再记得这个值的原文（重启后失效）。")
                        }
                    }
                } label: {
                    Text(String(localized: "不再脱敏"))
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(MagpieTheme.pill)
                        .foregroundStyle(MagpieTheme.textSecondary)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            } else if allowed.contains(value.p) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(MagpieTheme.green)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func icon(for value: MaskingValueDTO) -> String {
        if value.action == "block" { return "hand.raised.fill" }
        if value.action == "warn" { return "exclamationmark.triangle.fill" }
        switch value.k.uppercased() {
        case "EMAIL": return "envelope.fill"
        case "PHONE": return "phone.fill"
        case "API_KEY", "TOKEN", "SECRET": return "key.fill"
        case "CARD": return "creditcard.fill"
        case "IP": return "network"
        default: return "eye.slash.fill"
        }
    }

    private func color(for value: MaskingValueDTO) -> Color {
        if value.action == "block" { return MagpieTheme.red }
        if value.action == "warn" { return MagpieTheme.amber }
        return MagpieTheme.green
    }
}
