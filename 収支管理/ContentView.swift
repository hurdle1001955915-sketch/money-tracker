import SwiftUI

struct ContentView: View {
    @EnvironmentObject var dataStore: DataStore
    @EnvironmentObject var settings: AppSettings
    @StateObject private var deletionManager = DeletionManager.shared
    
    @State private var selectedTab = 0
    
    var body: some View {
        ZStack {
            mainTabView
            
            // Undo バナー（削除後に表示）
            UndoBannerView(deletionManager: deletionManager) {
                deletionManager.undo(to: dataStore)
            }
        }
        .preferredColorScheme(.light)
        .onChange(of: selectedTab) { _, _ in
            hideKeyboard()
        }
        .onOpenURL { url in
            handleDeepLink(url)
        }
        .environmentObject(deletionManager)
    }
    
    // MARK: - Deep Link Handling

    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "kakeibo",
              url.host == "widget" else { return }

        switch url.path {
        case "/input":
            selectedTab = 0
        case "/calendar":
            selectedTab = 1
        default:
            break
        }
    }

    private var mainTabView: some View {
        TabView(selection: $selectedTab) {
            LazyView(TransactionInputView())
                .tabItem {
                    Label("入力", systemImage: "pencil")
                }
                .tag(0)
                .accessibilityLabel("入力タブ")
                .accessibilityHint("収入や支出を入力します")

            LazyView(CalendarView())
                .tabItem {
                    Label("カレンダー", systemImage: "calendar")
                }
                .tag(1)
                .accessibilityLabel("カレンダータブ")
                .accessibilityHint("月間カレンダーで取引を確認します")

            LazyView(GraphView())
                .tabItem {
                    Label("グラフ", systemImage: "chart.pie")
                }
                .tag(2)
                .accessibilityLabel("グラフタブ")
                .accessibilityHint("収支をグラフで確認します")

            LazyView(AssetDashboardView())
                .tabItem {
                    Label("資産", systemImage: "briefcase")
                }
                .tag(3)
                .accessibilityLabel("資産タブ")
                .accessibilityHint("資産の状況を確認します")

            LazyView(SettingsView())
                .tabItem {
                    Label("設定", systemImage: "gearshape")
                }
                .tag(4)
                .accessibilityLabel("設定タブ")
                .accessibilityHint("アプリの設定を変更します")
        }
        .tint(Color.themeBlue)
    }
}

#Preview {
    ContentView()
        .environmentObject(DataStore.shared)
        .environmentObject(AppSettings.shared)
        .environmentObject(AppLockManager.shared)
}
