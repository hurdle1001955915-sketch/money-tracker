import Foundation
import Combine

/// SwiftDataマイグレーションのステータス管理
/// UserDefaultsベースで永続化し、一度だけのマイグレーションを保証する
@MainActor
final class MigrationStatus: ObservableObject {
    static let shared = MigrationStatus()

    private let defaults = UserDefaults.standard

    // MARK: - Keys
    private enum Keys {
        static let jsonToSwiftDataMigrationCompleted = "migration_json_to_swiftdata_completed"
        static let jsonToSwiftDataMigrationDate = "migration_json_to_swiftdata_date"
        static let lastMigrationVersion = "migration_last_version"
        static let migratedTransactionCount = "migration_transaction_count"
        static let migratedCategoryCount = "migration_category_count"
        static let migratedAccountCount = "migration_account_count"
    }

    // MARK: - Published Properties
    @Published private(set) var isJsonToSwiftDataMigrationCompleted: Bool = false
    @Published private(set) var migrationDate: Date?
    @Published private(set) var migratedTransactionCount: Int = 0
    @Published private(set) var migratedCategoryCount: Int = 0
    @Published private(set) var migratedAccountCount: Int = 0

    private init() {
        loadStatus()
    }

    // MARK: - Status Management

    private func loadStatus() {
        isJsonToSwiftDataMigrationCompleted = defaults.bool(forKey: Keys.jsonToSwiftDataMigrationCompleted)
        migrationDate = defaults.object(forKey: Keys.jsonToSwiftDataMigrationDate) as? Date
        migratedTransactionCount = defaults.integer(forKey: Keys.migratedTransactionCount)
        migratedCategoryCount = defaults.integer(forKey: Keys.migratedCategoryCount)
        migratedAccountCount = defaults.integer(forKey: Keys.migratedAccountCount)
    }

    /// マイグレーション完了をマーク
    func markJsonToSwiftDataMigrationCompleted(
        transactionCount: Int,
        categoryCount: Int,
        accountCount: Int
    ) {
        let now = Date()
        defaults.set(true, forKey: Keys.jsonToSwiftDataMigrationCompleted)
        defaults.set(now, forKey: Keys.jsonToSwiftDataMigrationDate)
        defaults.set(transactionCount, forKey: Keys.migratedTransactionCount)
        defaults.set(categoryCount, forKey: Keys.migratedCategoryCount)
        defaults.set(accountCount, forKey: Keys.migratedAccountCount)
        defaults.set(AppVersion.current, forKey: Keys.lastMigrationVersion)

        // Update published properties
        isJsonToSwiftDataMigrationCompleted = true
        migrationDate = now
        migratedTransactionCount = transactionCount
        migratedCategoryCount = categoryCount
        migratedAccountCount = accountCount

        Diagnostics.shared.log("Migration completed: transactions=\(transactionCount), categories=\(categoryCount), accounts=\(accountCount)")
    }

    /// マイグレーションが必要かどうか判定
    var needsMigration: Bool {
        !isJsonToSwiftDataMigrationCompleted
    }

    /// デバッグ用: マイグレーションステータスをリセット
    /// 本番では使用しない
    func resetMigrationStatus() {
        defaults.removeObject(forKey: Keys.jsonToSwiftDataMigrationCompleted)
        defaults.removeObject(forKey: Keys.jsonToSwiftDataMigrationDate)
        defaults.removeObject(forKey: Keys.migratedTransactionCount)
        defaults.removeObject(forKey: Keys.migratedCategoryCount)
        defaults.removeObject(forKey: Keys.migratedAccountCount)
        defaults.removeObject(forKey: Keys.lastMigrationVersion)
        loadStatus()
        Diagnostics.shared.log("Migration status reset (DEBUG)")
    }

    /// ステータスの概要を返す
    var statusSummary: String {
        if isJsonToSwiftDataMigrationCompleted {
            let dateStr = migrationDate.map { DateFormatter.localizedString(from: $0, dateStyle: .short, timeStyle: .short) } ?? "不明"
            return "完了済み(\(dateStr)) - Tx:\(migratedTransactionCount), Cat:\(migratedCategoryCount), Acc:\(migratedAccountCount)"
        } else {
            return "未実行"
        }
    }
}

// MARK: - App Version Helper

enum AppVersion {
    static var current: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }

    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
    }
}
