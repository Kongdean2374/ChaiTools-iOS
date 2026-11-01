import SwiftUI

@main struct ChaiToolsApp: App {
    var body: some Scene { WindowGroup { RootView() } }
}
struct RootView: View {
    @AppStorage("welcomed") private var welcomed = false
    @AppStorage("appearance") private var appearance = "system"
    var body: some View {
        TabView {
            ToolListView().tabItem { Label("工具", systemImage: "square.grid.2x2") }
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
