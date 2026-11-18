import SwiftUI
import UIKit

/// 路由组详情页：成员、策略与故障转移顺序，支持编辑 / 开关 / 手动指定 / 分享 / 删除。
struct GroupDetailView: View {
    let groupRef: String
    var viewModel: GroupsViewModel? = nil
    @Environment(AppModel.self) private var app
    @Environment(GroupsViewModel.self) private var envViewModel: GroupsViewModel?
    @Environment(\.dismiss) private var dismiss
    @State private var fallbackViewModel = GroupsViewModel()

    private var activeVM: GroupsViewModel {
        viewModel ?? envViewModel ?? fallbackViewModel
    }

    @State private var showingEdit = false
    @State private var showingShare = false
    @State private var showingDelete = false

    private var group: GroupDTO? {
        activeVM.group(ref: groupRef)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let group {
                    headerCard(group)
                    strategyCard(group)
                    if group.routing == "manual" {
                        pickCard(group)
                    }
                    membersSection(group)
                    if let holds = group.holds, !holds.isEmpty {
                        holdsSection(holds)
                    }
                    footerActions(group)
                } else {
                    ProgressView(String(localized: "读取路由组…"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .magpiePageBackground()
        .navigationTitle(group?.name ?? String(localized: "组详情"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showingEdit = true
                    } label: {
                        Label(
                            (group?.isAuto == true) ? String(localized: "复制为自定义组…") : String(localized: "编辑组…"),
                            systemImage: "pencil"
                        )
                    }
                    Button {
                        showingShare = true
                    } label: {
                        Label(String(localized: "分享组…"), systemImage: "square.and.arrow.up")
                    }
                    Button(role: .destructive) {
                        showingDelete = true
                    } label: {
                        Label(String(localized: "删除组"), systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingEdit) {
            if let group {
                GroupEditView(editing: group)
                    .environment(activeVM)
            }
        }
        .sheet(isPresented: $showingShare) {
            if let group {
                GroupShareSheetInline(group: group)
                    .environment(activeVM)
            }
        }
        .alert(String(localized: "删除这个路由组？"), isPresented: $showingDelete) {
            Button(String(localized: "删除"), role: .destructive) {
                guard let client = app.client, let group else { return }
                Task {
                    if await activeVM.delete(client: client, id: group.id) {
                        dismiss()
                    }
                }
            }
            Button(String(localized: "取消"), role: .cancel) {}
        } message: {
            Text(String(localized: "使用 group/\(group?.id ?? "") 的 Agent 将失去这个组。"))
        }
    }

    // MARK: - 头部
    private func headerCard(_ group: GroupDTO) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(group.isAuto ? MagpieTheme.accentSoft : MagpieTheme.pill)
                        .frame(width: 44, height: 44)
                    Image(systemName: group.isAuto ? "wand.and.stars" : "square.stack.3d.up")
                        .font(.title3)
                        .foregroundStyle(group.isAuto ? MagpieTheme.accent : MagpieTheme.textSecondary)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(group.name)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(MagpieTheme.textPrimary)

                        if group.isAuto {
                            MagpieStatusChip(text: "AUTO", color: MagpieTheme.accent)
                        }
                        if group.unlisted == true {
                            MagpieStatusChip(text: String(localized: "仅路由组"), color: MagpieTheme.cyan)
                        }
                        if group.disabled == true {
                            MagpieStatusChip(text: String(localized: "已停用"), color: MagpieTheme.amber)
                        }
                        if group.ready == true {
                            MagpieStatusChip(text: String(localized: "就绪"), color: MagpieTheme.green)
                        }
                    }

                    Text(group.ref)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(MagpieTheme.textMuted)
                }

                Spacer()
            }

            Divider().background(MagpieTheme.borderSubtle)

            HStack(spacing: 10) {
                detailMetric(String(localized: "成员"), "\(group.memberCount)")
                Spacer()
                detailMetric(String(localized: "推理档"), group.offers?.joined(separator: " · ") ?? "—")
                Spacer()
                detailMetric(String(localized: "类型"), group.isAuto ? String(localized: "自动发现") : String(localized: "自定义"))
            }
        }
        .magpieCard()
    }

    private func detailMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(MagpieTheme.textMuted)
            Text(value)
                .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(MagpieTheme.textPrimary)
                .lineLimit(1)
        }
    }

    // MARK: - 策略
    private func strategyCard(_ group: GroupDTO) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(String(localized: "当前分发策略"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MagpieTheme.textMuted)
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: GroupRouting.icon(group.routing))
                    Text(group.routingDisplayName)
                }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(MagpieTheme.accent)
            }

            Divider().background(MagpieTheme.borderSubtle)

            Text(GroupRouting.description(group.routing))
                .font(.caption)
                .foregroundStyle(MagpieTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let affinity = group.affinity, !affinity.isEmpty {
                HStack(spacing: 5) {
                    Image(systemName: "person.wave.2")
                        .font(.system(size: 9))
                    Text(String(localized: "对话保持：\(affinityLabel(affinity))"))
                        .font(.caption2)
                }
                .foregroundStyle(MagpieTheme.textMuted)
            }
        }
        .magpieCard()
    }

    private func affinityLabel(_ value: String) -> String {
        switch value {
        case "session": return String(localized: "整个会话")
        case "turn": return String(localized: "仅当前轮")
        case "off": return String(localized: "不保持")
        case "strict": return String(localized: "严格保持")
        default: return value
        }
    }

    // MARK: - 手动指定（Manual 组）
    private func pickCard(_ group: GroupDTO) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            MagpieSectionLabel(
                title: String(localized: "手动指定成员"),
                detail: String(localized: "Manual 组始终只走这里选中的成员")
            )

            VStack(spacing: 0) {
                ForEach(group.members ?? [], id: \.self) { member in
                    Button {
                        guard let client = app.client else { return }
                        Task { _ = await activeVM.pick(client: client, id: group.id, member: member) }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: group.picked == member ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(group.picked == member ? MagpieTheme.accent : MagpieTheme.textMuted)
                            Text(member)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(MagpieTheme.textPrimary)
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if member != (group.members ?? []).last {
                        Divider().background(MagpieTheme.borderSubtle).padding(.leading, 40)
                    }
                }
            }
            .magpieCard(padding: 0)
        }
    }

    // MARK: - 成员
    private func membersSection(_ group: GroupDTO) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            MagpieSectionLabel(
                title: String(localized: "成员与故障转移顺序"),
                detail: "\(group.memberCount)"
            )

            let info = group.memberInfo ?? []
            if info.isEmpty {
                Text(String(localized: "这个组还没有可用的成员。"))
                    .font(.caption)
                    .foregroundStyle(MagpieTheme.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .magpieCard()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(info.enumerated()), id: \.element.id) { index, member in
                        memberRow(
                            member,
                            index: index,
                            isPicked: group.picked == member.id,
                            isOff: group.off?.contains(member.id) == true
                        )
                        if index < info.count - 1 {
                            Divider().background(MagpieTheme.borderSubtle).padding(.leading, 58)
                        }
                    }
                }
                .magpieCard(padding: 0)
            }
        }
    }

    private func memberRow(_ member: GroupMemberDTO, index: Int, isPicked: Bool, isOff: Bool) -> some View {
        HStack(spacing: 11) {
            Text("\(index + 1)")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(member.isReady ? (index == 0 ? MagpieTheme.accent : MagpieTheme.textMuted) : MagpieTheme.textMuted.opacity(0.6))
                .frame(width: 20, height: 20)
                .background(member.isReady ? (index == 0 ? MagpieTheme.accentSoft : MagpieTheme.pill) : MagpieTheme.pill.opacity(0.5))
                .clipShape(Circle())

            MagpieIconView(
                icon: member.icon ?? member.provider,
                name: member.name ?? member.id,
                size: 26,
                cornerRadius: 6
            )
            .opacity(member.isReady ? 1 : 0.5)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(member.displayName)
                        .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(member.isReady ? MagpieTheme.textPrimary : MagpieTheme.textMuted)
                        .lineLimit(1)

                    if member.group == true {
                        MagpieStatusChip(text: String(localized: "嵌套组"), color: MagpieTheme.purple)
                    }
                    if isOff {
                        MagpieStatusChip(text: String(localized: "已停用"), color: MagpieTheme.amber)
                    }
                    if member.providerOff == true {
                        MagpieStatusChip(text: String(localized: "提供方已停用"), color: MagpieTheme.amber)
                    }
                    if member.free == true {
                        MagpieStatusChip(text: "FREE", color: MagpieTheme.green)
                    }
                    if isPicked {
                        MagpieStatusChip(text: String(localized: "已指定"), color: MagpieTheme.accent, icon: "checkmark")
                    }
                }

                HStack(spacing: 6) {
                    Text(member.id)
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(MagpieTheme.textMuted)
                        .lineLimit(1)
                    if let context = member.context, context > 0 {
                        Text(UsageDTO.formatTokens(context))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(MagpieTheme.textMuted.opacity(0.85))
                    }
                }
            }

            Spacer(minLength: 4)

            if !member.isReady {
                Text(String(localized: "未就绪"))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(MagpieTheme.amber)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .opacity(member.isReady ? 1 : 0.75)
    }

    // MARK: - 嵌套组
    private func holdsSection(_ holds: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            MagpieSectionLabel(
                title: String(localized: "包含的路由组"),
                detail: "\(holds.count)"
            )

            VStack(spacing: 0) {
                ForEach(Array(holds.enumerated()), id: \.element) { index, ref in
                    HStack(spacing: 10) {
                        Image(systemName: "square.3.layers.3d")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(MagpieTheme.purple)
                            .frame(width: 26, height: 26)
                            .background(MagpieTheme.purple.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        Text(ref)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(MagpieTheme.textPrimary)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)

                    if index < holds.count - 1 {
                        Divider().background(MagpieTheme.borderSubtle).padding(.leading, 50)
                    }
                }
            }
            .magpieCard(padding: 0)
        }
    }

    // MARK: - 底部操作
    private func footerActions(_ group: GroupDTO) -> some View {
        VStack(spacing: 10) {
            Toggle(isOn: Binding(
                get: { !(group.disabled ?? false) },
                set: { on in
                    guard let client = app.client else { return }
                    Task { _ = await activeVM.switchGroup(client: client, id: group.id, on: on) }
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "启用此组"))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(MagpieTheme.textPrimary)
                    Text(String(localized: "停用后成员与配置保留，但不再对外提供"))
                        .font(.caption2)
                        .foregroundStyle(MagpieTheme.textMuted)
                }
            }
            .tint(MagpieTheme.green)
            .padding(14)
            .magpieCard(padding: 0)

            Button {
                showingEdit = true
            } label: {
                Label(
                    group.isAuto ? String(localized: "复制为自定义组") : String(localized: "编辑这个组"),
                    systemImage: "slider.horizontal.3"
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
            }
            .buttonStyle(MagpiePrimaryButtonStyle(tint: MagpieTheme.accent))

            Button(role: .destructive) {
                showingDelete = true
            } label: {
                HStack {
                    Spacer()
                    Image(systemName: "trash")
                    Text(String(localized: "删除这个组"))
                    Spacer()
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(MagpieTheme.red)
                .padding(.vertical, 13)
                .background(MagpieTheme.redSoft)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - 复用分享面板（详情页内部）
private struct GroupShareSheetInline: View {
    let group: GroupDTO
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var app
    @Environment(GroupsViewModel.self) private var viewModel
    @State private var text: String?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(MagpieTheme.red)
                    }

                    if let text {
                        Text(text)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(MagpieTheme.textPrimary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(MagpieTheme.cardSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                        Button {
                            UIPasteboard.general.string = text
                            MagpieHaptics.success()
                        } label: {
                            Label(String(localized: "复制到剪贴板"), systemImage: "doc.on.doc.fill")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(MagpiePrimaryButtonStyle(tint: MagpieTheme.accent))
                    } else {
                        ProgressView(String(localized: "生成分享文本…"))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                    }
                }
                .padding(16)
            }
            .magpiePageBackground()
            .navigationTitle(String(localized: "分享路由组"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "完成")) { dismiss() }
                }
            }
            .task {
                guard text == nil, let client = app.client else { return }
                if let shared = await viewModel.share(client: client, id: group.id) {
                    text = shared
                } else {
                    errorMessage = viewModel.errorMessage ?? String(localized: "生成分享文本失败")
                }
            }
        }
    }
}
