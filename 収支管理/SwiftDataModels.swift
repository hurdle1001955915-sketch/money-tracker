// MARK: - SwiftData Models
// These models mirror the existing struct-based models but are designed for SwiftData persistence
// Migration from UserDefaults to SwiftData will happen in phases

import Foundation
import SwiftData
import SwiftUI

// MARK: - Persistent Transaction Model

@Model
final class TransactionModel {
    @Attribute(.unique) var id: UUID
    var date: Date
    var typeRaw: String // expense, income, transfer
    var amount: Int
    
    // カテゴリID化
    var categoryId: UUID?
    var originalCategoryName: String?
    
    var memo: String
    var isRecurring: Bool
    var templateId: UUID?
    var createdAt: Date
    
    // CSVインポート元の識別用
    var source: String?
    var sourceId: String?
    
    // Phase1: インポート追跡用
    var importId: String?      // このインポートで作られた取引に付与
    var sourceHash: String?    // 重複判定用（date+amount+memo等のハッシュ）

    // Phase3-1: 振替ペアリング用
    var transferId: String?    // 同じtransferIdを持つ2件の取引がペアとなる

    // 分類情報フィールド（CSV拡張用）
    var classificationSourceRaw: String?   // ClassificationSource.rawValue
    var classificationRuleId: UUID?
    var classificationConfidence: Double?
    var classificationReason: String?
    var suggestedCategoryId: UUID?

    var classificationSource: ClassificationSource? {
        get {
            guard let raw = classificationSourceRaw else { return nil }
            return ClassificationSource(rawValue: raw)
        }
        set {
            classificationSourceRaw = newValue?.rawValue
        }
    }

    // フェーズ4: 振替・分割・口座関連
    var accountId: UUID?
    var toAccountId: UUID?
    var parentId: UUID?
    var isSplit: Bool
    var isDeleted: Bool
    
    var type: TransactionType {
        get { TransactionType(rawValue: typeRaw) ?? .expense }
        set { typeRaw = newValue.rawValue }
    }
    
    init(
        id: UUID = UUID(),
        date: Date = Date(),
        type: TransactionType = .expense,
        amount: Int = 0,
        categoryId: UUID? = nil,
        originalCategoryName: String? = nil,
        memo: String = "",
        isRecurring: Bool = false,
        templateId: UUID? = nil,
        createdAt: Date = Date(),
        source: String? = nil,
        sourceId: String? = nil,
        accountId: UUID? = nil,
        toAccountId: UUID? = nil,
        parentId: UUID? = nil,
        isSplit: Bool = false,
        isDeleted: Bool = false,
        importId: String? = nil,
        sourceHash: String? = nil,
        transferId: String? = nil,
        classificationSource: ClassificationSource? = nil,
        classificationRuleId: UUID? = nil,
        classificationConfidence: Double? = nil,
        classificationReason: String? = nil,
        suggestedCategoryId: UUID? = nil
    ) {
        self.id = id
        self.date = date
        self.typeRaw = type.rawValue
        self.amount = amount
        self.categoryId = categoryId
        self.originalCategoryName = originalCategoryName
        self.memo = memo
        self.isRecurring = isRecurring
        self.templateId = templateId
        self.createdAt = createdAt
        self.source = source
        self.sourceId = sourceId
        self.accountId = accountId
        self.toAccountId = toAccountId
        self.parentId = parentId
        self.isSplit = isSplit
        self.isDeleted = isDeleted
        self.importId = importId
        self.sourceHash = sourceHash
        self.transferId = transferId
        self.classificationSourceRaw = classificationSource?.rawValue
        self.classificationRuleId = classificationRuleId
        self.classificationConfidence = classificationConfidence
        self.classificationReason = classificationReason
        self.suggestedCategoryId = suggestedCategoryId
    }

    /// Convert from struct-based Transaction (for migration)
    convenience init(from tx: Transaction) {
        self.init(
            id: tx.id,
            date: tx.date,
            type: tx.type,
            amount: tx.amount,
            categoryId: tx.categoryId,
            originalCategoryName: tx.originalCategoryName,
            memo: tx.memo,
            isRecurring: tx.isRecurring,
            templateId: tx.templateId,
            createdAt: tx.createdAt,
            source: tx.source,
            sourceId: tx.sourceId,
            accountId: tx.accountId,
            toAccountId: tx.toAccountId,
            parentId: tx.parentId,
            isSplit: tx.isSplit,
            isDeleted: tx.isDeleted,
            importId: tx.importId,
            sourceHash: tx.sourceHash,
            transferId: tx.transferId,
            classificationSource: tx.classificationSource,
            classificationRuleId: tx.classificationRuleId,
            classificationConfidence: tx.classificationConfidence,
            classificationReason: tx.classificationReason,
            suggestedCategoryId: tx.suggestedCategoryId
        )
    }

    /// Convert back to struct-based Transaction (for compatibility)
    func toTransaction() -> Transaction {
        Transaction(
            id: id,
            date: date,
            type: type,
            amount: amount,
            categoryId: categoryId,
            originalCategoryName: originalCategoryName,
            memo: memo,
            isRecurring: isRecurring,
            templateId: templateId,
            createdAt: createdAt,
            source: source,
            sourceId: sourceId,
            accountId: accountId,
            toAccountId: toAccountId,
            parentId: parentId,
            isSplit: isSplit,
            isDeleted: isDeleted,
            importId: importId,
            sourceHash: sourceHash,
            transferId: transferId,
            classificationSource: classificationSource,
            classificationRuleId: classificationRuleId,
            classificationConfidence: classificationConfidence,
            classificationReason: classificationReason,
            suggestedCategoryId: suggestedCategoryId
        )
    }
}

// MARK: - Persistent Category Model

@Model
final class CategoryModel {
    @Attribute(.unique) var id: UUID
    var name: String
    var colorHex: String
    var typeRaw: String
    var order: Int
    
    var type: TransactionType {
        get { TransactionType(rawValue: typeRaw) ?? .expense }
        set { typeRaw = newValue.rawValue }
    }
    
    var color: Color {
        Color(hex: colorHex)
    }
    
    init(
        id: UUID = UUID(),
        name: String,
        colorHex: String = "#607D8B",
        type: TransactionType,
        order: Int = 0
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.typeRaw = type.rawValue
        self.order = order
    }
    
    convenience init(from category: Category) {
        self.init(
            id: category.id,
            name: category.name,
            colorHex: category.colorHex,
            type: category.type,
            order: category.order
        )
    }
    
    func toCategory() -> Category {
        Category(
            id: id,
            name: name,
            colorHex: colorHex,
            type: type,
            order: order
        )
    }
}

// MARK: - Persistent Account Model

@Model
final class AccountModel {
    @Attribute(.unique) var id: UUID
    var name: String
    var typeRaw: String
    var initialBalance: Int
    var colorHex: String
    var order: Int
    var isActive: Bool
    var createdAt: Date
    
    var accountType: AccountType {
        get { AccountType(rawValue: typeRaw) ?? .other }
        set { typeRaw = newValue.rawValue }
    }
    
    init(
        id: UUID = UUID(),
        name: String,
        type: AccountType,
        initialBalance: Int = 0,
        colorHex: String = "#607D8B",
        order: Int = 0,
        isActive: Bool = true,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.typeRaw = type.rawValue
        self.initialBalance = initialBalance
        self.colorHex = colorHex
        self.order = order
        self.isActive = isActive
        self.createdAt = createdAt
    }
    
    convenience init(from account: Account) {
        self.init(
            id: account.id,
            name: account.name,
            type: account.type,
            initialBalance: account.initialBalance,
            colorHex: account.colorHex,
            order: account.order,
            isActive: account.isActive,
            createdAt: account.createdAt
        )
    }
    
    func toAccount() -> Account {
        Account(
            id: id,
            name: name,
            type: accountType,
            initialBalance: initialBalance,
            colorHex: colorHex,
            order: order,
            isActive: isActive,
            createdAt: createdAt
        )
    }
}

// MARK: - Persistent CategoryGroup Model

@Model
final class CategoryGroupModel {
    @Attribute(.unique) var id: UUID
    var name: String
    var typeRaw: String
    var order: Int
    var colorHex: String?

    var type: TransactionType {
        get { TransactionType(rawValue: typeRaw) ?? .expense }
        set { typeRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        name: String,
        type: TransactionType,
        order: Int = 0,
        colorHex: String? = nil
    ) {
        self.id = id
        self.name = name
        self.typeRaw = type.rawValue
        self.order = order
        self.colorHex = colorHex
    }

    convenience init(from group: CategoryGroup) {
        self.init(
            id: group.id,
            name: group.name,
            type: group.type,
            order: group.order,
            colorHex: group.colorHex
        )
    }

    func toCategoryGroup() -> CategoryGroup {
        CategoryGroup(
            id: id,
            name: name,
            type: type,
            order: order,
            colorHex: colorHex
        )
    }
}

// MARK: - Persistent CategoryItem Model

@Model
final class CategoryItemModel {
    @Attribute(.unique) var id: UUID
    var name: String
    var groupId: UUID
    var typeRaw: String
    var order: Int
    var colorHex: String

    var type: TransactionType {
        get { TransactionType(rawValue: typeRaw) ?? .expense }
        set { typeRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        name: String,
        groupId: UUID,
        type: TransactionType,
        order: Int = 0,
        colorHex: String = "#607D8B"
    ) {
        self.id = id
        self.name = name
        self.groupId = groupId
        self.typeRaw = type.rawValue
        self.order = order
        self.colorHex = colorHex
    }

    convenience init(from item: CategoryItem) {
        self.init(
            id: item.id,
            name: item.name,
            groupId: item.groupId,
            type: item.type,
            order: item.order,
            colorHex: item.colorHex
        )
    }

    func toCategoryItem() -> CategoryItem {
        CategoryItem(
            id: id,
            name: name,
            groupId: groupId,
            type: type,
            order: order,
            colorHex: colorHex
        )
    }
}

// MARK: - Persistent Budget Model

@Model
final class BudgetModel {
    @Attribute(.unique) var id: UUID
    var categoryId: UUID?
    var originalCategoryName: String?
    var amount: Int
    var month: Int
    var year: Int
    
    init(
        id: UUID = UUID(),
        categoryId: UUID? = nil,
        originalCategoryName: String? = nil,
        amount: Int,
        month: Int = 0,
        year: Int = 0
    ) {
        self.id = id
        self.categoryId = categoryId
        self.originalCategoryName = originalCategoryName
        self.amount = amount
        self.month = month
        self.year = year
    }
    
    convenience init(from budget: Budget) {
        self.init(
            id: budget.id,
            categoryId: budget.categoryId,
            originalCategoryName: budget.originalCategoryName,
            amount: budget.amount,
            month: budget.month,
            year: budget.year
        )
    }
    
    func toBudget() -> Budget {
        Budget(
            id: id,
            categoryId: categoryId,
            originalCategoryName: originalCategoryName,
            amount: amount,
            month: month,
            year: year
        )
    }
}

// MARK: - Persistent FixedCostTemplate Model

@Model
final class FixedCostTemplateModel {
    @Attribute(.unique) var id: UUID
    var name: String
    var typeRaw: String
    var amount: Int
    
    var categoryId: UUID?
    var originalCategoryName: String?
    
    var dayOfMonth: Int
    var memo: String
    var isEnabled: Bool
    var lastProcessedMonth: String
    var createdAt: Date
    
    var type: TransactionType {
        get { TransactionType(rawValue: typeRaw) ?? .expense }
        set { typeRaw = newValue.rawValue }
    }
    
    var dayOfMonthDisplay: String {
        dayOfMonth == 0 ? "末日" : "\(dayOfMonth)日"
    }
    
    init(
        id: UUID = UUID(),
        name: String,
        type: TransactionType,
        amount: Int,
        categoryId: UUID? = nil,
        originalCategoryName: String? = nil,
        dayOfMonth: Int,
        memo: String = "",
        isEnabled: Bool = true,
        lastProcessedMonth: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.typeRaw = type.rawValue
        self.amount = amount
        self.categoryId = categoryId
        self.originalCategoryName = originalCategoryName
        self.dayOfMonth = dayOfMonth
        self.memo = memo
        self.isEnabled = isEnabled
        self.lastProcessedMonth = lastProcessedMonth
        self.createdAt = createdAt
    }
    
    convenience init(from template: FixedCostTemplate) {
        self.init(
            id: template.id,
            name: template.name,
            type: template.type,
            amount: template.amount,
            categoryId: template.categoryId,
            originalCategoryName: template.originalCategoryName,
            dayOfMonth: template.dayOfMonth,
            memo: template.memo,
            isEnabled: template.isEnabled,
            lastProcessedMonth: template.lastProcessedMonth,
            createdAt: template.createdAt
        )
    }
    
    func toFixedCostTemplate() -> FixedCostTemplate {
        FixedCostTemplate(
            id: id,
            name: name,
            type: type,
            amount: amount,
            categoryId: categoryId,
            originalCategoryName: originalCategoryName,
            dayOfMonth: dayOfMonth,
            memo: memo,
            isEnabled: isEnabled,
            lastProcessedMonth: lastProcessedMonth,
            createdAt: createdAt
        )
    }
}

// MARK: - Import History Model

@Model
final class ImportHistoryModel {
    @Attribute(.unique) var id: UUID
    var importId: String?          // Phase1: インポート単位の一意ID（取引と紐付け用）
    var importDate: Date?
    var filename: String?
    var fileHash: String?
    var totalRowCount: Int
    var addedCount: Int
    var duplicateCount: Int
    var skippedCount: Int
    var source: String?  // PayPay, Resona, etc.
    var notes: String?

    init(
        id: UUID = UUID(),
        importId: String? = nil,
        importDate: Date = Date(),
        filename: String = "",
        fileHash: String = "",
        totalRowCount: Int = 0,
        addedCount: Int = 0,
        duplicateCount: Int = 0,
        skippedCount: Int = 0,
        source: String? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.importId = importId
        self.importDate = importDate
        self.filename = filename
        self.fileHash = fileHash
        self.totalRowCount = totalRowCount
        self.addedCount = addedCount
        self.duplicateCount = duplicateCount
        self.skippedCount = skippedCount
        self.source = source
        self.notes = notes
    }

    func toImportHistory() -> ImportHistory {
        ImportHistory(
            id: id,
            importId: importId ?? id.uuidString,
            importDate: importDate ?? Date(),
            filename: filename ?? "不明なファイル",
            fileHash: fileHash ?? "",
            totalRowCount: totalRowCount,
            addedCount: addedCount,
            duplicateCount: duplicateCount,
            skippedCount: skippedCount,
            source: source,
            notes: notes
        )
    }
}

/// ImportHistory struct (for use in views)
struct ImportHistory: Identifiable, Codable {
    var id: UUID
    var importId: String           // Phase1: インポート単位の一意ID
    var importDate: Date
    var filename: String
    var fileHash: String
    var totalRowCount: Int
    var addedCount: Int
    var duplicateCount: Int
    var skippedCount: Int
    var source: String?
    var notes: String?

    init(
        id: UUID = UUID(),
        importId: String = UUID().uuidString,
        importDate: Date = Date(),
        filename: String,
        fileHash: String,
        totalRowCount: Int,
        addedCount: Int,
        duplicateCount: Int,
        skippedCount: Int = 0,
        source: String? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.importId = importId
        self.importDate = importDate
        self.filename = filename
        self.fileHash = fileHash
        self.totalRowCount = totalRowCount
        self.addedCount = addedCount
        self.duplicateCount = duplicateCount
        self.skippedCount = skippedCount
        self.source = source
        self.notes = notes
    }
}

// MARK: - Database Configuration

enum DatabaseConfig {
    static let schema = Schema([
        TransactionModel.self,
        CategoryModel.self,
        CategoryGroupModel.self,
        CategoryItemModel.self,
        AccountModel.self,
        BudgetModel.self,
        FixedCostTemplateModel.self,
        ImportHistoryModel.self
    ])
    
    static var modelConfiguration: ModelConfiguration {
        ModelConfiguration(
            "KakeiboDatabase",
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true
        )
    }
    
    @MainActor
    static func createContainer() throws -> ModelContainer {
        try ModelContainer(for: schema, configurations: [modelConfiguration])
    }
}
