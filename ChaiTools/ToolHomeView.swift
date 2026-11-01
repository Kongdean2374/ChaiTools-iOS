import SwiftUI

struct ToolListView: View {
    @State private var preferences = Preferences()
    @State private var recent: [WorkTask] = []
    @State private var error = ""
    @State private var query = ""
    @State private var hasKey = false
    @State private var showSettings = false
    private var visible: [Tool] {
        preferences.tools.filter { $0.enabled && (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.subtitle.localizedCaseInsensitiveContains(query)) }
    }
    private let groups: [(String, [String])] = [("語言與寫作", ["translate", "rewrite", "generate", "language"]), ("查詢與整理", ["search", "calculate", "summary"])]
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    if !error.isEmpty { NoticeCard(notice: OperationNotice(title: "讀取資料未完成", message: error, kind: .failure)) }
                    if query.isEmpty {
                        let favorites = visible.filter(\.favorite)
                        if !favorites.isEmpty { toolGroup("常用收藏", tools: favorites) }
                        ForEach(groups, id: \.0) { group in toolGroup(group.0, tools: visible.filter { group.1.contains($0.id) }) }
                        toolGroup("我的工具", tools: visible.filter { !groups.flatMap(\.1).contains($0.id) })
                    } else { toolGroup("搜尋結果", tools: visible) }
                    if visible.isEmpty { ContentUnavailableView("沒有符合的工具", systemImage: "magnifyingglass", description: Text("試試其他關鍵字，或在『我的工具』啟用工具。")) }
                    if query.isEmpty && !recent.isEmpty { recentWork }
                    NavigationLink { KeyboardGuideView() } label: {
                        Label("在其他 App 使用 · 鍵盤指南", systemImage: "keyboard").frame(maxWidth: .infinity)
                    }.buttonStyle(QuietButtonStyle())
                }.padding(16)
            }.appSurface().navigationTitle("ChaiTools").navigationBarTitleDisplayMode(.inline)
                .searchable(text: $query.guarded(onBlocked: { error = SensitiveContentGuard.message }), prompt: "搜尋工具")
                .sheet(isPresented: $showSettings, onDismiss: { Task { await load() } }) { SettingsView() }
                .task { await load() }
        }
    }
    private var header: some View {
        SurfaceCard {
            HStack(spacing: 12) {
                BrandMark(size: 42)
                VStack(alignment: .leading, spacing: 4) {
                    Text("你的文字工作台").font(.title3.bold())
                    Text(preferences.model).font(.caption).foregroundStyle(InterfaceTheme.secondaryText).lineLimit(1)
                }
                Spacer(minLength: 0)
                Button { showSettings = true } label: {
                    Image(systemName: hasKey ? "checkmark.shield" : "key").frame(width: 44, height: 44)
                }.accessibilityLabel(hasKey ? "已儲存金鑰，開啟連線設定" : "尚未設定金鑰，開啟連線設定")
            }
            HStack {
                Text(hasKey ? "已儲存金鑰 · 可在設定測試連線" : "先設定金鑰，或直接使用本機計算")
                Spacer(minLength: 0)
                Image(systemName: preferences.history ? "clock" : "hand.raised")
            }.font(.caption).foregroundStyle(InterfaceTheme.secondaryText)
        }
    }
    private var recentWork: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("繼續上次的工作").font(.headline)
            ForEach(recent.prefix(2)) { task in
                NavigationLink { ToolWorkspace(tool: task.tool, task: task) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: task.tool.icon).foregroundStyle(InterfaceTheme.accent)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(task.tool.name).font(.subheadline.weight(.medium))
                            Text(task.answer?.text ?? task.source).lineLimit(1).font(.caption).foregroundStyle(InterfaceTheme.secondaryText)
                        }
                        Spacer(minLength: 0); Image(systemName: "chevron.right").font(.caption)
                    }.padding(14).frame(minHeight: 60).background(InterfaceTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                }.buttonStyle(.plain)
            }
        }
    }
    @ViewBuilder private func toolGroup(_ title: String, tools: [Tool]) -> some View {
        if !tools.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                CTSectionHeader(title: title)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                    ForEach(tools) { tool in
                        NavigationLink { ToolWorkspace(tool: tool) } label: {
                            CTToolTile(tool: tool)
                        }.buttonStyle(CTPressStyle())
                    }
                }
            }
        }
    }
    private func load() async {
        let loaded = await Task.detached(priority: .utility) { () -> (Preferences?, [WorkTask], Bool, String) in
            do {
                let store = try SharedStore.live(); let p = try store.preferences()
                return (p, p.history ? Array(try store.history().prefix(2)) : [], try CredentialStore.hasKey(), "")
            } catch { return (nil, [], false, SensitiveContentGuard.userMessage(error)) }
        }.value
        guard !Task.isCancelled else { return }
        if let p = loaded.0 { preferences = p }; recent = loaded.1; hasKey = loaded.2; error = loaded.3
    }
}
