# AI分類 実装前提調査（収支管理/収支管理/ 実コードベース）

調査日: 2026-01-25
調査対象: `収支管理/収支管理/` 配下のSwiftファイル（アプリ本体コードのみ）

---

## 1) categoryId移行状況（結論）

### 判定: **移行済み**

Transactionモデルは `categoryId: UUID?` で統一されており、表示・集計・インポートすべてがcategoryIdベースで動作している。

### 根拠

#### A) Transactionモデルのカテゴリ保持方式

| ファイル | 行付近 | 内容 |
|---------|--------|------|
| Transaction.swift | 37 | `var categoryId: UUID?` - 新仕様のカテゴリID |
| Transaction.swift | 39-41 | `var originalCategoryName: String?` - 「旧仕様のカテゴリ画像（移行用・未分類用）」コメントあり |
| SwiftDataModels.swift | 19-20 | TransactionModelも同様に `categoryId: UUID?` と `originalCategoryName: String?` を保持 |

**結論**: `categoryId` が主フィールドであり、`originalCategoryName` は移行用・フォールバック専用。

#### B) 表示/集計/編集でのcategoryId使用

| ファイル | 行付近 | 処理 | 根拠 |
|---------|--------|------|------|
| CalendarView.swift | 426 | 表示 | `dataStore.category(for: transaction.categoryId)` でID解決 |
| GraphView.swift | 39-43 | 集計 | `if let catId = tx.categoryId { categoryTotals[catId, default: 0] += tx.amount }` |
| GraphView.swift | 78-92 | 集計 | `// 3. 未分類 (categoryId == nil)` コメント付きでnilを未分類として集計 |
| InputView.swift | 32, 493 | 入力 | `@State private var categoryId: UUID? = nil` / `categoryId: categoryId` で保存 |
| DataStore.swift | 125-132 | 名前解決 | `func category(for id: UUID?)` / `func categoryName(for id: UUID?)` |

#### C) マイグレーション処理の存在

| ファイル | 行付近 | 処理内容 |
|---------|--------|----------|
| DataStore.swift | 41 | `performCategoryIdMigration()` - 起動時に実行 |
| DataStore.swift | 54-68 | `migrateTransactionCategoryIds()` - `categoryId == nil && originalCategoryName != nil` の取引をID解決 |
| DataStore.swift | 72-85 | `migrateRuleCategoryIds()` - 分類ルールのID移行 |
| DataStore.swift | 88-102 | `migrateFixedCostCategoryIds()` - 固定費テンプレートのID移行 |
| DataStore.swift | 105-120 | `migrateBudgetCategoryIds()` - 予算のID移行 |

**移行ロジック**: `categoryId == nil` かつ `originalCategoryName` がある場合、名前からカテゴリIDを解決して `categoryId` に設定。

---

## 2) 未分類の保持方法（結論）

### データ表現: **categoryId == nil**

予約IDや予約文字列は存在しない。`categoryId` がnilの取引が「未分類」として扱われる。

### 根拠

#### A) 未分類の判定ロジック

| ファイル | 行付近 | 条件式 | 用途 |
|---------|--------|--------|------|
| DataStore.swift | 131 | `guard let id = id else { return "未分類" }` | カテゴリ名表示 |
| DataStore.swift | 703-705 | `if filterByUncategorized { if tx.categoryId != nil { return false } }` | 検索フィルタ |
| DataStore.swift | 740-745 | `func getUnclassifiedTransactions(...)` / `return tx.categoryId == nil` | 未分類取引抽出 |
| GraphView.swift | 36-43 | `if let catId = tx.categoryId { ... } else { uncategorizedTotal += tx.amount }` | グラフ集計 |
| GraphView.swift | 78 | `// 3. 未分類 (categoryId == nil)` | コメントで明示 |

#### B) CSVインポートでの未分類生成

| ファイル | 行付近 | 内容 |
|---------|--------|------|
| ImportDraftTypes.swift | 24 | `case unresolved // 未分類（要ユーザーアクション）` - ドラフト行のステータス |
| ImportDraftTypes.swift | 133-134 | `var suggestedCategoryId: UUID?` / `var finalCategoryId: UUID?` - どちらもnil可 |
| ImportDraftTypes.swift | 156-158 | `var resolvedCategoryId: UUID? { finalCategoryId ?? suggestedCategoryId }` - nilなら未分類 |
| ImportDraftTypes.swift | 567 | `draftRows.filter { $0.status == .unresolved }` - unresolvedはカテゴリ未設定の行 |

**インポートフロー**: CSVパース → 自動分類ルール適用 → マッチしなければ `status = .unresolved` かつ `finalCategoryId = nil` → ユーザーが手動設定するか、nil（未分類）のまま保存。

#### C) デフォルトカテゴリグループの「未分類」

| ファイル | 行付近 | 内容 |
|---------|--------|------|
| HierarchicalCategory.swift | 144-146 | `("未分類", [("その他", "#9E9E9E")])` - 支出の「未分類」グループに「その他」カテゴリ |
| HierarchicalCategory.swift | 166-168 | `("未分類", [("その他", "#607D8B")])` - 収入の「未分類」グループに「その他」カテゴリ |

**注意**: これはカテゴリグループの名前であり、「その他」カテゴリ自体には通常のcategoryIdが割り当てられる。`categoryId == nil` と「その他」カテゴリは別物。

---

## 3) 未分類件数の想定（結論）

### コード上の上限: **なし**

CSVパース処理に行数制限は存在せず、ファイルの行数に応じて未分類件数は無制限に増加しうる。

### 根拠

#### A) CSVインポートのパース処理

| ファイル | 行付近 | 内容 |
|---------|--------|------|
| ImportDraftTypes.swift | 649-684 | `for i in startIndex..<rows.count` - 全行を制限なしでパース |
| ImportDraftTypes.swift | 684 | `draftRows = parsedRows` - 配列に全件格納 |

**確認結果**: `rows.count` に対するチェックやページング処理は存在しない。

#### B) 未分類の集計

| ファイル | 行付近 | 内容 |
|---------|--------|------|
| ImportDraftTypes.swift | 493-495 | `var unresolvedCount: Int { draftRows.filter { $0.status == .unresolved }.count }` |
| ImportDraftTypes.swift | 575-593 | `var unresolvedGroups: [DescriptionGroup]` - descriptionでグルーピングして一括適用可能 |

#### C) 現実的なケースの想定

- 銀行/カードの月次明細: 数十〜数百件程度
- PayPay等のQR決済: 100〜500件/月程度（利用頻度による）
- 年間一括インポート: 数千件の可能性あり

### AI分類の推奨バッチサイズ

| 項目 | 値 | 根拠 |
|------|-----|------|
| カテゴリ数（支出） | 約50個 | HierarchicalCategory.swift:93-147 |
| カテゴリ数（収入） | 約12個 | HierarchicalCategory.swift:151-169 |
| 1リクエストあたり取引件数 | **25件推奨** | LLMのコンテキスト効率・レスポンス時間・リトライ容易性 |
| 100件超の場合 | **25件×4バッチ** | 並列またはシーケンシャル実行 |

**理由**:
1. 1取引あたり送信フィールド: date, amount, description(memo), type（最低4フィールド）
2. カテゴリリスト: 約60カテゴリ × 名前（＋ID）
3. レスポンス: 25件 × categoryId
4. 失敗時のリトライ: 25件なら再送コストが低い
5. UI待機時間: 25件なら数秒〜10秒程度で完了想定

---

## 4) 根拠一覧（表）

| 項目 | ファイル | 型/関数 | 行付近 | 何が分かったか |
|------|---------|---------|--------|----------------|
| Transactionのカテゴリフィールド | Transaction.swift | struct Transaction | 37 | `categoryId: UUID?` が主フィールド |
| 旧カテゴリ名フィールド | Transaction.swift | struct Transaction | 41 | `originalCategoryName: String?` は移行・バックアップ用 |
| カテゴリID解決 | DataStore.swift | `category(for:)` | 125-127 | IDからCategoryを取得 |
| カテゴリ名解決 | DataStore.swift | `categoryName(for:)` | 130-132 | IDがnilなら"未分類"を返す |
| 未分類フィルタ | DataStore.swift | `searchTransactions(...)` | 703-705 | `categoryId != nil { return false }` で未分類判定 |
| 未分類取引抽出 | DataStore.swift | `getUnclassifiedTransactions(...)` | 740-745 | `categoryId == nil` を抽出 |
| グラフ未分類集計 | GraphView.swift | `GraphData.build(...)` | 36-43, 78-92 | `categoryId == nil` を uncategorizedTotal に加算 |
| マイグレーション | DataStore.swift | `migrateTransactionCategoryIds()` | 54-68 | 起動時にID未解決のデータを変換 |
| CSVパース処理 | ImportDraftTypes.swift | `parseCSVToDraftRows(...)` | 649-684 | 行数制限なし |
| ドラフト行ステータス | ImportDraftTypes.swift | `DraftRowStatus` | 22-28 | `.unresolved` が未分類状態 |
| 未分類件数計算 | ImportDraftTypes.swift | `unresolvedCount` | 493-495 | filter+countで動的計算 |
| デフォルトカテゴリ | HierarchicalCategory.swift | `DefaultHierarchicalCategories` | 93-168 | 支出約50・収入約12カテゴリ |

---

## 5) ブロッカー/リスク（あれば）

### 現時点で確認されたブロッカー: **なし**

categoryId方式への移行は完了しており、AI分類実装を妨げる構造的問題は見当たらない。

### 軽微なリスク・考慮点

| リスク | 詳細 | 対応案 |
|--------|------|--------|
| 未分類件数の上限なし | 大量インポート時にAI分類のコスト/時間が増大 | バッチサイズ制限（25件）+ 進捗表示で対応 |
| originalCategoryNameの残存 | マイグレーション未実行のデータが残る可能性 | AI分類時は `categoryId ?? originalCategoryName` でフォールバック |
| 振替(type == .transfer)の扱い | 振替はカテゴリ不要（categoryId == nil が正常） | AI分類対象から `type != .transfer` で除外 |

---

## 完了報告

### 結論（3行）

1. **categoryId移行: 完了** - Transactionは `categoryId: UUID?` で統一、マイグレーション処理も実装済み
2. **未分類の表現: categoryId == nil** - 予約ID/文字列は存在せず、nilが未分類を表す
3. **未分類件数上限: なし** - CSVの行数依存。AI分類は25件/バッチを推奨
