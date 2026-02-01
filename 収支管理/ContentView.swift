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
        .environmentObject(deletionManager)
    }
    
    private var mainTabView: some View {
        TabView(selection: $selectedTab) {
            LazyView(TransactionInputView())
                .tabItem {
                    Label("入力", systemImage: "pencil")
                }
                .tag(0)
            
            LazyView(CalendarView())
                .tabItem {
                    Label("カレンダー", systemImage: "calendar")
                }
                .tag(1)
            
            LazyView(GraphView())
                .tabItem {
                    Label("グラフ", systemImage: "chart.pie")
                }
                .tag(2)
            
            LazyView(AssetDashboardView())
                .tabItem {
                    Label("資産", systemImage: "briefcase")
                }
                .tag(3)
            
            LazyView(SettingsView())
                .tabItem {
                    Label("設定", systemImage: "gearshape")
                }
                .tag(4)
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
