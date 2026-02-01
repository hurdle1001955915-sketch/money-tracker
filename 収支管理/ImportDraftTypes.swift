import Foundation
import SwiftUI
import Combine

// MARK: - Import Draft Types (Phase 2 + Phase 3-2 + Phase 3-3)
// CSVインポートウィザード用のドラフト（下書き）型定義
// 重要: これらはメモリ上のみで管理し、SwiftDataには保存しない

// MARK: - CSV Parse Error

struct CSVParseError: Error {
    let message: String

    init(_ message: String) {
        self.message = message
    }
}

// MARK: - Draft Row Status

/// ドラフト行のステータス
enum DraftRowStatus: String, CaseIterable {
    case resolved           // finalCategoryId確定済み
    case unresolved         // 未分類（要ユーザーアクション）
    case transferCandidate  // 振替候補（Phase3-2で判定強化）
    case transferConfirmed  // 振替確定（Phase3-3: 口座設定済み）
    case duplicate          // 重複としてスキップ
    case invalid            // パースエラー

    var displayName: String {
        switch self {
        case .resolved: return "解決済み"
        case .unresolved: return "未分類"
        case .transferCandidate: return "振替候補"
        case .transferConfirmed: return "振替確定"
        case .duplicate: return "重複"
        case .invalid: return "無効"
        }
    }

    var iconName: String {
        switch self {
        case .resolved: return "checkmark.circle.fill"
        case .unresolved: return "exclamationmark.triangle.fill"
        case .transferCandidate: return "arrow.left.arrow.right.circle.fill"
        case .transferConfirmed: return "arrow.left.arrow.right.circle.fill"
        case .duplicate: return "doc.on.doc"
        case .invalid: return "xmark.circle"
        }
    }

    var iconColor: Color {
        switch self {
        case .resolved: return .green
        case .unresolved: return .orange
        case .transferCandidate: return .blue
        case .transferConfirmed: return .green
        case .duplicate: return .gray
        case .invalid: return .red
        }
    }
}

// MARK: - Amount Sign (Phase 3-2)

/// 金額の符号（入出金方向）
enum AmountSign: String, CaseIterable {
    case plus   // 入金（プラス）
    case minus  // 出金（マイナス）
    case zero   // ゼロ

    var displayName: String {
        switch self {
        case .plus: return "入金"
        case .minus: return "出金"
        case .zero: return "0円"
        }
    }

    var icon: String {
        switch self {
        case .plus: return "arrow.down.circle.fill"
        case .minus: return "arrow.up.circle.fill"
        case .zero: return "circle"
        }
    }

    var color: Color {
        switch self {
        case .plus: return .green
        case .minus: return .red
        case .zero: return .gray
        }
    }

    var symbol: String {
        switch self {
        case .plus: return "+"
        case .minus: return "-"
        case .zero: return ""
        }
    }
    
    // Alias for backward compatibility if needed, or just use symbol
    var label: String { symbol }
}

// MARK: - Transfer Candidate Reason (Phase 3-2)

/// 振替候補と判定された理由
enum TransferCandidateReason: String, CaseIterable {
    case convenienceATM         // コンビニATM（カード/送金含む）
    case atmKeyword             // ATMキーワード
    case chargeKeyword          // チャージキーワード
    case transferKeyword        // 振替/振込キーワード
    case transferType           // type == .transfer
    case bankTransfer           // 銀行間振込
    case atmCardTransaction     // 「カード」で始まるATM取引（りそな銀行など）
    case atmLocation            // 郵便局などATM設置場所
    case none                   // 振替候補ではない

    var displayName: String {
        switch self {
        case .convenienceATM: return "コンビニATM"
        case .atmKeyword: return "ATM取引"
        case .chargeKeyword: return "チャージ"
        case .transferKeyword: return "振替・振込"
        case .transferType: return "振替タイプ"
        case .bankTransfer: return "銀行振込"
        case .atmCardTransaction: return "ATM入出金"
        case .atmLocation: return "ATM取引"
        case .none: return ""
        }
    }
}

// MARK: - Import Draft Row

/// CSVインポートのドラフト行（メモリ上のみ）
struct ImportDraftRow: Identifiable {
    var id: UUID = UUID()
    var date: Date
    var amount: Int
    var description: String       // payee/説明
    var memo: String
    var type: TransactionType

    var suggestedCategoryId: UUID? = nil   // 自動分類で推定
    var finalCategoryId: UUID? = nil       // ユーザー確定

    var status: DraftRowStatus
    var originalRow: [String]        // 元CSV行（参照用）
    var rowIndex: Int                // 行番号
    var parseError: String? = nil          // パースエラーメッセージ

    // Phase 3-2: 振替関連フィールド
    var isUserMarkedAsTransfer: Bool = false    // ユーザーが「振替として扱う」をONにしたか
    var transferCandidateReason: TransferCandidateReason = .none  // 振替候補判定理由
    var amountSign: AmountSign = .minus         // 金額の符号（入出金方向）
    var normalizedKey: String = ""              // 一括適用用のキー

    // Phase 3-3: 振替確定用フィールド
    var counterAccountId: UUID? = nil                 // 振替相手口座ID

    // Phase 3-4: AI分類情報
    var aiReason: String? = nil                       // AIによる判定理由

    /// 表示用の説明
    var displayDescription: String {
        description.isEmpty ? "(説明なし)" : description
    }

    /// 最終的に使用されるカテゴリID
    var resolvedCategoryId: UUID? {
        finalCategoryId ?? suggestedCategoryId
    }

    /// ユーザーアクションが必要かどうか
    var needsUserAction: Bool {
        status == .unresolved
    }

    /// 解決済みかどうか（保存可能）
    var isResolved: Bool {
        status == .resolved || status == .duplicate || status == .invalid || status == .transferConfirmed
    }

    /// 振替として最終確定されるべきか（Phase 3-3で使用）
    var shouldTreatAsTransfer: Bool {
        status == .transferConfirmed
    }

    /// 振替候補で口座未設定かどうか
    var isTransferPendingAccountSetup: Bool {
        status == .transferCandidate && isUserMarkedAsTransfer && counterAccountId == nil
    }

    /// 金額表示（符号付き）
    var displayAmountWithSign: String {
        switch amountSign {
        case .plus: return "+¥\(amount.formatted())"
        case .minus: return "-¥\(amount.formatted())"
        case .zero: return "¥0"
        }
    }
}

// MARK: - Description Group

/// descriptionでグループ化したもの（一括カテゴリ適用用）
struct DescriptionGroup: Identifiable {
    let id = UUID()
    let description: String
    let rows: [ImportDraftRow]
    let type: TransactionType

    var displayDescription: String {
        description.isEmpty ? "(説明なし)" : description
    }

    var count: Int { rows.count }

    var totalAmount: Int {
        rows.reduce(0) { $0 + $1.amount }
    }

    var rowIds: Set<UUID> {
        Set(rows.map { $0.id })
    }

    /// キーワード候補を生成（ルール保存用）
    var suggestedKeyword: String {
        var result = description

        // " - " より前を優先
        if let range = result.range(of: " - ") {
            result = String(result[..<range.lowerBound])
        }

        // " / " より前を優先
        if let range = result.range(of: " / ") {
            result = String(result[..<range.lowerBound])
        }

        // 末尾の数字・記号を除去
        result = result.replacingOccurrences(of: #"\s*[\d\-_]+$"#, with: "", options: .regularExpression)

        return result.trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Import Wizard Step

/// ウィザードのステップ
enum ImportWizardStep: Int, CaseIterable {
    case settings = 0      // Step 0: フォーマット・口座選択
    case preview = 1       // Step 1: プレビュー一覧
    case resolve = 2       // Step 2: 未分類解決 & 振替確定
    case summary = 3       // Step 3: サマリー・確定保存

    var title: String {
        switch self {
        case .settings: return "設定"
        case .preview: return "プレビュー"
        case .resolve: return "分類"
        case .summary: return "確認"
        }
    }

    var subtitle: String {
        switch self {
        case .settings: return "形式と口座を選択"
        case .preview: return "インポート内容を確認"
        case .resolve: return "未分類・振替を解決"
        case .summary: return "最終確認と保存"
        }
    }
}

// MARK: - Import Commit Result

/// 確定保存の結果
struct ImportCommitResult {
    let importId: String
    let totalRows: Int
    let addedCount: Int
    let skippedCount: Int
    let duplicateCount: Int
    let addedTransactionIds: [UUID]
    var transferPairCount: Int = 0  // Phase 3-3: 振替ペア数
}

// MARK: - Preview Filter Mode (Phase 3-2)

/// プレビュー画面のフィルタモード
enum PreviewFilterMode: String, CaseIterable {
    case all                // すべて表示
    case unresolvedOnly     // 未分類のみ
    case transferOnly       // 振替候補のみ
    case resolvedOnly       // 解決済みのみ

    var displayName: String {
        switch self {
        case .all: return "すべて"
        case .unresolvedOnly: return "未分類のみ"
        case .transferOnly: return "振替候補のみ"
        case .resolvedOnly: return "解決済みのみ"
        }
    }
}

// MARK: - Resolve Tab Mode (Phase 3-3)

/// Step2の解決モード
enum ResolveTabMode: String, CaseIterable {
    case unresolved     // 未分類
    case transfer       // 振替

    var displayName: String {
        switch self {
        case .unresolved: return "未分類"
        case .transfer: return "振替"
        }
    }
}

// MARK: - Transfer Candidate Detector (Phase 3-2)

/// 振替候補判定ロジック
/// 注意: 全てのキーワードはTextNormalizer.normalize()の出力形式に合わせて定義
/// - 全角カタカナ → 半角カタカナ
/// - 長音記号(ー) → ハイフン(-)
/// - 全角英数字 → 半角英数字
struct TransferCandidateDetector {

    // コンビニ名キーワード（正規化済み形式）
    static let convenienceStoreKeywords: [String] = [
        "ｾﾌﾞﾝ", "7-eleven", "seven", "seven-eleven",      // セブン
        "ﾛ-ｿﾝ", "lawson",                                  // ローソン
        "ﾌｧﾐﾘ-ﾏ-ﾄ", "ﾌｧﾐﾏ", "familymart",                // ファミリーマート
        "ﾐﾆｽﾄｯﾌﾟ", "ministop",                             // ミニストップ
        "ﾃﾞｲﾘ-ﾔﾏｻﾞｷ", "ﾃﾞｲﾘ-", "daily",                  // デイリーヤマザキ
        "ｻﾝｸｽ", "ｻ-ｸﾙk", "circlek",                       // サンクス
        "ﾎﾟﾌﾟﾗ", "poplar",                                 // ポプラ
        "ｾｲｺ-ﾏ-ﾄ", "seicomart",                           // セイコーマート
        "ｺﾝﾋﾞﾆ"                                             // コンビニ
    ]

    // ATM/カード/送金キーワード（正規化済み形式、コンビニと組み合わせで振替候補になる）
    static let atmCardKeywords: [String] = [
        "ｶ-ﾄﾞ", "card",           // カード
        "ｿｳｷﾝ",                    // 送金
        "atm",
        "ﾆｭｳｷﾝ", "ｼｭｯｷﾝ",         // 入金、出金
        "ﾋｷﾀﾞｼ", "ﾋｷﾀﾞｼ",         // 引出、引き出し
        "ｱｽﾞｹｲﾚ",                  // 預入、預け入れ
        "ﾌﾘｺﾐ", "ﾌﾘｶｴ",           // 振込、振替
        "ｷｬｯｼｭ", "cash"           // キャッシュ
    ]

    // 単独で振替候補になるキーワード（正規化済み形式）
    static let transferKeywords: [String] = [
        "ﾁｬ-ｼﾞ", "charge",        // チャージ
        "ﾌﾘｶｴ", "ﾌﾘｺﾐ",           // 振替、振込
        "ｺｳｻﾞｶﾝ", "ｼｷﾝｲﾄﾞｳ",     // 口座間、資金移動
        "ﾆｭｳｷﾝ", "ｼｭｯｷﾝ",         // 入金、出金
        "atm",
        "ﾋｷﾀﾞｼ",                   // 引出、引き出し
        "ｱｽﾞｹｲﾚ"                   // 預入、預け入れ
    ]

    // 銀行間振込キーワード（正規化済み形式）
    static let bankTransferKeywords: [String] = [
        "ﾌﾘｺﾐ",                    // 振込
        "ｿｳｷﾝ",                    // 送金
        "ﾀｺｳ", "ﾀｺｳｻﾞ",           // 他行、他口座
        "ﾕｳﾁｮ", "ﾕｳﾋﾞﾝｷｮｸ",       // ゆうちょ、郵便局
        "ｷﾞﾝｺｳ", "bank"           // 銀行
    ]

    // 振替候補から除外する例外キーワード（正規化済み形式）
    static let excludeKeywords: [String] = [
        "chargespot", "ﾁｬ-ｼﾞｽﾎﾟｯﾄ"  // チャージスポット
    ]

    // ATMカード取引パターン（正規化済み形式、「カード」で始まる場合はATM入出金）
    static let atmCardPrefixes: [String] = [
        "ｶ-ﾄﾞ"                     // カード（全パターン正規化後は同一）
    ]

    // ATM設置場所キーワード（正規化済み形式 + 漢字、単独で振替候補）
    static let atmLocationKeywords: [String] = [
        "ﾕｳﾋﾞﾝｷｮｸ",                // 郵便局（半角カタカナ）
        "郵便局"                    // 郵便局（漢字）- TextNormalizerでは漢字は変換されない
    ]

    /// 振替候補かどうかを判定
    /// - Parameters:
    ///   - description: 取引の説明（生テキスト）
    ///   - type: 取引タイプ
    ///   - amount: 金額
    /// - Returns: (振替候補かどうか, 理由)
    static func detect(description: String, type: TransactionType, amount: Int) -> (isCandidate: Bool, reason: TransferCandidateReason) {
        // TextNormalizerで正規化（半角カタカナ + ハイフン統一）
        let normalizedDesc = TextNormalizer.normalize(description)

        // 例外キーワードが含まれる場合は振替候補にしない
        if excludeKeywords.contains(where: { normalizedDesc.contains($0) }) {
            return (false, .none)
        }

        // 1. type == .transfer の場合
        if type == .transfer {
            return (true, .transferType)
        }

        // 2. ATMカード取引パターン: 「ｶ-ﾄﾞ」で始まる場合（りそな銀行など）
        // ユーザー要件: 「カード」の記載があれば入金出金分類（セブンだけとは限らない）
        for prefix in atmCardPrefixes {
            if normalizedDesc.hasPrefix(prefix) {
                return (true, .atmCardTransaction)
            }
        }

        // 3. コンビニ + ATM/カード/送金キーワードの組み合わせ
        let hasConvenienceStore = convenienceStoreKeywords.contains { keyword in
            normalizedDesc.contains(keyword)
        }

        if hasConvenienceStore {
            let hasATMCardKeyword = atmCardKeywords.contains { keyword in
                normalizedDesc.contains(keyword)
            }
            if hasATMCardKeyword {
                return (true, .convenienceATM)
            }
        }

        // 4. 単独の振替キーワード
        for keyword in transferKeywords {
            if normalizedDesc.contains(keyword) {
                if keyword == "atm" {
                    return (true, .atmKeyword)
                } else if keyword == "ﾁｬ-ｼﾞ" || keyword == "charge" {
                    return (true, .chargeKeyword)
                } else {
                    return (true, .transferKeyword)
                }
            }
        }

        // 5. 銀行間振込
        let hasBankTransfer = bankTransferKeywords.contains { keyword in
            normalizedDesc.contains(keyword)
        }
        if hasBankTransfer && (normalizedDesc.contains("ﾌﾘｺﾐ") || normalizedDesc.contains("ｿｳｷﾝ")) {
            return (true, .bankTransfer)
        }

        // 6. ATM設置場所キーワード: 郵便局など（単独で振替候補）
        for keyword in atmLocationKeywords {
            if normalizedDesc.contains(keyword) {
                return (true, .atmLocation)
            }
        }

        return (false, .none)
    }

    /// 金額の符号を判定
    static func detectAmountSign(amount: Int, type: TransactionType) -> AmountSign {
        if amount == 0 {
            return .zero
        }
        // typeベースで判定（expenseは出金、incomeは入金）
        switch type {
        case .income:
            return .plus
        case .expense:
            return .minus
        case .transfer:
            // transferの場合はamount自体の符号で判定する仕組みが必要だが、
            // 現状amountは正の値で保持されているため、追加情報が必要
            // Phase 3-3でより詳細に実装
            return .minus
        }
    }

    /// 正規化キーを生成（一括適用用）
    static func generateNormalizedKey(description: String) -> String {
        var key = description
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // 数字を除去
        key = key.replacingOccurrences(of: #"\d+"#, with: "", options: .regularExpression)

        // 連続スペースを単一に
        key = key.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)

        // 記号を除去
        key = key.replacingOccurrences(of: #"[^\p{L}\p{N}\s]"#, with: "", options: .regularExpression)

        return key.trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Import Wizard State

/// ウィザードの状態管理（ObservableObject）
@MainActor
class ImportWizardState: ObservableObject {
    // 設定
    @Published var selectedFormat: CSVImportFormat = .bankGeneric
    @Published var selectedAccountId: UUID?          // 主体口座（CSV元口座）

    // CSVデータ
    @Published var csvText: String = ""
    @Published var fileName: String = ""
    @Published var fileHash: String = ""

    // ドラフト行（メモリのみ - SwiftDataには保存しない）
    @Published var draftRows: [ImportDraftRow] = []

    // 処理状態
    @Published var isProcessing: Bool = false
    @Published var currentStep: ImportWizardStep = .settings
    @Published var errorMessage: String?

    // 結果
    @Published var commitResult: ImportCommitResult?

    // フィルタ（Phase 3-2で拡張）
    // MARK: - Filter State
    @Published var filterMode: PreviewFilterMode = .all
    
    // MARK: - Selection Mode State
    @Published var isSelectionMode: Bool = false
    @Published var selectedTransactionIds: Set<UUID> = []
    
    func toggleSelectionMode() {
        isSelectionMode.toggle()
        if !isSelectionMode {
            selectedTransactionIds.removeAll()
        }
    }
    
    func toggleSelection(for id: UUID) {
        if selectedTransactionIds.contains(id) {
            selectedTransactionIds.remove(id)
        } else {
            selectedTransactionIds.insert(id)
        }
    }
    
    func selectAll() {
        let visibleIds = displayRows.map { $0.id }
        selectedTransactionIds.formUnion(visibleIds)
    }
    
    func deselectAll() {
        selectedTransactionIds.removeAll()
    }
    
    // MARK: - Bulk Actions
    
    func bulkApplyCategory(_ categoryId: UUID?, _ categoryName: String?, saveRule: Bool = false) {
        guard !selectedTransactionIds.isEmpty else { return }
        
        // Update rows that match the selection
        for i in 0..<draftRows.count {
            if selectedTransactionIds.contains(draftRows[i].id) {
                // Update finalCategoryId (User selection overrides everything)
                draftRows[i].finalCategoryId = categoryId
                
                if let _ = categoryId {
                     if draftRows[i].status == .unresolved {
                         draftRows[i].status = .resolved
                     }
                }
            }
        }
        

        
        if saveRule, let catId = categoryId {
            // Group by description and type to save rules correctly
            for i in 0..<draftRows.count {
                if selectedTransactionIds.contains(draftRows[i].id) {
                     let row = draftRows[i]
                     // Avoid duplicates
                     addRule(keyword: row.description, categoryId: catId, type: row.type)
                }
            }
        }
        
        // Exit selection mode after action? Or keep it?
        // Usually better to keep it if user wants to do more, but for "Apply", maybe exit.
        // Let's keep it active for now or clear selection.
        selectedTransactionIds.removeAll()
        isSelectionMode = false
    }
    
    func bulkDelete() {
        guard !selectedTransactionIds.isEmpty else { return }
        
        draftRows.removeAll { selectedTransactionIds.contains($0.id) }
        selectedTransactionIds.removeAll()
    }

    @Published var showUnresolvedOnly: Bool = false  // 互換性維持

    // Phase R1-3: マニュアルマッピング
    @Published var manualMapping: CSVManualMapping?

    // Phase 3-3: 振替一括設定
    @Published var defaultCounterAccountId: UUID?    // デフォルト相手口座

    // Phase 3-3: Step2のタブ
    @Published var resolveTabMode: ResolveTabMode = .unresolved

    // MARK: - AI Classification State
    @Published var isAIClassifying: Bool = false
    @Published var aiClassificationProgress: AIClassificationProgress?
    @Published var aiClassificationError: AIClassificationError?
    @Published var showAIClassificationResult: Bool = false
    @Published var lastAIClassificationResult: AIClassificationResult?

    // MARK: - Computed Properties

    var resolvedCount: Int {
        draftRows.filter { $0.status == .resolved }.count
    }

    var unresolvedCount: Int {
        draftRows.filter { $0.status == .unresolved }.count
    }

    var transferCandidateCount: Int {
        draftRows.filter { $0.status == .transferCandidate }.count
    }

    var transferConfirmedCount: Int {
        draftRows.filter { $0.status == .transferConfirmed }.count
    }

    var userMarkedTransferCount: Int {
        draftRows.filter { $0.status == .transferCandidate && $0.isUserMarkedAsTransfer }.count
    }

    /// 振替候補で口座未設定の数
    var transferPendingAccountCount: Int {
        draftRows.filter { $0.isTransferPendingAccountSetup }.count
    }

    var duplicateCount: Int {
        draftRows.filter { $0.status == .duplicate }.count
    }

    var invalidCount: Int {
        draftRows.filter { $0.status == .invalid }.count
    }

    var validRowCount: Int {
        draftRows.filter { $0.status == .resolved || $0.status == .unresolved || $0.status == .transferCandidate || $0.status == .transferConfirmed }.count
    }

    var willAddCount: Int {
        draftRows.filter { $0.status == .resolved }.count + transferConfirmedCount
    }

    /// 保存可能かどうか（Phase 3-3: 未確定が残ると保存不可）
    var canProceedToCommit: Bool {
        // 1. 未分類が0件
        // 2. 振替候補でマークされているが口座未設定の行が0件
        // 3. 保存する行が1件以上
        let hasUnresolved = unresolvedCount > 0
        let hasTransferPending = transferPendingAccountCount > 0
        let hasItemsToSave = willAddCount > 0

        return !hasUnresolved && !hasTransferPending && hasItemsToSave
    }

    /// 保存不可の理由
    var commitBlockReason: String? {
        if unresolvedCount > 0 {
            return "未分類が\(unresolvedCount)件あります"
        }
        if transferPendingAccountCount > 0 {
            return "振替の相手口座が未設定の行が\(transferPendingAccountCount)件あります"
        }
        if willAddCount == 0 {
            return "保存する取引がありません"
        }
        return nil
    }

    /// フィルタ適用後の表示行
    var displayRows: [ImportDraftRow] {
        switch filterMode {
        case .all:
            return draftRows
        case .unresolvedOnly:
            return draftRows.filter { $0.status == .unresolved }
        case .transferOnly:
            return draftRows.filter { $0.status == .transferCandidate || $0.status == .transferConfirmed }
        case .resolvedOnly:
            return draftRows.filter { $0.status == .resolved || $0.status == .transferConfirmed }
        }
    }

    /// descriptionでグループ化した未分類行
    var unresolvedGroups: [DescriptionGroup] {
        let unresolved = draftRows.filter { $0.status == .unresolved }
        var grouped: [String: [ImportDraftRow]] = [:]

        for row in unresolved {
            let key = row.description.trimmingCharacters(in: .whitespacesAndNewlines)
            grouped[key, default: []].append(row)
        }

        return grouped.map { key, rows in
            DescriptionGroup(
                description: key,
                rows: rows,
                type: rows.first?.type ?? .expense
            )
        }
        .sorted { $0.rows.count > $1.rows.count }
    }

    /// 振替候補（未確定）の行
    var transferCandidateRows: [ImportDraftRow] {
        draftRows.filter { $0.status == .transferCandidate }
    }

    // MARK: - Actions


    /// CSVをパースしてドラフト行を生成
    func parseCSVToDraftRows(dataStore: DataStore) {
        guard !csvText.isEmpty else { return }

        isProcessing = true
        errorMessage = nil
        draftRows = [] // 以前の結果をクリア

        // CSV正規化
        var text = csvText.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        if !text.contains(",") && text.contains("\t") { text = text.replacingOccurrences(of: "\t", with: ",") }

        let rows = CSVParser.parse(text)
        guard !rows.isEmpty else {
            errorMessage = "CSVが空です"
            isProcessing = false
            return
        }

        // フォーマット自動検出
        var actualFormat = selectedFormat
        if selectedFormat == .cardGeneric && AmazonCardDetector.detect(rows: rows) {
            actualFormat = .amazonCard
        } else if (selectedFormat == .bankGeneric || selectedFormat == .cardGeneric) && PayPayDetector.detect(rows: rows) {
            actualFormat = .payPay
        } else if (selectedFormat == .bankGeneric || selectedFormat == .cardGeneric) && ResonaDetector.detect(rows: rows) {
            actualFormat = .resonaBank
        }
        selectedFormat = actualFormat

        // ヘッダー検出
        let firstRow = rows[0]
        var hasHeader = looksLikeHeader(firstRow)
        var startIndex = hasHeader ? 1 : 0
        if actualFormat == .amazonCard && AmazonCardDetector.isPersonalInfoRow(firstRow) {
            hasHeader = false
            startIndex = 1
        }
        let header = hasHeader ? firstRow : []
        var map = ColumnMap.build(fromHeader: header, format: actualFormat)
        if let manual = manualMapping {
            map.apply(manual)
        }

        // 既存取引のキーセットを作成（重複検出用）
        let existingKeys = Set(dataStore.transactions.map { txKey($0, dataStore: dataStore) })

        // 行をパース
        var parsedRows: [ImportDraftRow] = []

        for i in startIndex..<rows.count {
            let r = rows[i]
            if r.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) { continue }
            if actualFormat == .amazonCard && AmazonCardDetector.isTotalRow(r) { continue }

            let result = buildDraftRow(from: r, format: actualFormat, map: map, rowIndex: i, dataStore: dataStore)

            switch result {
            case .success(var draftRow):
                // 重複チェック
                let key = draftRowKey(draftRow, dataStore: dataStore)
                if existingKeys.contains(key) {
                    draftRow.status = .duplicate
                }
                parsedRows.append(draftRow)

            case .failure(let error):
                // パースエラー行
                let invalidRow = ImportDraftRow(
                    date: Date(),
                    amount: 0,
                    description: String(r.joined(separator: ", ").prefix(50)),
                    memo: "",
                    type: .expense,
                    status: .invalid,
                    originalRow: r,
                    rowIndex: i,
                    parseError: error.message
                )
                parsedRows.append(invalidRow)
            }
        }

        draftRows = parsedRows
        isProcessing = false

        // Phase 3-2: 詳細ログ出力
        logParseResult()
    }

    /// パース結果のログ出力 (Phase 3-2)
    private func logParseResult() {
        print("[ImportWizard] ===== パース完了 =====")
        print("[ImportWizard] 総数: \(draftRows.count)")
        print("[ImportWizard] 解決済み: \(resolvedCount)")
        print("[ImportWizard] 未分類: \(unresolvedCount)")
        print("[ImportWizard] 振替候補: \(transferCandidateCount)")
        print("[ImportWizard] 振替確定: \(transferConfirmedCount)")
        print("[ImportWizard] 重複: \(duplicateCount)")
        print("[ImportWizard] 無効: \(invalidCount)")

        // 振替候補の理由別カウント
        let reasonCounts = Dictionary(grouping: draftRows.filter { $0.status == .transferCandidate || $0.status == .transferConfirmed }) {
            $0.transferCandidateReason
        }.mapValues { $0.count }

        if !reasonCounts.isEmpty {
            print("[ImportWizard] -- 振替候補内訳 --")
            for (reason, count) in reasonCounts.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
                print("[ImportWizard]   \(reason.displayName): \(count)件")
            }
        }

        print("[ImportWizard] ユーザー確定済み振替: \(userMarkedTransferCount)")
        print("[ImportWizard] ====================")
    }

    /// 指定したdescriptionの全行にカテゴリを適用
    func applyCategoryToDescription(_ categoryId: UUID, description: String) {
        for i in draftRows.indices {
            let normalizedDesc = draftRows[i].description.trimmingCharacters(in: .whitespacesAndNewlines)
            if normalizedDesc == description && draftRows[i].status == .unresolved {
                draftRows[i].finalCategoryId = categoryId
                draftRows[i].status = .resolved
            }
        }
    }

    /// 単一行にカテゴリを適用
    func applyCategoryToRow(_ rowId: UUID, categoryId: UUID) {
        if let idx = draftRows.firstIndex(where: { $0.id == rowId }) {
            draftRows[idx].finalCategoryId = categoryId
            draftRows[idx].status = .resolved
        }
    }

    /// 振替として扱うフラグをトグル (Phase 3-2)
    func toggleTransferDecision(rowId: UUID) {
        if let idx = draftRows.firstIndex(where: { $0.id == rowId }) {
            draftRows[idx].isUserMarkedAsTransfer.toggle()
            print("[ImportWizard] Row \(rowId): isUserMarkedAsTransfer = \(draftRows[idx].isUserMarkedAsTransfer)")
        }
    }

    /// 振替候補を通常の取引に変更 (Phase 3-2)
    func markAsNormalTransaction(rowId: UUID, categoryId: UUID) {
        if let idx = draftRows.firstIndex(where: { $0.id == rowId }) {
            draftRows[idx].finalCategoryId = categoryId
            draftRows[idx].status = .resolved
            draftRows[idx].isUserMarkedAsTransfer = false
            draftRows[idx].transferCandidateReason = .none
            draftRows[idx].counterAccountId = nil
        }
    }

    // MARK: - Phase 3-3: 振替確定アクション

    /// 振替として確定（口座設定）
    func confirmTransfer(rowId: UUID, counterAccountId: UUID) {
        if let idx = draftRows.firstIndex(where: { $0.id == rowId }) {
            draftRows[idx].isUserMarkedAsTransfer = true
            draftRows[idx].counterAccountId = counterAccountId
            draftRows[idx].status = .transferConfirmed
            print("[ImportWizard] Row \(rowId): 振替確定 counterAccountId=\(counterAccountId)")
        }
    }

    /// 振替候補を一括で振替確定
    func confirmAllTransferCandidates(counterAccountId: UUID) {
        for i in draftRows.indices {
            if draftRows[i].status == .transferCandidate {
                draftRows[i].isUserMarkedAsTransfer = true
                draftRows[i].counterAccountId = counterAccountId
                draftRows[i].status = .transferConfirmed
            }
        }
        print("[ImportWizard] 振替候補を一括確定: \(transferConfirmedCount)件")
    }

    /// 振替確定を解除（振替候補に戻す）
    func revertTransferConfirmation(rowId: UUID) {
        if let idx = draftRows.firstIndex(where: { $0.id == rowId }) {
            draftRows[idx].status = .transferCandidate
            draftRows[idx].counterAccountId = nil
            print("[ImportWizard] Row \(rowId): 振替確定を解除")
        }
    }

    /// ルールとして保存（Phase 3-3）
    func saveAsRule(keyword: String, categoryId: UUID, type: TransactionType) {
        let rule = ClassificationRule(
            keyword: keyword,
            matchType: .contains,
            targetCategoryId: categoryId,
            transactionType: type,
            isEnabled: true,
            priority: 30  // ユーザー定義は中〜高優先度
        )

        let result = ClassificationRulesStore.shared.addRuleWithCheck(rule)
        if result.success {
            print("[ImportWizard] ルール保存成功: '\(keyword)' -> categoryId=\(categoryId)")

            // 既存のドラフト行を再分類
            reapplyRules()
        } else if let conflicting = result.conflictingRule {
            print("[ImportWizard] ルール競合: 既存ルール '\(conflicting.keyword)' とキーワードが重複")
            // 上書きするかどうかはUIで確認
            ClassificationRulesStore.shared.overwriteRule(existingId: conflicting.id, with: rule)
            reapplyRules()
        }
    }

    /// ルール適用後のドラフト再分類
    private func reapplyRules() {
        // 未分類の行に対してルールを再適用
        // DataStoreへの参照が必要なため、外部から呼び出す形に
    }

    /// 外部からルール再適用を呼び出す
    func reapplyClassificationRules(dataStore: DataStore) {
        for i in draftRows.indices {
            if draftRows[i].status == .unresolved {
                // 自動分類を再試行
                if let suggestedId = ClassificationRulesStore.shared.suggestCategoryId(
                    from: [draftRows[i].description, draftRows[i].memo],
                    type: draftRows[i].type,
                    categories: dataStore.categories(for: draftRows[i].type)
                ) {
                    draftRows[i].suggestedCategoryId = suggestedId
                    draftRows[i].finalCategoryId = suggestedId
                    draftRows[i].status = .resolved
                    print("[ImportWizard] 再分類成功: '\(draftRows[i].description)' -> \(suggestedId)")
                }
            }
        }
    }

    // MARK: - AI Classification

    /// AI分類が実行可能かどうか
    var canPerformAIClassification: Bool {
        // AI分類対象（unresolved && resolvedCategoryId == nil && type != transfer）が1件以上あり、分類中でない
        aiClassificationTargetCount > 0 && !isAIClassifying
    }

    /// AI分類のターゲット件数（未分類かつtransfer以外）
    var aiClassificationTargetCount: Int {
        draftRows.filter { row in
            row.status == .unresolved &&
            row.resolvedCategoryId == nil &&
            row.type != .transfer
        }.count
    }

    /// AI分類を実行
    func performAIClassification(dataStore: DataStore) async {
        guard canPerformAIClassification else { return }

        isAIClassifying = true
        aiClassificationError = nil
        showAIClassificationResult = false

        // 対象のタイプを収集（支出/収入）
        let targetTypes = Set(draftRows.filter { $0.status == .unresolved && $0.type != .transfer }.map { $0.type })

        // 各タイプのカテゴリを階層構造付きで収集
        var allCategories: [(id: UUID, name: String, groupName: String?)] = []
        for type in targetTypes {
            let groupsForType = dataStore.groups(for: type)
            for group in groupsForType {
                let itemsForGroup = dataStore.items(for: group.id)
                for item in itemsForGroup {
                    allCategories.append((id: item.id, name: item.name, groupName: group.name))
                }
            }
        }

        // 分類ヒント（Few-shot samples）を収集
        // 直近の正常に分類された取引からユニークな例を最大20件抽出
        var hints: [(description: String, categoryName: String, groupName: String?)] = []
        let recentTransactions = dataStore.transactions
            .filter { !$0.isDeleted && $0.categoryId != nil && $0.type != .transfer }
            .sorted { $0.date > $1.date }
        
        var seenHintKeys = Set<String>()
        for tx in recentTransactions {
            guard hints.count < 20 else { break }
            let catName = dataStore.categoryName(for: tx.categoryId)
            let groupName = DefaultHierarchicalCategories.findGroupName(for: catName, type: tx.type) // 暫定的にDefaultから引く、本来はDataStoreから引くのが正確
            
            let key = "\(tx.memo)|\(catName)"
            if !seenHintKeys.contains(key) {
                hints.append((description: tx.memo, categoryName: catName, groupName: groupName))
                seenHintKeys.insert(key)
            }
        }

        let service = AIClassificationService.shared

        // service.progressをstate.aiClassificationProgressに反映するための購読
        var cancellable: AnyCancellable?
        cancellable = service.$progress
            .receive(on: DispatchQueue.main)
            .sink { [weak self] progress in
                self?.aiClassificationProgress = progress
            }

        let (result, updates) = await service.classifyDraftRows(
            draftRows: draftRows,
            categories: allCategories,
            hints: hints
        )

        // 購読を解除
        cancellable?.cancel()

        // 更新を適用
        for (rowId, update) in updates {
            if let idx = draftRows.firstIndex(where: { $0.id == rowId }) {
                draftRows[idx].finalCategoryId = update.categoryId
                draftRows[idx].aiReason = update.reason
                draftRows[idx].status = .resolved
            }
        }

        // 結果を保存
        lastAIClassificationResult = result
        aiClassificationError = result.error
        showAIClassificationResult = true
        isAIClassifying = false

        // 進捗をクリア
        aiClassificationProgress = nil

        print("[ImportWizard] AI分類完了: 処理=\(result.totalProcessed), 確定=\(result.totalConfirmed), スキップ=\(result.totalSkipped), エラー=\(result.totalErrors)")
    }

    /// 分類ルールを追加
    func addRule(keyword: String, categoryId: UUID, type: TransactionType) {
        let rule = ClassificationRule(
            keyword: keyword,
            matchType: .contains,
            targetCategoryId: categoryId,
            transactionType: type,
            isEnabled: true,
            priority: 100 // ユーザー作成ルールは優先度高め
        )
        ClassificationRulesStore.shared.addRule(rule)
    }

    /// リセット
    func reset() {
        csvText = ""
        fileName = ""
        fileHash = ""
        draftRows = []
        currentStep = .settings
        commitResult = nil
        errorMessage = nil
        filterMode = .all
        showUnresolvedOnly = false
        defaultCounterAccountId = nil
        resolveTabMode = .unresolved
        isProcessing = false
        lastAIClassificationResult = nil
        aiClassificationError = nil
        showAIClassificationResult = false
        aiClassificationProgress = nil
    }

    // MARK: - Private Helpers

    private func looksLikeHeader(_ row: [String]) -> Bool {
        let joined = row.joined(separator: ",").lowercased()
        let keywords = ["日付", "種類", "金額", "カテゴリ", "メモ", "category", "date"]
        return keywords.contains(where: { joined.contains($0.lowercased()) })
    }

    private func buildDraftRow(from row: [String], format: CSVImportFormat, map: ColumnMap, rowIndex: Int, dataStore: DataStore) -> Result<ImportDraftRow, CSVParseError> {
        var date: Date
        var type: TransactionType
        var amount: Int
        var memo: String
        var description: String

        switch format {
        case .appExport:
            guard row.count >= 3 else { return .failure(CSVParseError("列数が不足しています")) }
            guard let d = DateParser.parse(row[safe: 0] ?? "") else { return .failure(CSVParseError("日付の形式が不正です")) }
            guard let (t, a) = parseAppTypeAmount(typeStr: row[safe: 1] ?? "", amountStr: row[safe: 2] ?? "") else {
                return .failure(CSVParseError("金額または種別が不正です"))
            }
            date = d; type = t; amount = a
            description = row[safe: 3] ?? ""
            memo = row[safe: 4] ?? ""

        case .bankGeneric, .cardGeneric:
            guard let ds = map.pickDate(from: row), let d = DateParser.parse(ds) else {
                return .failure(CSVParseError("日付が見つからないか形式が不正です"))
            }
            guard let (t, a) = map.pickTypeAmount(from: row, format: format) else {
                return .failure(CSVParseError("金額または入出金種別を特定できませんでした"))
            }
            date = d; type = t; amount = a
            description = map.pickMemo(from: row) ?? ""
            memo = ""

        case .amazonCard:
            guard row.count >= 3 else { return .failure(CSVParseError("列数が不足しています")) }
            guard let d = DateParser.parse(row[safe: 0] ?? "") else { return .failure(CSVParseError("日付の形式が不正です")) }
            guard let a = AmountParser.parse(row[safe: 2] ?? ""), a > 0 else { return .failure(CSVParseError("金額が不正です")) }
            date = d; type = .expense; amount = a
            let raw = row[safe: 1] ?? ""
            description = TextNormalizer.normalize(raw)
            if description.uppercased().contains("AMAZON.CO.JP") { description = "Amazonでの購入" }
            memo = ""

        case .resonaBank:
            // レガシー形式のパースを試行
            if row.count > 19,
               let y = row[safe: 14], let m = row[safe: 15], let d = row[safe: 16],
               let dateVal = DateParser.parse("\(y)/\(m)/\(d)"),
               let a = AmountParser.parse(row[safe: 17] ?? ""), a > 0 {

                let typeStr = row[safe: 13]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                // 取引名は漢字「入金」「支払」なのでそのまま比較
                // TextNormalizerは漢字をカタカナに変換しないため、直接漢字で比較する
                type = (typeStr == "入金") ? .income : .expense
                amount = a
                description = TextNormalizer.normalize(row[safe: 19] ?? "")
                memo = ""
                date = dateVal
            } else {
                // フォールバック
                guard let d = map.pickDateValue(from: row) else { return .failure(CSVParseError("日付を特定できませんでした")) }
                date = d

                // pickTypeAmountを使って入出金を総合的に判定
                if let (t, a) = map.pickTypeAmount(from: row, format: format) {
                    type = t
                    amount = a
                } else if let (t, a) = map.pickAmountFromDebitCredit(from: row) {
                    type = t; amount = a
                } else if let a = map.pickAmount(from: row) {
                    amount = a
                    type = map.pickType(from: row) ?? .expense
                } else {
                    return .failure(CSVParseError("金額を特定できませんでした"))
                }

                description = TextNormalizer.normalize(map.pickMemoString(from: row))
                memo = ""
            }

        case .payPay:
            guard row.count > 8 else { return .failure(CSVParseError("列数が不足しています")) }
            guard let d = DateParser.parse(row[safe: 0] ?? "") else { return .failure(CSVParseError("日付不正")) }
            let outStr = row[safe: 1] ?? ""; let inStr = row[safe: 2] ?? ""
            let content = row[safe: 7]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let partner = row[safe: 8]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            var t: TransactionType = .expense; var a = 0

            if let v = AmountParser.parse(outStr), v > 0 {
                t = .expense; a = v
            } else if let v = AmountParser.parse(inStr), v > 0 {
                t = .income; a = v
            } else {
                return .failure(CSVParseError("金額が見つかりません"))
            }
            // チャージ判定（半角/全角対応）
            let normalizedContent = TextNormalizer.normalize(content)
            if normalizedContent == "ﾁｬ-ｼﾞ" || normalizedContent.contains("ﾁｬ-ｼﾞ") {
                t = .transfer
            }

            date = d; type = t; amount = a
            if !partner.isEmpty {
                description = partner
                if !content.isEmpty { description += " (\(content))" }
            } else {
                description = content
            }
            if description.isEmpty { description = "PayPay取引" }
            memo = ""
        }

        // カテゴリ自動分類
        var suggestedCategoryId: UUID? = nil
        var status: DraftRowStatus = .unresolved

        if let suggestedId = ClassificationRulesStore.shared.suggestCategoryId(
            from: [description, memo],
            type: type,
            categories: dataStore.categories(for: type)
        ) {
            suggestedCategoryId = suggestedId
            status = .resolved
        }

        // Phase 3-2: 振替候補検出（強化版）
        let (isTransferCandidate, transferReason) = TransferCandidateDetector.detect(
            description: description,
            type: type,
            amount: amount
        )

        if isTransferCandidate {
            status = .transferCandidate
        }

        // 金額符号の判定
        let amountSign = TransferCandidateDetector.detectAmountSign(amount: amount, type: type)

        // 正規化キー生成
        let normalizedKey = TransferCandidateDetector.generateNormalizedKey(description: description)

        var draftRow = ImportDraftRow(
            date: date,
            amount: amount,
            description: description,
            memo: memo,
            type: type,
            suggestedCategoryId: suggestedCategoryId,
            finalCategoryId: suggestedCategoryId, // 自動分類が成功した場合はfinalも設定
            status: status,
            originalRow: row,
            rowIndex: rowIndex,
            isUserMarkedAsTransfer: false,  // デフォルトOFF（誤判定防止）
            transferCandidateReason: transferReason,
            amountSign: amountSign,
            normalizedKey: normalizedKey
        )

        // ATM取引（カード〜、郵便局〜）の場合、現金口座を自動設定
        if transferReason == .atmCardTransaction || transferReason == .atmLocation {
            if let cashAccount = AccountStore.shared.cashAccount() {
                draftRow.counterAccountId = cashAccount.id
                draftRow.isUserMarkedAsTransfer = true
                draftRow.status = .transferConfirmed  // 振替確定状態に
            }
        }

        return .success(draftRow)
    }

    private func parseAppTypeAmount(typeStr: String, amountStr: String) -> (TransactionType, Int)? {
        guard let raw = AmountParser.parse(amountStr) else { return nil }
        let t = typeStr.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.contains("収入") || t.lowercased().contains("income") { return (.income, abs(raw)) }
        if t.contains("支出") || t.lowercased().contains("expense") { return (.expense, abs(raw)) }
        return (raw < 0 ? .expense : .income, abs(raw))
    }

    private func txKey(_ t: Transaction, dataStore: DataStore) -> String {
        let catName = dataStore.categoryName(for: t.categoryId)
        return fingerprintKey(date: t.date, type: t.type, amount: t.amount, categoryName: catName, memo: t.memo)
    }

    private func draftRowKey(_ row: ImportDraftRow, dataStore: DataStore) -> String {
        let catName: String
        if let catId = row.resolvedCategoryId {
            catName = dataStore.categoryName(for: catId)
        } else {
            catName = "その他"
        }
        return fingerprintKey(date: row.date, type: row.type, amount: row.amount, categoryName: catName, memo: row.description)
    }

    private func fingerprintKey(date: Date, type: TransactionType, amount: Int, categoryName: String, memo: String) -> String {
        let cal = Calendar(identifier: .gregorian)
        let day = cal.startOfDay(for: date)
        let catStr = TextNormalizer.normalize(categoryName)
        let memoStr = TextNormalizer.normalize(memo)
        return "\(day.timeIntervalSince1970)|\(type.rawValue)|\(amount)|\(catStr)|\(memoStr)"
    }
}

// MARK: - Array Safe Subscript Extension

fileprivate extension Array where Element == String {
    subscript(safe index: Int) -> String? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
