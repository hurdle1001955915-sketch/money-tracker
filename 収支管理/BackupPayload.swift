import Foundation

// MARK: - BackupPayload

/// バックアップ用統一構造体
struct BackupPayload: Codable {
    static let currentVersion = 3
    
    let version: Int
    let createdAt: Date
    let transactions: [Transaction]
    let expenseCategories: [Category] // 旧バハックアップ互換用（v3でも空配列等で維持、または階層化前データとして保持）
    let incomeCategories: [Category]  // 同上
    let fixedCostTemplates: [FixedCostTemplate]
    let budgets: [Budget]
    
    // v3 新規追加
    let accounts: [Account]?
    let classificationRules: [ClassificationRule]?
    let categoryGroups: [CategoryGroup]?
    let categoryItems: [CategoryItem]?
    
    init(
        transactions: [Transaction],
        expenseCategories: [Category],
        incomeCategories: [Category],
        fixedCostTemplates: [FixedCostTemplate],
        budgets: [Budget],
        accounts: [Account]? = nil,
        classificationRules: [ClassificationRule]? = nil,
        categoryGroups: [CategoryGroup]? = nil,
        categoryItems: [CategoryItem]? = nil
    ) {
        self.version = Self.currentVersion
        self.createdAt = Date()
        self.transactions = transactions
        self.expenseCategories = expenseCategories
        self.incomeCategories = incomeCategories
        self.fixedCostTemplates = fixedCostTemplates
        self.budgets = budgets
        self.accounts = accounts
        self.classificationRules = classificationRules
        self.categoryGroups = categoryGroups
        self.categoryItems = categoryItems
    }
    
    // 後方互換性のためのカスタムデコーダー
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        transactions = try container.decode([Transaction].self, forKey: .transactions)
        expenseCategories = try container.decode([Category].self, forKey: .expenseCategories)
        incomeCategories = try container.decode([Category].self, forKey: .incomeCategories)
        fixedCostTemplates = try container.decode([FixedCostTemplate].self, forKey: .fixedCostTemplates)
        budgets = try container.decode([Budget].self, forKey: .budgets)
        
        // v3 optionals
        accounts = try container.decodeIfPresent([Account].self, forKey: .accounts)
        classificationRules = try container.decodeIfPresent([ClassificationRule].self, forKey: .classificationRules)
        categoryGroups = try container.decodeIfPresent([CategoryGroup].self, forKey: .categoryGroups)
        categoryItems = try container.decodeIfPresent([CategoryItem].self, forKey: .categoryItems)
    }
    
    private enum CodingKeys: String, CodingKey {
        case version, createdAt, transactions, expenseCategories, incomeCategories
        case fixedCostTemplates, budgets, accounts, classificationRules
        case categoryGroups, categoryItems
    }
}

// MARK: - BackupResult

enum BackupResult {
    case success(message: String)
    case failure(error: BackupError)
    
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
    
    var message: String {
        switch self {
        case .success(let msg): return msg
        case .failure(let err): return err.localizedDescription
        }
    }
}

enum BackupError: Error, LocalizedError {
    case encodingFailed(String)
    case decodingFailed(String)
    case fileNotFound
    case fileReadFailed(String)
    case fileWriteFailed(String)
    case noBackupAvailable
    case invalidData
    case unknown(String)
    
    var errorDescription: String? {
        switch self {
        case .encodingFailed(let detail):
            return "エンコード失敗: \(detail)"
        case .decodingFailed(let detail):
            return "デコード失敗: \(detail)"
        case .fileNotFound:
            return "ファイルが見つかりません"
        case .fileReadFailed(let detail):
            return "ファイル読み込み失敗: \(detail)"
        case .fileWriteFailed(let detail):
            return "ファイル書き込み失敗: \(detail)"
        case .noBackupAvailable:
            return "バックアップがありません"
        case .invalidData:
            return "無効なデータ形式です"
        case .unknown(let detail):
            return "不明なエラー: \(detail)"
        }
    }
}

// MARK: - BackupInfo

struct BackupInfo {
    let key: String
    let createdAt: Date
    let transactionCount: Int
    let fileSize: Int
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy/MM/dd HH:mm"
        return formatter.string(from: createdAt)
    }
    
    var formattedSize: String {
        if fileSize < 1024 {
            return "\(fileSize) B"
        } else if fileSize < 1024 * 1024 {
            return String(format: "%.1f KB", Double(fileSize) / 1024.0)
        } else {
            return String(format: "%.1f MB", Double(fileSize) / (1024.0 * 1024.0))
        }
    }
}
