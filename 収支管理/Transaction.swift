import Foundation

enum TransactionType: String, Codable, CaseIterable {
    case expense = "expense"
    case income = "income"
    case transfer = "transfer"

    var displayName: String {
        switch self {
        case .expense: return "支出"
        case .income: return "収入"
        case .transfer: return "振替"
        }
    }

    /// 集計対象のタイプ（振替は除外）
    static var countableTypes: [TransactionType] {
        [.expense, .income]
    }
}

// MARK: - Classification Source

/// 分類元の種別（どの方法で分類されたか）
enum ClassificationSource: String, Codable, CaseIterable {
    case manual = "manual"       // 手動分類
    case rule = "rule"           // ルールベース自動分類
    case ai = "ai"               // AI自動分類
    case imported = "imported"   // CSVインポート時のカテゴリ
    case unknown = "unknown"     // 不明（移行データ等）

    var displayName: String {
        switch self {
        case .manual: return "手動"
        case .rule: return "ルール"
        case .ai: return "AI"
        case .imported: return "インポート"
        case .unknown: return "不明"
        }
    }
}

/// 取引の入力元をアプリ内で安定して扱うための既知ソース一覧
/// 保存は Transaction.source の String を維持し、KnownSource は補助として使う
enum KnownTransactionSource: String, CaseIterable {
    case paypay = "PayPay"
    case resona = "Resona"
    case amazonCard = "AmazonCard"
}

struct Transaction: Identifiable, Codable, Equatable {
    var id: UUID
    var date: Date
    var type: TransactionType
    var amount: Int
    
    /// カテゴリID（新仕様）
    var categoryId: UUID?
    
    /// 旧仕様のカテゴリ画像（移行用・未分類用）
    /// categoryIdが解決できない場合のバックアップとして使用
    var originalCategoryName: String?
    
    var memo: String
    var isRecurring: Bool
    var templateId: UUID?
    var createdAt: Date

    /// CSVインポート元の識別用（重複判定精度向上のため）
    var source: String?
    var sourceId: String?

    /// 口座/財布ID（振替用）
    var accountId: UUID?

    /// 振替先口座ID（振替用）
    var toAccountId: UUID?

    /// 親取引ID（分割用）
    var parentId: UUID?

    /// 分割取引かどうか
    var isSplit: Bool

    /// ソフト削除フラグ（Undo用）
    var isDeleted: Bool
    
    /// Phase1: インポート追跡用
    var importId: String?
    var sourceHash: String?

    /// Phase3-1: 振替ペアリング用
    /// 同じtransferIdを持つ2件の取引がペアとなる
    var transferId: String?

    // MARK: - 分類情報フィールド（CSV拡張用）

    /// 分類元（どの方法で分類されたか）
    var classificationSource: ClassificationSource?

    /// 分類に使用されたルールID
    var classificationRuleId: UUID?

    /// 分類の信頼度（0.0〜1.0、AI分類時に使用）
    var classificationConfidence: Double?

    /// 分類理由（ルール名、AIの判定理由など）
    var classificationReason: String?

    /// 自動提案されたカテゴリID（ユーザーが変更した場合、categoryIdと異なる値になる）
    var suggestedCategoryId: UUID?

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
        self.type = type
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
        self.classificationSource = classificationSource
        self.classificationRuleId = classificationRuleId
        self.classificationConfidence = classificationConfidence
        self.classificationReason = classificationReason
        self.suggestedCategoryId = suggestedCategoryId
    }

    // MARK: - Derived / Helpers

    /// 既知ソースなら enum で返す
    var knownSource: KnownTransactionSource? {
        guard let source = source?.trimmingCharacters(in: .whitespacesAndNewlines),
              !source.isEmpty else { return nil }
        return KnownTransactionSource(rawValue: source)
    }

    /// 集計対象かどうか
    var isCountable: Bool {
        TransactionType.countableTypes.contains(type) && !isDeleted
    }

    /// テキスト検索用プロパティ（正規化済み）
    /// カテゴリ名を含めるには外部解決が必要だが、ここでは保持している情報のみ
    var normalizedSearchText: String {
        let nMemo = TextNormalizer.normalize(memo)
        let nCategory = TextNormalizer.normalize(originalCategoryName ?? "")
        return "\(nMemo) \(nCategory)"
    }
    
    /// 重複チェック用のユニークキー生成補助
    var uniqueKey: String {
        let d = ISO8601DateFormatter().string(from: date)
        // 移行期は categoryId 優先、なければ originalCategoryName
        // しかし、fingerprintが既存と変わると重複判定されなくなる恐れがある。
        // -> マイグレーションで過去データがcategoryId化されていれば、以降はIDベースでキーを作ればよい。
        // しかしIDはUUID文字列なので、以前の日本語カテゴリ名とは異なる。
        // つまりfingerprintが変わってしまう。これは許容する（既存データは既に保存済み）。
        // 新規インポート時の判定が問題。
        // -> インポート時は「名前」しか分からない。
        // -> したがって、インポート時の重複チェックは「名前」で行う必要がある。
        // -> Transaction側で「解決済みの名前」を使ってキーを作る必要があるが、Transaction単体では名前がわからない。
        // 
        // 解決策: fingerprintKey計算時は、DataStore側で解決した名前を渡すか、
        // あるいは `originalCategoryName` にインポート時の名前が入っていることを期待するか。
        // インポート直後のTransactionは `originalCategoryName` に名前が入っているはず（未解決なら）。
        // ID解決後も `originalCategoryName` を残すべきか？ -> "Don't duplicate".
        // 
        // 妥協点: fingerprintKey は一旦 `categoryId?.uuidString ?? originalCategoryName ?? ""` を使う。
        // これにより、既存データ(ID化後)と新規インポートデータ(ID解決前)でキーが合わなくなる。
        // 
        // 修正案: DataStoreで重複チェックする際、既存TransactionのIDから名前を引いて比較するか、
        // インポートデータ側をID解決してから比較するか。
        // 
        // ここでは単純なプロパティ定義に留め、ロジックはDataStoreで吸収する。
        return "\(d)|\(type.rawValue)|\(amount)|\(categoryId?.uuidString ?? originalCategoryName ?? "")|\(memo)"
    }
    
    /// マッチング判定（検索等）
    func matches(keyword: String) -> Bool {
        if keyword.isEmpty { return true }
        let nKeyword = TextNormalizer.normalize(keyword)
        
        if TextNormalizer.normalize(memo).contains(nKeyword) { return true }
        // カテゴリ名での検索は、ID解決できないここでは originalCategoryName のみ対象
        if let original = originalCategoryName, TextNormalizer.normalize(original).contains(nKeyword) { return true }
        if let source = source, TextNormalizer.normalize(source).contains(nKeyword) { return true }
        if let sourceId = sourceId, TextNormalizer.normalize(sourceId).contains(nKeyword) { return true }
        
        return false
    }

    /// 分類用にメモを正規化した文字列
    var normalizedMemoForClassification: String {
        TextNormalizer.normalize(memo)
    }

    // MARK: - Transfer Helpers

    /// 振替取引かどうか
    var isTransfer: Bool {
        type == .transfer
    }

    /// 振替元口座名を動的に取得（AccountStoreから）
    func fromAccountName(accountStore: AccountStore) -> String? {
        guard let accountId = accountId else { return nil }
        return accountStore.account(for: accountId)?.name
    }

    /// 振替先口座名を動的に取得（AccountStoreから）
    func toAccountName(accountStore: AccountStore) -> String? {
        guard let toAccountId = toAccountId else { return nil }
        return accountStore.account(for: toAccountId)?.name
    }

    /// 振替の表示ラベル（動的に口座名を解決）
    /// 例: "現金 → 銀行口座"
    func transferDisplayLabel(accountStore: AccountStore) -> String {
        let fromName = fromAccountName(accountStore: accountStore) ?? "不明"
        let toName = toAccountName(accountStore: accountStore) ?? "不明"
        return "\(fromName) → \(toName)"
    }

    /// 指定口座から見た時の振替方向
    /// - Returns: .outgoing (出金), .incoming (入金), .none (関係なし)
    func transferDirection(for accountId: UUID) -> TransferDirection {
        guard isTransfer else { return .none }
        if self.accountId == accountId {
            return .outgoing
        } else if self.toAccountId == accountId {
            return .incoming
        }
        return .none
    }

    /// 重複判定用の指紋（最適化版）
    /// - 振替の場合: 口座IDも含める
    /// - カテゴリIDを優先、なければ正規化された名前
    /// - source/sourceIdも含めて一意性を高める
    var fingerprintKey: String {
        let cal = Calendar(identifier: .gregorian)
        let day = cal.startOfDay(for: date)

        // カテゴリ部分: IDを優先、なければ正規化された名前
        let catStr = categoryId?.uuidString ?? TextNormalizer.normalize(originalCategoryName ?? "")

        // 基本要素
        var components: [String] = [
            "\(day.timeIntervalSince1970)",
            type.rawValue,
            "\(amount)",
            catStr,
            TextNormalizer.normalize(memo)
        ]

        // 振替の場合は口座情報も含める
        if type == .transfer {
            components.append(accountId?.uuidString ?? "")
            components.append(toAccountId?.uuidString ?? "")
        } else if let accId = accountId {
            // 通常取引でも口座が設定されていれば含める
            components.append(accId.uuidString)
        }

        // source/sourceIdがあれば追加（CSVインポート元の識別）
        let s = TextNormalizer.normalize(source ?? "")
        let sid = TextNormalizer.normalize(sourceId ?? "")
        if !s.isEmpty || !sid.isEmpty {
            components.append(s)
            components.append(sid)
        }

        return components.joined(separator: "|")
    }

    /// CSVインポート用の軽量fingerprint（カテゴリID不要）
    /// インポート時はまだカテゴリIDが割り当てられていないため、
    /// 日付・金額・メモ・source等で判定
    var importFingerprintKey: String {
        let cal = Calendar(identifier: .gregorian)
        let day = cal.startOfDay(for: date)

        var components: [String] = [
            "\(day.timeIntervalSince1970)",
            type.rawValue,
            "\(amount)",
            TextNormalizer.normalize(memo)
        ]

        // source/sourceIdがあれば追加
        let s = TextNormalizer.normalize(source ?? "")
        let sid = TextNormalizer.normalize(sourceId ?? "")
        if !s.isEmpty {
            components.append(s)
        }
        if !sid.isEmpty {
            components.append(sid)
        }

        return components.joined(separator: "|")
    }

    // MARK: - Backward Compatible Decoder

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        date = try container.decode(Date.self, forKey: .date)
        type = try container.decode(TransactionType.self, forKey: .type)
        amount = try container.decode(Int.self, forKey: .amount)
        
        // 新仕様: categoryId
        categoryId = try container.decodeIfPresent(UUID.self, forKey: .categoryId)
        
        // 旧仕様: category (String) -> originalCategoryName
        if let oldCategory = try container.decodeIfPresent(String.self, forKey: .category) {
            // categoryIdがない場合、または移行用として保持
            if categoryId == nil {
                originalCategoryName = oldCategory
            }
            // IDがある場合でも、念のため保持しておくかは要件次第だが初期移行では保持しない方が綺麗
            // しかし移行ロジックで「category」から読み取るので、ここは単に「古いキーがあれば読む」としておく
        } else {
             // originalCategoryNameキーが将来的にセーブされるなら読む
             originalCategoryName = try container.decodeIfPresent(String.self, forKey: .originalCategoryName)
        }
        
        memo = try container.decode(String.self, forKey: .memo)
        isRecurring = try container.decode(Bool.self, forKey: .isRecurring)
        templateId = try container.decodeIfPresent(UUID.self, forKey: .templateId)
        createdAt = try container.decode(Date.self, forKey: .createdAt)

        source = try container.decodeIfPresent(String.self, forKey: .source)
        sourceId = try container.decodeIfPresent(String.self, forKey: .sourceId)
        accountId = try container.decodeIfPresent(UUID.self, forKey: .accountId)
        toAccountId = try container.decodeIfPresent(UUID.self, forKey: .toAccountId)
        parentId = try container.decodeIfPresent(UUID.self, forKey: .parentId)
        isSplit = try container.decodeIfPresent(Bool.self, forKey: .isSplit) ?? false
        isDeleted = try container.decodeIfPresent(Bool.self, forKey: .isDeleted) ?? false
        importId = try container.decodeIfPresent(String.self, forKey: .importId)
        sourceHash = try container.decodeIfPresent(String.self, forKey: .sourceHash)
        transferId = try container.decodeIfPresent(String.self, forKey: .transferId)

        // 分類情報フィールド（後方互換：存在しない場合はnil）
        classificationSource = try container.decodeIfPresent(ClassificationSource.self, forKey: .classificationSource)
        classificationRuleId = try container.decodeIfPresent(UUID.self, forKey: .classificationRuleId)
        classificationConfidence = try container.decodeIfPresent(Double.self, forKey: .classificationConfidence)
        classificationReason = try container.decodeIfPresent(String.self, forKey: .classificationReason)
        suggestedCategoryId = try container.decodeIfPresent(UUID.self, forKey: .suggestedCategoryId)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(date, forKey: .date)
        try container.encode(type, forKey: .type)
        try container.encode(amount, forKey: .amount)
        try container.encodeIfPresent(categoryId, forKey: .categoryId)
        try container.encodeIfPresent(originalCategoryName, forKey: .originalCategoryName)
        // 旧 category キーには書き込まない（移行完了後は消える）
        try container.encode(memo, forKey: .memo)
        try container.encode(isRecurring, forKey: .isRecurring)
        try container.encodeIfPresent(templateId, forKey: .templateId)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(source, forKey: .source)
        try container.encodeIfPresent(sourceId, forKey: .sourceId)
        try container.encodeIfPresent(accountId, forKey: .accountId)
        try container.encodeIfPresent(toAccountId, forKey: .toAccountId)
        try container.encodeIfPresent(parentId, forKey: .parentId)
        try container.encode(isSplit, forKey: .isSplit)
        try container.encode(isDeleted, forKey: .isDeleted)
        try container.encodeIfPresent(importId, forKey: .importId)
        try container.encodeIfPresent(sourceHash, forKey: .sourceHash)
        try container.encodeIfPresent(transferId, forKey: .transferId)

        // 分類情報フィールド
        try container.encodeIfPresent(classificationSource, forKey: .classificationSource)
        try container.encodeIfPresent(classificationRuleId, forKey: .classificationRuleId)
        try container.encodeIfPresent(classificationConfidence, forKey: .classificationConfidence)
        try container.encodeIfPresent(classificationReason, forKey: .classificationReason)
        try container.encodeIfPresent(suggestedCategoryId, forKey: .suggestedCategoryId)
    }

    private enum CodingKeys: String, CodingKey {
        case id, date, type, amount, categoryId, category, originalCategoryName, memo, isRecurring, templateId, createdAt
        case source, sourceId, accountId, toAccountId, parentId, isSplit, isDeleted, importId, sourceHash, transferId
        case classificationSource, classificationRuleId, classificationConfidence, classificationReason, suggestedCategoryId
    }
}

// MARK: - Transfer Direction

/// 振替の方向
enum TransferDirection {
    case outgoing  // 出金（振替元）
    case incoming  // 入金（振替先）
    case none      // 関係なし
}

// MARK: - Account

enum AccountType: String, Codable, CaseIterable {
    case bank = "bank"
    case creditCard = "creditCard"
    case electronicMoney = "electronicMoney"
    case payPay = "payPay"
    case suica = "suica"
    case cash = "cash"
    case investment = "investment"
    case other = "other"

    var displayName: String {
        switch self {
        case .bank: return "銀行口座"
        case .creditCard: return "クレジットカード"
        case .electronicMoney: return "電子マネー"
        case .payPay: return "PayPay"
        case .suica: return "Suica"
        case .cash: return "現金"
        case .investment: return "投資口座"
        case .other: return "その他"
        }
    }
}

struct Account: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var type: AccountType
    var initialBalance: Int
    var colorHex: String
    var order: Int
    var isActive: Bool
    var createdAt: Date

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
        self.type = type
        self.initialBalance = initialBalance
        self.colorHex = colorHex
        self.order = order
        self.isActive = isActive
        self.createdAt = createdAt
    }
}
