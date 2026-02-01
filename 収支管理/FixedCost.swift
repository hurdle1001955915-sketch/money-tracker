import Foundation

struct FixedCostTemplate: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var type: TransactionType
    var amount: Int
    
    /// 新仕様: カテゴリID
    var categoryId: UUID?
    
    /// 旧仕様: カテゴリ名（移行用）
    var originalCategoryName: String?
    
    var dayOfMonth: Int
    var memo: String
    var isEnabled: Bool
    var lastProcessedMonth: String
    var createdAt: Date
    
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
        self.type = type
        self.amount = amount
        self.categoryId = categoryId
        self.originalCategoryName = originalCategoryName
        self.dayOfMonth = dayOfMonth
        self.memo = memo
        self.isEnabled = isEnabled
        self.lastProcessedMonth = lastProcessedMonth
        self.createdAt = createdAt
    }
    
    var dayOfMonthDisplay: String {
        dayOfMonth == 0 ? "末日" : "\(dayOfMonth)日"
    }
    
    // MARK: - Backward Compatible Decoder
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        type = try container.decode(TransactionType.self, forKey: .type)
        amount = try container.decode(Int.self, forKey: .amount)
        
        categoryId = try container.decodeIfPresent(UUID.self, forKey: .categoryId)
        if let stringCat = try container.decodeIfPresent(String.self, forKey: .category) {
            if categoryId == nil {
                originalCategoryName = stringCat
            }
        } else {
             originalCategoryName = try container.decodeIfPresent(String.self, forKey: .originalCategoryName)
        }
        
        dayOfMonth = try container.decode(Int.self, forKey: .dayOfMonth)
        memo = try container.decode(String.self, forKey: .memo)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        lastProcessedMonth = try container.decode(String.self, forKey: .lastProcessedMonth)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(type, forKey: .type)
        try container.encode(amount, forKey: .amount)
        try container.encodeIfPresent(categoryId, forKey: .categoryId)
        try container.encodeIfPresent(originalCategoryName, forKey: .originalCategoryName)
        try container.encode(dayOfMonth, forKey: .dayOfMonth)
        try container.encode(memo, forKey: .memo)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(lastProcessedMonth, forKey: .lastProcessedMonth)
        try container.encode(createdAt, forKey: .createdAt)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, type, amount, categoryId, category, originalCategoryName, dayOfMonth, memo, isEnabled, lastProcessedMonth, createdAt
    }
}
