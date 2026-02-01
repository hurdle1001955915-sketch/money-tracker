import Foundation

struct Budget: Identifiable, Codable, Equatable {
    var id: UUID
    
    /// 新仕様: カテゴリID (nilなら全体予算)
    var categoryId: UUID?
    
    /// 旧仕様: カテゴリ名（移行用）
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
    
    // MARK: - Backward Compatible Decoder
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(UUID.self, forKey: .id)
        
        categoryId = try container.decodeIfPresent(UUID.self, forKey: .categoryId)
        if let stringCat = try container.decodeIfPresent(String.self, forKey: .category) {
             if categoryId == nil && !stringCat.isEmpty {
                 originalCategoryName = stringCat
             }
        } else {
             originalCategoryName = try container.decodeIfPresent(String.self, forKey: .originalCategoryName)
        }
        
        amount = try container.decode(Int.self, forKey: .amount)
        month = try container.decode(Int.self, forKey: .month)
        year = try container.decode(Int.self, forKey: .year)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(categoryId, forKey: .categoryId)
        try container.encodeIfPresent(originalCategoryName, forKey: .originalCategoryName)
        try container.encode(amount, forKey: .amount)
        try container.encode(month, forKey: .month)
        try container.encode(year, forKey: .year)
    }

    private enum CodingKeys: String, CodingKey {
        case id, categoryId, category, originalCategoryName, amount, month, year
    }
}
