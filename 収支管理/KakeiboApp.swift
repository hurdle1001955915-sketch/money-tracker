import SwiftUI
import SwiftData

@main
struct KakeiboApp: App {
    @StateObject private var dataStore = DataStore.shared
    @StateObject private var settings = AppSettings.shared
    @StateObject private var lockManager = AppLockManager.shared
    @StateObject private var deletionManager = DeletionManager.shared
    @StateObject private var diagnostics = Diagnostics.shared
    @StateObject private var migrationStatus = MigrationStatus.shared

    private let jpLocale = Locale(identifier: "ja_JP")
    private var jpCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = jpLocale
        cal.timeZone = .current
        return cal
    }
    
    // DB初期化ステータス
    static var isFallbackMode = false
    @State private var showDatabaseErrorAlert = false

    // SwiftData ModelContainer
    private var modelContainer: ModelContainer = {
        do {
            return try DatabaseConfig.createContainer()
        } catch {
            // Fallback to in-memory container to avoid app hang/black screen
            print("⚠️ Failed to create persistent ModelContainer. Falling back to in-memory: \(error)")
            // ログ記録（ただしDiagnostics初期化前なのでprintのみ、後でフラグを見てログする）
            KakeiboApp.isFallbackMode = true
            
            let config = ModelConfiguration(
                "KakeiboDatabase_Fallback",
                schema: DatabaseConfig.schema,
                isStoredInMemoryOnly: true,
                allowsSave: true
            )
            if let container = try? ModelContainer(for: DatabaseConfig.schema, configurations: [config]) {
                return container
            }
            // As a last resort, crash with context to surface the real error
            fatalError("Unable to create any ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(dataStore)
                .environmentObject(settings)
                .environmentObject(lockManager)
                .environmentObject(deletionManager)
                .environment(\.locale, jpLocale)
                .environment(\.calendar, jpCalendar)
                .environment(\.timeZone, .current)
                .preferredColorScheme(.light)
                .withLockScreen()
                .modelContainer(modelContainer)
                .onAppear {
                    // Startup diagnostics logging
                    Diagnostics.shared.logStartupDiagnostics()
                    
                    // Check fallback mode
                    if KakeiboApp.isFallbackMode {
                        Diagnostics.shared.log("Running in DB Fallback Mode (In-Memory)", category: .error)
                        showDatabaseErrorAlert = true
                    }

                    // Get ModelContext
                    let context = modelContainer.mainContext

                    // Perform JSON→SwiftData migration on first launch
                    DataMigration.migrateIfNeeded(context: context)

                    // Inject ModelContext into DataStore and AccountStore
                    DataStore.shared.setModelContext(context)
                    AccountStore.shared.setModelContext(context)
                    
                    // 固定費の自動生成チェック（Context設定後に実行）
                    // 過去の未処理分も含めて現在まで処理する
                    DataStore.shared.processAllFixedCostsUntilNow()
                    
                    // 初期分類ルールの注入（ルールが空の場合のみ）
                    ClassificationRulesStore.shared.ensureDefaultRules(with: DataStore.shared)
                }
                .alert("データベースエラー", isPresented: $showDatabaseErrorAlert) {
                    Button("OK", role: .cancel) { }
                } message: {
                    Text("データの読み込みに失敗しました。一時的なモードで起動しています。変更内容は保存されない可能性があります。")
                }
        }
    }
}
