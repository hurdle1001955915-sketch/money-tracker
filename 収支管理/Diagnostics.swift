import Foundation
import Combine

/// 診断・ロギングシステム
/// アプリ起動時のデータ状態、マイグレーション、CSVインポートなどをログに記録
@MainActor
final class Diagnostics: ObservableObject {
    static let shared = Diagnostics()

    /// ログエントリ
    struct LogEntry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let category: Category
        let message: String

        enum Category: String {
            case startup = "STARTUP"
            case migration = "MIGRATION"
            case csvImport = "CSV_IMPORT"
            case swiftData = "SWIFT_DATA"
            case json = "JSON"
            case error = "ERROR"
            case info = "INFO"
        }
    }

    @Published private(set) var logs: [LogEntry] = []

    /// 最大ログ保持数
    private let maxLogs = 1000

    private init() {}

    // MARK: - Logging

    func log(_ message: String, category: LogEntry.Category = .info) {
        #if DEBUG
        let entry = LogEntry(timestamp: Date(), category: category, message: message)
        logs.append(entry)

        // 最大数を超えたら古いものを削除
        if logs.count > maxLogs {
            logs.removeFirst(logs.count - maxLogs)
        }

        // コンソールにも出力
        print("[\(category.rawValue)] \(message)")
        #endif
    }

    // MARK: - Startup Diagnostics

    func logStartupDiagnostics() {
        log("=== アプリ起動診断 ===", category: .startup)
        log("Version: \(AppVersion.current) (\(AppVersion.build))", category: .startup)

        // JSON Data Counts
        logJSONDataCounts()

        // Migration Status
        logMigrationStatus()

        // SwiftData Counts (placeholder for future)
        logSwiftDataCounts()

        log("=== 起動診断完了 ===", category: .startup)
    }

    /// JSONファイルのデータ件数をログ
    private func logJSONDataCounts() {
        let dataStore = DataStore.shared

        let transactionCount = dataStore.transactions.count
        let categoryGroupCount = dataStore.categoryGroups.count
        let categoryItemCount = dataStore.categoryItems.count
        let fixedCostCount = dataStore.fixedCostTemplates.count
        let budgetCount = dataStore.budgets.count

        log("JSON Data - Transactions: \(transactionCount)", category: .json)
        log("JSON Data - CategoryGroups: \(categoryGroupCount)", category: .json)
        log("JSON Data - CategoryItems: \(categoryItemCount)", category: .json)
        log("JSON Data - FixedCosts: \(fixedCostCount)", category: .json)
        log("JSON Data - Budgets: \(budgetCount)", category: .json)

        // ファイル存在チェック
        logJSONFileStatus()
    }

    /// JSONファイルの存在状況をログ
    private func logJSONFileStatus() {
        let fm = FileManager.default
        guard let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            log("Application Support directory not found", category: .error)
            return
        }

        let files = [
            "transactions.json",
            "category_groups.json",
            "category_items.json",
            "fixed_costs.json",
            "budgets.json"
        ]

        for file in files {
            let url = appSupport.appendingPathComponent(file)
            if fm.fileExists(atPath: url.path) {
                if let attrs = try? fm.attributesOfItem(atPath: url.path),
                   let size = attrs[.size] as? Int {
                    log("File exists: \(file) (\(formatBytes(size)))", category: .json)
                } else {
                    log("File exists: \(file) (size unknown)", category: .json)
                }
            } else {
                log("File NOT found: \(file)", category: .json)
            }
        }
    }

    /// MigrationStatusをログ
    private func logMigrationStatus() {
        let status = MigrationStatus.shared
        log("Migration Status: \(status.statusSummary)", category: .migration)
        log("Needs Migration: \(status.needsMigration)", category: .migration)
    }

    /// SwiftDataの件数をログ（将来の実装用プレースホルダ）
    private func logSwiftDataCounts() {
        // SwiftData実装後に追加
        log("SwiftData - Not yet implemented", category: .swiftData)
    }

    // MARK: - CSV Import Logging

    func logCSVImportStart(format: String) {
        log("CSV Import started - Format: \(format)", category: .csvImport)
    }

    func logCSVImportResult(added: Int, skipped: Int, duplicateSkipped: Int, invalidSkipped: Int, errors: [String]) {
        log("CSV Import completed:", category: .csvImport)
        log("  - Added: \(added)", category: .csvImport)
        log("  - Skipped: \(skipped) (duplicate: \(duplicateSkipped), invalid: \(invalidSkipped))", category: .csvImport)
        if !errors.isEmpty {
            log("  - Errors: \(errors.prefix(5).joined(separator: ", "))\(errors.count > 5 ? "..." : "")", category: .csvImport)
        }
    }

    // MARK: - Helpers

    private func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 {
            return "\(bytes) B"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024.0)
        } else {
            return String(format: "%.1f MB", Double(bytes) / (1024.0 * 1024.0))
        }
    }

    // MARK: - Export Logs

    /// ログをテキストとしてエクスポート
    func exportLogsAsText() -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"

        var output = "=== Kakeibo Diagnostics Log ===\n"
        output += "Exported: \(df.string(from: Date()))\n"
        output += "Version: \(AppVersion.current) (\(AppVersion.build))\n"
        output += "================================\n\n"

        for entry in logs {
            let timestamp = df.string(from: entry.timestamp)
            output += "[\(timestamp)] [\(entry.category.rawValue)] \(entry.message)\n"
        }

        return output
    }

    /// ログをクリア
    func clearLogs() {
        logs.removeAll()
        log("Logs cleared", category: .info)
    }
}
