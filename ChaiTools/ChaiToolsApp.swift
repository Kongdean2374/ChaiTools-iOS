import SwiftUI

@main struct ChaiToolsApp: App {
    var body: some Scene { WindowGroup { RootView() } }
}
struct RootView: View {
    @AppStorage("welcomed") private var welcomed = false
    @AppStorage("appearance") private var appearance = "system"
    @Environment(\.scenePhase) private var scenePhase
    @State private var securityReady = false
    @State private var securityError = ""
    @State private var securityNotice = ""
    @State private var securityEpoch = UUID()
    var body: some View {
        Group {
            if securityReady { tabs.id(securityEpoch) }
            else {
                VStack(spacing: 16) {
                    if securityError.isEmpty { ProgressView("正在準備安全工作區") }
                    else { Text(securityError); Button("重試") { prepareSecurity() } }
                }.padding().appSurface()
            }
        }.safeAreaInset(edge: .top) {
            if !securityNotice.isEmpty {
                HStack { Text(securityNotice).font(.caption); Spacer(); Button("收起") { securityNotice = "" }.frame(minHeight: 44) }.padding(.horizontal).background(CTBarSurface())
            }
        }.task { prepareSecurity() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { prepareSecurity() } }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ChaiToolsCredentialsChanged"))) { _ in
                securityEpoch = UUID(); securityNotice = "金鑰已更新，工作區已重新整理。"; prepareSecurity()
            }
    }
    private func prepareSecurity() {
        do {
            try CredentialStore.prepareGuard()
            // Accessing these boundaries purges contaminated legacy files before restoring any View.
            let store = try SharedStore.live()
            do { _ = try store.preferences() } catch { securityNotice = SensitiveContentGuard.userMessage(error) }
            do { _ = try store.history() } catch { securityNotice = SensitiveContentGuard.userMessage(error) }
            securityReady = true; securityError = ""
        } catch { securityReady = false; securityError = SensitiveContentGuard.userMessage(error) }
    }
    private var tabs: some View {
        TabView {
            NavigationStack { ToolWorkspace() }.tabItem { Label("對話", systemImage: "bubble.left.and.bubble.right") }
            HistoryView().tabItem { Label("工作紀錄", systemImage: "clock") }
            ManageToolsView().tabItem { Label("我的工具", systemImage: "slider.horizontal.3") }
            SettingsView().tabItem { Label("設定", systemImage: "gearshape") }
        }.tint(InterfaceTheme.accent)
            .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
            .task { _ = LegacyCredentialCleanup.runOnce() }
            .sheet(isPresented: Binding(get: { !welcomed }, set: { welcomed = !$0 })) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        BrandMark(size: 72)
                        Text("讓文字，\n更接近你的想法。").font(.largeTitle.bold())
                        Text("翻譯、寫作、整理。從主 App 到鍵盤，用熟悉的原生操作完成。").foregroundStyle(InterfaceTheme.secondaryText)
                        SurfaceCard {
                            Label("貼上或輸入文字", systemImage: "doc.on.clipboard")
                            Label("選擇工具與情境", systemImage: "slider.horizontal.3")
                            Label("確認結果，再複製或插入", systemImage: "checkmark.bubble")
                        }
                        Text("只有你按下執行時，內容才會送至 OpenAI，可能產生 API 費用。紀錄預設關閉；本機計算不需金鑰。").font(.caption).foregroundStyle(InterfaceTheme.secondaryText)
                        Button("開始使用") { welcomed = true }.frame(maxWidth: .infinity).buttonStyle(QuietButtonStyle(prominent: true))
                    }.padding(24)
                }.appSurface()
            }
    }
}
