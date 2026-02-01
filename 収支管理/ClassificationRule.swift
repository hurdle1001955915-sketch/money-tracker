import Foundation
import Combine
import SwiftUI

// MARK: - 自動分類ルール

/// メモや店舗名から自動でカテゴリを割り当てるルール
struct ClassificationRule: Identifiable, Codable, Equatable {
    var id: UUID
    var keyword: String           // マッチするキーワード（部分一致）
    var matchType: MatchType      // マッチ方法
    
    /// 新仕様: カテゴリID
    var targetCategoryId: UUID?
    
    /// 旧仕様: カテゴリ名（移行用・ID未解決時用）
    var targetCategoryName: String?
    
    var transactionType: TransactionType  // 支出/収入
    var isEnabled: Bool
    var priority: Int             // 優先度（高いほど優先）
    var createdAt: Date
    
    init(
        id: UUID = UUID(),
        keyword: String,
        matchType: MatchType = .contains,
        targetCategoryId: UUID? = nil,
        targetCategoryName: String? = nil,
        transactionType: TransactionType = .expense,
        isEnabled: Bool = true,
        priority: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.keyword = keyword
        self.matchType = matchType
        self.targetCategoryId = targetCategoryId
        self.targetCategoryName = targetCategoryName
        self.transactionType = transactionType
        self.isEnabled = isEnabled
        self.priority = priority
        self.createdAt = createdAt
    }
    
    /// マッチ方法
    enum MatchType: String, Codable, CaseIterable, Identifiable {
        case contains = "contains"       // 部分一致
        case prefix = "prefix"           // 前方一致
        case suffix = "suffix"           // 後方一致
        case exact = "exact"             // 完全一致
        
        var id: String { rawValue }
        
        var displayName: String {
            switch self {
            case .contains: return "含む"
            case .prefix: return "で始まる"
            case .suffix: return "で終わる"
            case .exact: return "完全一致"
            }
        }
    }
    
    /// テキストがルールにマッチするか判定
    func matches(_ text: String) -> Bool {
        guard isEnabled, !keyword.isEmpty else { return false }

        let normText = TextNormalizer.normalize(text)
        let normKeyword = TextNormalizer.normalize(keyword)

        switch matchType {
        case .contains:
            return normText.contains(normKeyword)
        case .prefix:
            return normText.hasPrefix(normKeyword)
        case .suffix:
            return normText.hasSuffix(normKeyword)
        case .exact:
            return normText == normKeyword
        }
    }

    /// マッチング用に正規化（TextNormalizerに委譲）
    static func normalizeForMatching(_ input: String) -> String {
        TextNormalizer.normalize(input)
    }
    
    // MARK: - Backward Compatible Decoder
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(UUID.self, forKey: .id)
        keyword = try container.decode(String.self, forKey: .keyword)
        matchType = try container.decode(MatchType.self, forKey: .matchType)
        
        // Target Category Migration
        targetCategoryId = try container.decodeIfPresent(UUID.self, forKey: .targetCategoryId)
        if let stringCat = try container.decodeIfPresent(String.self, forKey: .targetCategory) {
            if targetCategoryId == nil {
                targetCategoryName = stringCat
            }
        } else {
             targetCategoryName = try container.decodeIfPresent(String.self, forKey: .targetCategoryName)
        }
        
        transactionType = try container.decode(TransactionType.self, forKey: .transactionType)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        priority = try container.decode(Int.self, forKey: .priority)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(keyword, forKey: .keyword)
        try container.encode(matchType, forKey: .matchType)
        
        try container.encodeIfPresent(targetCategoryId, forKey: .targetCategoryId)
        try container.encodeIfPresent(targetCategoryName, forKey: .targetCategoryName)
        // 旧 targetCategory には書き込まない
        
        try container.encode(transactionType, forKey: .transactionType)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(priority, forKey: .priority)
        try container.encode(createdAt, forKey: .createdAt)
    }
    
    private enum CodingKeys: String, CodingKey {
        case id, keyword, matchType, targetCategoryId, targetCategory, targetCategoryName, transactionType, isEnabled, priority, createdAt
    }
}

// MARK: - ClassificationRulesStore

/// 自動分類ルールの管理
@MainActor
final class ClassificationRulesStore: ObservableObject {
    static let shared = ClassificationRulesStore()
    
    private let storageKey = "classification_rules_v1"
    
    @Published private(set) var rules: [ClassificationRule] = []
    
    private init() {
        loadRules()
    }
    
    // MARK: - CRUD
    
    func addRule(_ rule: ClassificationRule) {
        rules.append(rule)
        saveRules()
    }
    
    func updateRule(_ rule: ClassificationRule) {
        if let idx = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[idx] = rule
            saveRules()
        }
    }
    
    func deleteRule(_ rule: ClassificationRule) {
        rules.removeAll { $0.id == rule.id }
        saveRules()
    }
    
    func reorderRules(from: IndexSet, to: Int) {
        rules.move(fromOffsets: from, toOffset: to)
        // 優先度を再設定
        for (i, var rule) in rules.enumerated() {
            rule.priority = rules.count - i
            rules[i] = rule
        }
        saveRules()
    }
    
    // MARK: - Classification
    
    /// テキストに最もマッチするルールを検索
    func findMatchingRule(for text: String, type: TransactionType) -> ClassificationRule? {
        let enabledRules = rules
            .filter { $0.isEnabled && $0.transactionType == type }
            .sorted { $0.priority > $1.priority }

        // デバッグ: 最初の5つのルールの状態を出力
        if enabledRules.prefix(3).contains(where: { $0.targetCategoryId == nil }) {
            print("[findMatchingRule] WARNING: Some rules have nil targetCategoryId!")
            for rule in enabledRules.prefix(5) {
                print("  - '\(rule.keyword)': targetCategoryId=\(rule.targetCategoryId?.uuidString ?? "nil")")
            }
        }

        return enabledRules.first { $0.matches(text) }
    }
    
    /// メモからカテゴリIDを推測
    /// 1. 既存ルールでマッチを検索
    /// 2. マッチしなければキーワードからカテゴリ名を推測し、カテゴリマスタから検索
    func suggestCategoryId(for memo: String, type: TransactionType, categories: [Category] = []) -> UUID? {
        guard !memo.isEmpty else { return nil }

        // 1. 既存ルールでマッチを検索
        if let rule = findMatchingRule(for: memo, type: type) {
            if let ruleId = rule.targetCategoryId {
                print("[suggestCategoryId] '\(memo)' matched rule '\(rule.keyword)' -> \(ruleId)")
                return ruleId
            } else {
                print("[suggestCategoryId] '\(memo)' matched rule '\(rule.keyword)' but targetCategoryId is nil!")
            }
        }

        // 2. キーワードからカテゴリ名を推測
        guard !categories.isEmpty else {
            print("[suggestCategoryId] '\(memo)' no rule match, categories empty")
            return nil
        }
        if let suggestedName = suggestCategoryNameFromKeyword(memo, type: type),
           let cat = categories.first(where: { $0.name == suggestedName && $0.type == type }) {
            print("[suggestCategoryId] '\(memo)' suggested '\(suggestedName)' -> \(cat.id)")
            return cat.id
        }

        print("[suggestCategoryId] '\(memo)' no match found")
        return nil
    }
    
    /// 複数のテキストフィールドからカテゴリIDを推測
    func suggestCategoryId(from texts: [String], type: TransactionType, categories: [Category] = []) -> UUID? {
        for text in texts {
            if let catId = suggestCategoryId(for: text, type: type, categories: categories) {
                return catId
            }
        }
        return nil
    }
    
    /// ユーザーの手動分類を学習して次回以降に反映
    func learn(from tx: Transaction) {
        // 振替は対象外
        guard tx.type != .transfer else { return }
        // ターゲットカテゴリIDが必要
        guard let targetId = tx.categoryId else { return }
        
        let memo = tx.memo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard memo.count >= 2 else { return }
        
        // 既存ルールで既に同カテゴリが提案されるなら追加しない
        if let suggestedId = suggestCategoryId(for: memo, type: tx.type), suggestedId == targetId {
            return
        }
        
        // 同一キーワード・タイプ・カテゴリのルールが無ければ追加
        let exists = rules.contains { r in
            r.transactionType == tx.type && r.targetCategoryId == targetId && ClassificationRule.normalizeForMatching(r.keyword) == ClassificationRule.normalizeForMatching(memo)
        }
        
        if !exists {
            let rule = ClassificationRule(
                keyword: memo,
                matchType: .contains,
                targetCategoryId: targetId,
                transactionType: tx.type,
                isEnabled: true,
                priority: 20
            )
            rules.append(rule)
            saveRules()
        }
    }
    
    // MARK: - Keyword Search (for conflict detection)
    
    /// キーワードで既存ルールを検索（未分類レビュー用）
    func findByKeyword(_ keyword: String, type: TransactionType) -> ClassificationRule? {
        let normalized = ClassificationRule.normalizeForMatching(keyword)
        return rules.first { r in
            r.transactionType == type && ClassificationRule.normalizeForMatching(r.keyword) == normalized
        }
    }
    
    /// ルール追加（衝突チェック付き）
    func addRuleWithCheck(_ rule: ClassificationRule) -> (success: Bool, conflictingRule: ClassificationRule?) {
        if let existing = findByKeyword(rule.keyword, type: rule.transactionType) {
            return (false, existing)
        }
        rules.append(rule)
        saveRules()
        return (true, nil)
    }
    
    /// 既存ルールを上書き
    func overwriteRule(existingId: UUID, with newRule: ClassificationRule) {
        if let idx = rules.firstIndex(where: { $0.id == existingId }) {
            rules[idx] = newRule
            saveRules()
        }
    }

    /// すべてのルールを削除
    func clearAllRules() {
        rules.removeAll()
        saveRules()
    }

    /// バックアップからの復元（全置換）
    func restoreRules(_ newRules: [ClassificationRule]) {
        rules = newRules
        saveRules()
        print("Restored \(rules.count) classification rules from backup")
    }

    /// デフォルトルールが存在しない場合、初期ルールを注入する
    @MainActor
    func ensureDefaultRules(with dataStore: DataStore) {
        // 既にルールがある場合は収入ルールのマージのみ行う
        if !rules.isEmpty {
            ensureIncomeRules(with: dataStore)
            return
        }
        
        let defaults: [(keyword: String, category: String, type: TransactionType)] = [
            // コンビニ
            ("セブン", "コンビニ", .expense),
            ("ファミマ", "コンビニ", .expense),
            ("ローソン", "コンビニ", .expense),
            ("ミニストップ", "コンビニ", .expense),
            ("DAILY YAMAZAKI", "コンビニ", .expense),
            
            // スーパー
            ("イオン", "スーパー", .expense),
            ("イトーヨーカドー", "スーパー", .expense),
            ("ライフ", "スーパー", .expense),
            ("オーケー", "スーパー", .expense),
            ("西友", "スーパー", .expense),
            ("まいばすけっと", "スーパー", .expense),
            
            // 外食・カフェ
            ("マクドナルド", "外食", .expense),
            ("スターバックス", "カフェ", .expense),
            ("スタバ", "カフェ", .expense),
            ("ドトール", "カフェ", .expense),
            ("タリーズ", "カフェ", .expense),
            ("サイゼリヤ", "外食", .expense),
            ("すき家", "外食", .expense),
            ("松屋", "外食", .expense),
            ("吉野家", "外食", .expense),
            ("くら寿司", "外食", .expense),
            ("スシロー", "外食", .expense),
            
            // デリバリー
            ("Uber", "デリバリー", .expense),
            ("出前館", "デリバリー", .expense),
            
            // 買い物
            ("Amazon", "Amazon", .expense),
            ("アマゾン", "Amazon", .expense),
            ("ユニクロ", "衣服", .expense),
            ("GU", "衣服", .expense),
            ("ニトリ", "家具・インテリア", .expense),
            ("ダイソー", "雑貨", .expense),
            ("セリア", "雑貨", .expense),
            ("マツモトキヨシ", "ドラッグストア", .expense),
            ("ウエルシア", "ドラッグストア", .expense),
            
            // 移動
            ("JR", "電車・駅", .expense),
            ("スイカ", "交通費", .expense),
            ("Suica", "交通費", .expense),
            ("パスモ", "交通費", .expense),
            ("PASMO", "交通費", .expense),
            ("タクシー", "タクシー", .expense),
            ("ENEOS", "ガソリン", .expense),
            ("出光", "ガソリン", .expense),
            ("ETC", "高速道路", .expense),
            
            // 通信
            ("ソフトバンク", "通信費", .expense),
            ("ドコモ", "通信費", .expense),
            ("KDDI", "通信費", .expense),
            ("楽天モバイル", "通信費", .expense),
            ("NTT", "通信費", .expense),
            
            // サブスク
            ("APPLE", "サブスク・デジタル", .expense),
            ("GOOGLE", "サブスク・デジタル", .expense),
            ("NETFLIX", "サブスク・デジタル", .expense),
            ("Spotify", "サブスク・デジタル", .expense),
            ("YOUTUBE", "サブスク・デジタル", .expense),
            ("Uber", "サブスク・デジタル", .expense),
            ("LINE", "サブスク・デジタル", .expense),

            // タクシー
            ("未来都", "タクシー", .expense),
            ("国際興業", "タクシー", .expense),
            ("GO", "タクシー", .expense),
            ("DiDi", "タクシー", .expense),

            // 高速道路
            ("NEXCO", "高速道路", .expense),
            ("ETC", "高速道路", .expense),

            // 駐車場
            ("パーキング", "駐車場", .expense),
            ("ピットデザイン", "駐車場", .expense),
            ("タイムズ", "駐車場", .expense),
            ("Times", "駐車場", .expense),

            // 百貨店・モール
            ("PARCO", "百貨店", .expense),
            ("パルコ", "百貨店", .expense),
            ("ルミネ", "百貨店", .expense),
            ("なんばCITY", "百貨店", .expense),
            ("なんばパークス", "百貨店", .expense),

            // 娯楽
            ("シネマ", "娯楽", .expense),
            ("映画", "娯楽", .expense),
            ("ROUND1", "娯楽", .expense),
            ("ラウンドワン", "娯楽", .expense),
            ("動物園", "娯楽", .expense),
            ("水族館", "娯楽", .expense),

            // イベント
            ("TICKET", "イベント", .expense),
            ("チケット", "イベント", .expense),
            ("EXPO", "イベント", .expense),

            // 中古・買取
            ("GEO", "中古・買取", .expense),
            ("ゲオ", "中古・買取", .expense),
            ("2nd STREET", "中古・買取", .expense),
            ("セカンドストリート", "中古・買取", .expense),

            // 現金・ATM
            ("ATM", "現金入出金", .expense),
            ("郵便局", "現金入出金", .expense),

            // ===== 収入ルール =====

            // 給与・賞与
            ("給与", "給与", .income),
            ("給料", "給与", .income),
            ("賞与", "賞与", .income),
            ("ボーナス", "賞与", .income),

            // 利息
            ("利息", "利息", .income),
            ("利子", "利息", .income),

            // ポイント還元
            ("ポイント還元", "ポイント還元", .income),
            ("キャッシュバック", "ポイント還元", .income),
            ("PayPayボーナス", "ポイント還元", .income),
            ("dポイント", "ポイント還元", .income),
            ("楽天ポイント", "ポイント還元", .income),
            ("Amazonポイント", "ポイント還元", .income),
            ("Tポイント", "ポイント還元", .income),
            ("Pontaポイント", "ポイント還元", .income),

            // 還付金
            ("還付金", "還付金", .income),
            ("税務署", "還付金", .income),
            ("確定申告", "還付金", .income),

            // 失業保険
            ("失業保険", "失業保険", .income),
            ("ハローワーク", "失業保険", .income),
            ("雇用保険", "失業保険", .income),

            // 副業
            ("副業", "副業", .income),
            ("報酬", "副業", .income),

            // 受け取り・返金
            ("返金", "受け取り", .income),
            ("払戻", "受け取り", .income),
            ("フリマ売上", "受け取り", .income),
            ("メルカリ売上", "受け取り", .income),
            ("ラクマ売上", "受け取り", .income),
        ]
        
        var newRules: [ClassificationRule] = []
        
        for def in defaults {
            // カテゴリ名をIDに解決
            if let category = dataStore.findCategory(name: def.category, type: def.type) {
                let rule = ClassificationRule(
                    keyword: def.keyword,
                    matchType: .contains,
                    targetCategoryId: category.id,
                    targetCategoryName: category.name, // バックアップ互換用
                    transactionType: def.type,
                    isEnabled: true,
                    priority: 50 // デフォルト優先度は中程度
                )
                newRules.append(rule)
            }
        }
        
        if !newRules.isEmpty {
            rules.append(contentsOf: newRules)
            saveRules()
            print("Initialized \(newRules.count) default classification rules.")
        }
    }

    /// 既存ユーザーに収入ルールを追加（マイグレーション）
    /// 一度だけ実行され、UserDefaultsにフラグを保存
    @MainActor
    private func ensureIncomeRules(with dataStore: DataStore) {
        let migrationKey = "income_rules_migration_v1"

        // 既にマイグレーション済みならスキップ
        if UserDefaults.standard.bool(forKey: migrationKey) {
            return
        }

        let incomeDefaults: [(keyword: String, category: String)] = [
            // 給与・賞与
            ("給与", "給与"),
            ("給料", "給与"),
            ("賞与", "賞与"),
            ("ボーナス", "賞与"),

            // 利息
            ("利息", "利息"),
            ("利子", "利息"),

            // ポイント還元
            ("ポイント還元", "ポイント還元"),
            ("キャッシュバック", "ポイント還元"),
            ("PayPayボーナス", "ポイント還元"),
            ("dポイント", "ポイント還元"),
            ("楽天ポイント", "ポイント還元"),
            ("Amazonポイント", "ポイント還元"),
            ("Tポイント", "ポイント還元"),
            ("Pontaポイント", "ポイント還元"),

            // 還付金
            ("還付金", "還付金"),
            ("税務署", "還付金"),
            ("確定申告", "還付金"),

            // 失業保険
            ("失業保険", "失業保険"),
            ("ハローワーク", "失業保険"),
            ("雇用保険", "失業保険"),

            // 副業
            ("副業", "副業"),
            ("報酬", "副業"),

            // 受け取り・返金
            ("返金", "受け取り"),
            ("払戻", "受け取り"),
            ("フリマ売上", "受け取り"),
            ("メルカリ売上", "受け取り"),
            ("ラクマ売上", "受け取り"),
        ]

        var addedCount = 0

        for def in incomeDefaults {
            // 既に同じキーワード+タイプのルールがあればスキップ
            let normalizedKeyword = ClassificationRule.normalizeForMatching(def.keyword)
            let exists = rules.contains { r in
                r.transactionType == .income &&
                ClassificationRule.normalizeForMatching(r.keyword) == normalizedKeyword
            }

            if exists {
                continue
            }

            // カテゴリ名をIDに解決
            if let category = dataStore.findCategory(name: def.category, type: .income) {
                let rule = ClassificationRule(
                    keyword: def.keyword,
                    matchType: .contains,
                    targetCategoryId: category.id,
                    targetCategoryName: category.name,
                    transactionType: .income,
                    isEnabled: true,
                    priority: 50
                )
                rules.append(rule)
                addedCount += 1
            }
        }

        if addedCount > 0 {
            saveRules()
            print("[ensureIncomeRules] Added \(addedCount) income rules for existing user.")
        }

        // マイグレーション完了フラグを設定
        UserDefaults.standard.set(true, forKey: migrationKey)
    }

    // MARK: - Persistence
    
    private func loadRules() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([ClassificationRule].self, from: data) else {
            // デフォルトルールを設定：ここではマイグレーションが必要だが、DataStore側で一括管理する
            // したがって、初期ロード時はルールが空かもしれないし、マイグレーション待ちかもしれない
            // 一旦セットアップはせず、空で初期化してDataStoreのmigrationを待つ
            // setupDefaultRules() // ← Do not call here directly if we rely on categories
            return
        }
        rules = decoded
    }
    
    private func saveRules() {
        guard let data = try? JSONEncoder().encode(rules) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
    
    /// カテゴリマスタを使ってルールをIDベースに移行
    /// NOTE: キーワードからの推測を優先し、推測できない場合のみtargetCategoryNameを使用
    /// forceRemigrate: trueの場合、既存の有効なIDも再マイグレーション
    func migrateRules(with categories: [Category], forceRemigrate: Bool = false) {
        print("[migrateRules] Called with \(categories.count) categories, \(rules.count) rules, force=\(forceRemigrate)")

        guard !categories.isEmpty else {
            print("[migrateRules] No categories available, skipping migration")
            return
        }

        var changed = false
        for i in rules.indices {
            let rule = rules[i]

            // 強制再マイグレーションでない場合、既存の有効なIDがあればスキップ
            if !forceRemigrate, let currentId = rule.targetCategoryId {
                if categories.contains(where: { $0.id == currentId }) {
                    continue
                }
            }

            // IDをクリア
            if rules[i].targetCategoryId != nil {
                rules[i].targetCategoryId = nil
            }

            // 1. キーワードからカテゴリを推測（優先）
            if let suggestedCatName = suggestCategoryNameFromKeyword(rules[i].keyword, type: rules[i].transactionType) {
                if let cat = categories.first(where: { $0.name == suggestedCatName && $0.type == rules[i].transactionType }) {
                    rules[i].targetCategoryId = cat.id
                    rules[i].targetCategoryName = cat.name
                    changed = true
                    print("[migrateRules] Rule '\(rule.keyword)': -> '\(suggestedCatName)'")
                    continue
                } else {
                    print("[migrateRules] Rule '\(rule.keyword)': Category '\(suggestedCatName)' not found")
                }
            }

            // 2. 推測できない場合、targetCategoryNameで検索
            if let name = rules[i].targetCategoryName,
               let cat = categories.first(where: { $0.name == name && $0.type == rules[i].transactionType }) {
                rules[i].targetCategoryId = cat.id
                changed = true
                print("[migrateRules] Rule '\(rule.keyword)': -> '\(name)' (saved name)")
                continue
            }

            print("[migrateRules] Rule '\(rule.keyword)': No match found")
        }

        if changed {
            saveRules()
            print("[migrateRules] Migration complete: \(rules.count) rules, changes saved")
        } else {
            print("[migrateRules] No changes needed")
        }
    }

    /// キーワードから最適なカテゴリ名を推測
    /// NOTE: TextNormalizer.normalize は全角カタカナを半角カタカナに変換するため、
    /// 検索キーワードも同様に正規化してからチェックする
    private func suggestCategoryNameFromKeyword(_ keyword: String, type: TransactionType) -> String? {
        let normalized = TextNormalizer.normalize(keyword)

        // 例外: ChargeSPOT はレンタルサービスなので「チャージ」にしない
        if normalized.lowercased().contains("chargespot") || normalized.contains("チャージスポット") {
            return nil
        }

        // ヘルパー関数: 検索キーワードも正規化してから比較
        func matches(_ patterns: [String]) -> Bool {
            patterns.contains { normalized.contains(TextNormalizer.normalize($0)) }
        }

        if type == .expense {
            // コンビニ
            if matches(["コンビニ", "こんびに", "セブン", "せぶん", "ローソン", "ろーそん",
                        "ファミマ", "ふぁみま", "ミニストップ", "デイリーヤマザキ"]) {
                return "コンビニ"
            }
            // スーパー
            if matches(["スーパー", "すーぱー", "イオン", "西友", "イトーヨーカドー", "オーケー",
                        "ライフ", "まいばすけっと", "マルエツ", "業務スーパー"]) {
                return "スーパー"
            }
            // 外食
            if matches(["マクドナルド", "マック", "すき家", "吉野家", "松屋", "サイゼリヤ",
                        "ガスト", "モスバーガー", "ケンタッキー", "くら寿司", "スシロー",
                        "はなまる", "丸亀", "外食"]) {
                return "外食"
            }
            // カフェ
            if matches(["スタバ", "starbucks", "カフェ", "cafe", "ドトール", "タリーズ",
                        "コメダ", "星乃珈琲", "サンマルク", "ミスド", "ミスタードーナツ"]) {
                return "カフェ"
            }
            // 電車・駅
            if matches(["jr", "電車", "駅", "地下鉄", "メトロ"]) {
                return "電車・駅"
            }
            // 交通費
            if matches(["suica", "pasmo", "スイカ", "パスモ", "モバイル", "交通"]) {
                return "交通費"
            }
            // タクシー
            if matches(["タクシー", "taxi", "goタクシー", "didi", "未来都", "国際興業"]) {
                return "タクシー"
            }
            // 高速道路
            if matches(["ETC", "高速道路", "NEXCO"]) {
                return "高速道路"
            }
            // 駐車場
            if matches(["駐車場", "パーキング", "コインパーキング", "ピットデザイン", "タイムズ", "times"]) {
                return "駐車場"
            }
            // ガソリン
            if matches(["ガソリン", "エネオス", "eneos", "出光", "シェル", "コスモ石油"]) {
                return "ガソリン"
            }
            // ドラッグストア
            if matches(["ドラッグ", "マツモトキヨシ", "ウエルシア", "スギ薬局", "薬局", "サンドラッグ", "富士薬品"]) {
                return "ドラッグストア"
            }
            // Amazon
            if matches(["amazon", "アマゾン"]) { return "Amazon" }
            // 通販
            if matches(["楽天", "rakuten", "メルカリ", "mercari", "ヤフオク", "ゾゾ", "zozo", "通販", "エディオン"]) {
                return "通販"
            }
            // 水道光熱費
            if matches(["電気", "ガス", "水道", "tepco", "nhk", "電力", "ガス@"]) {
                return "水道光熱費"
            }
            // 通信費
            if matches(["通信", "ドコモ", "docomo", "ソフトバンク", "softbank", "au", "ワイモバイル", "uq"]) {
                return "通信費"
            }
            // サブスク
            if matches(["サブスク", "netflix", "spotify", "youtube", "apple", "google",
                        "icloud", "adobe", "zoom", "nintendo", "uber one", "line ec"]) {
                return "サブスク・デジタル"
            }
            // 衣服
            if matches(["ユニクロ", "uniqlo", "gu", "ジーユー", "衣服", "服", "無印良品", "muji"]) {
                return "衣服"
            }
            // 雑貨
            if matches(["ダイソー", "セリア", "seria", "100均", "雑貨", "ロフト", "loft", "ハンズ"]) {
                return "雑貨"
            }
            // 家具・インテリア
            if matches(["ニトリ", "ikea", "イケア", "インテリア"]) {
                return "家具・インテリア"
            }
            // 手数料（銀行振込手数料など）
            if matches(["手数料"]) {
                return "手数料"
            }
            // 奨学金返済
            if matches(["奨学金", "学生支援機構", "ガクセイシエン", "返済金"]) {
                return "奨学金返済"
            }
            // カード引落（銀行からのカード引落）
            if matches(["振替", "Dカード", "エポス", "楽天カード", "d-カード", "au pay"]) {
                return "カード引落"
            }
            // 個人送金
            if matches(["送金", "送った金額"]) {
                return "個人送金"
            }
            // チャージ
            if matches(["チャージ"]) {
                return "チャージ"
            }
            // デリバリー
            if matches(["uber eats", "出前館", "デリバリー"]) {
                return "デリバリー"
            }
            // 中古・買取
            if matches(["geo", "セカンドストリート", "買取", "中古", "ゲオ"]) {
                return "中古・買取"
            }
            // 百貨店
            if matches(["髙島屋", "高島屋", "伊勢丹", "三越", "大丸", "阪急百貨店", "なんばcity", "なんばパークス", "ルミネ", "parco", "パルコ"]) {
                return "百貨店"
            }
            // 娯楽
            if matches(["シネマ", "映画", "動物園", "水族館", "アミューズメント", "ラウンドワン"]) {
                return "娯楽"
            }
            // イベント
            if matches(["チケット", "興行", "イベント", "expo"]) {
                return "イベント"
            }
            // 現金入出金
            if matches(["カード@lans", "郵便局", "atm"]) {
                return "現金入出金"
            }
        } else if type == .income {
            // 給与
            if matches(["給与", "給料", "賞与", "ボーナス", "ゼロイチ", "ぜろいち", "振込", "会社"]) {
                return "給与"
            }
            // 利息
            if matches(["利息", "利子"]) { return "利息" }
            // ポイント還元
            if matches(["ポイント", "還元", "残高", "キャッシュバック", "マイナ", "キャンペーン"]) {
                return "ポイント還元"
            }
            // 受け取り
            if matches(["受け取", "受取", "返金", "入金"]) {
                return "受け取り"
            }
            // 還付金
            if matches(["還付", "税務署", "国税"]) {
                return "還付金"
            }
            // 副業
            if matches(["副業", "報酬", "謝礼"]) {
                return "副業"
            }
            // チャージ（入金側：ATMからのチャージ等）
            if matches(["チャージ"]) {
                return "チャージ"
            }
            // 失業保険
            if matches(["失業", "職業安定", "ショクギョウアンテイ", "ハローワーク"]) {
                return "失業保険"
            }
        }

        return nil
    }
    
    // NOTE: default rules setup logic should now rely on IDs.
    // It's better to move default rule creation to DataStore where categories are available.
    // Or keep it here but we need access to Category UUIDs.
    // For now, I will create a helper method that takes a Category map.
    
    func setupDefaultRules(with categories: [Category]) {
        // ... (Logic to map string -> ID using categories list)
        // This is complex because default rules are hardcoded strings.
        // We will implement migration logic in DataStore instead.
    }
}
