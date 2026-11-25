import Foundation

/// magpie `unservedJSON`：某 Agent 模型字段当前未提供的路由组及其原因。
struct UnservedGroupDTO: Codable, Sendable, Identifiable, Hashable {
    var value: String
    var label: String
    var icons: [String]?
    var ref: String
    var why: String
    /// 网关本身提供该路由组，仅被该 Agent 的模型列表隐藏；选中时可自动加回并切换。
    var pick: Bool?

    var id: String { ref.isEmpty ? value : ref }
    var isPickable: Bool { pick == true }
}

/// magpie `fieldJSON`：Agent 的一个可配置字段（model / effort / opus / sonnet …）。
struct FieldDTO: Codable, Sendable, Identifiable, Hashable {
    var key: String
    var label: String
    var value: String
    /// 字段自带的选项；为 nil 时用 `list` 指向 `state.optionLists`。
    var options: [ModelOption]?
    /// 1 起索引，指向 `state.optionLists[list-1]`；0 表示用自带 `options`。
    var list: Int?
    /// 用户创建但该字段当前未提供的路由组及原因。
    var unserved: [UnservedGroupDTO]?

    var id: String { key }
}