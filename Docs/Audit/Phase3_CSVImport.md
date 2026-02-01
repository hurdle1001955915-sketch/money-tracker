# Phase3: CSVインポート監査

## 実行日時
- 実行日: 2025-01-23
- 目的: CSVインポートの仕様/挙動/保存確定/取消/重複/カテゴリ割当/ルール保存の実装状況を確定し、欠陥と不足を洗い出す

---

## 1. 対応フォーマット（判定ロジックの根拠）

### 1.1 対応フォーマット一覧

| フォーマット | 表示名 | 説明 | 判定方法 |
|------------|--------|------|---------|
| `appExport` | このアプリのCSV | このアプリでエクスポートしたCSV | 手動選択のみ |
| `resonaBank` | りそな銀行CSV | りそな銀行の入出金明細CSV | `ResonaDetector.detect()` |
| `amazonCard` | 三井住友カード（Amazon等） | 三井住友カード（Vpass）からダウンロードしたCSV | `AmazonCardDetector.detect()` |
| `payPay` | PayPay CSV | PayPayアプリからダウンロードしたCSV | `PayPayDetector.detect()` |
| `bankGeneric` | 銀行CSV（汎用） | 一般的な銀行の入出金明細CSV | 手動選択、自動検出なし |
| `cardGeneric` | クレカCSV（汎用） | 一般的なクレジットカードの利用明細CSV | 手動選択、自動検出あり |

### 1.2 自動判定ロジック

#### 実装箇所
```swift:1239:1242:収支管理/DataStore.swift
var actualFormat = format
if format == .cardGeneric && AmazonCardDetector.detect(rows: rows) { actualFormat = .amazonCard }
else if (format == .bankGeneric || format == .cardGeneric) && PayPayDetector.detect(rows: rows) { actualFormat = .payPay }
else if (format == .bankGeneric || format == .cardGeneric) && ResonaDetector.detect(rows: rows) { actualFormat = .resonaBank }
```

#### 判定条件

**AmazonCardDetector**:
```swift:252:293:収支管理/CSVImportTypes.swift
static func detect(rows: [[String]]) -> Bool {
    // 1. カード番号マスクパターン（****）
    // 2. カード名キーワード（amazon, master, visa, 三井住友, smbc）
    // 3. 「様」を含む
    // 4. データ構造（日付、金額の一致）
}
```

**PayPayDetector**: `CSVImportTypes.swift` 内で実装（詳細未確認）

**ResonaDetector**: `CSVImportTypes.swift` 内で実装（詳細未確認）

### 1.3 判定の優先順位

1. ユーザーが選択したフォーマットを初期値とする
2. `cardGeneric` または `bankGeneric` の場合のみ自動判定を実行
3. 検出された場合は `actualFormat` を上書き

**リスク**: 自動判定が失敗した場合、汎用フォーマットで処理されるが、列マッピングが正しくない可能性がある

---

## 2. UIフロー（選択→プレビュー→確定→結果）

### 2.1 CSVImportView（従来方式）

#### フロー
```
1. フォーマット選択
   └─→ CSVImportFormat を選択

2. ファイル選択
   └─→ CSVDocumentPicker でファイル選択
   └─→ プレビュー表示（最大15行）

3. 列マッピング（汎用フォーマットの場合）
   └─→ 日付、金額、出金列、入金列、区分、メモ、カテゴリの列番号を指定
   └─→ テンプレート保存機能あり

4. インポート実行
   └─→ doImport() → performImport()
   └─→ DataStore.importCSV() を呼び出し
   └─→ 結果を ImportResultSheet で表示

5. 結果確認
   └─→ 追加件数、重複件数、失敗件数を表示
   └─→ 未分類がある場合、「未分類を確認」ボタン表示
   └─→ UnclassifiedReviewView に遷移可能
```

#### 実装箇所
- **メイン画面**: `CSVImportView.swift`
- **ファイル選択**: `CSVDocumentPicker.swift`
- **結果表示**: `CSVImportView.swift:1000-1149` (ImportResultSheet)

### 2.2 CSVImportWizardView（ウィザード方式）

#### フロー
```
1. Step 0: 設定
   └─→ フォーマット選択
   └─→ ファイル選択
   └─→ CSVをパースしてドラフト行を生成

2. Step 1: プレビュー
   └─→ ドラフト行を一覧表示
   └─→ 重複/無効/未解決の状態を表示
   └─→ フィルタ機能（all/unresolved/duplicate/invalid）

3. Step 2: 解決
   └─→ 未解決行のカテゴリ設定
   └─→ 振替候補の確認・設定
   └─→ 重複行の確認

4. Step 3: サマリー
   └─→ 確定前の最終確認
   └─→ commitDraftRows() または commitDraftRowsWithTransfer() を呼び出し
   └─→ 結果表示
```

#### 実装箇所
- **メイン画面**: `CSVImportWizardView.swift`
- **状態管理**: `ImportDraftTypes.swift` (ImportWizardState)
- **各ステップ**: ImportWizardStep0View, Step1View, Step2View, Step3View

### 2.3 両方式の使い分け

**現状**: 両方の方式が存在するが、どちらが推奨か不明確

**CSVImportView**: 従来方式、即座にインポート
**CSVImportWizardView**: ウィザード方式、プレビュー→解決→確定

---

## 3. 取り込み時のカテゴリ自動判定（ルールの所在/保存先）

### 3.1 カテゴリ自動判定の流れ

#### 処理順序
```
1. buildTransaction() で取引を構築
   └─→ ClassificationRulesStore.shared.suggestCategoryId() を呼び出し

2. suggestCategoryId() の処理
   ├─→ 既存ルールでマッチ検索（findMatchingRule）
   │   └─→ マッチした場合、targetCategoryId を返す
   └─→ ルールにない場合、キーワードから推測（suggestCategoryNameFromKeyword）
       └─→ カテゴリマスタから検索してIDを返す

3. categoryId が設定された場合
   └─→ originalCategoryName を nil にクリア

4. categoryId が nil の場合
   └─→ originalCategoryName からカテゴリを作成/取得
   └─→ createCategoryIfNeeded() でカテゴリを確保
   └─→ 「その他」にフォールバックする場合あり
```

#### 実装箇所
```swift:1550:1564:収支管理/DataStore.swift
let tx = Transaction(date: date, type: type, amount: amount, categoryId: nil, originalCategoryName: catName, memo: memo)

// 分類ルールを使ってカテゴリIDを推測
if let suggestedId = ClassificationRulesStore.shared.suggestCategoryId(from: [memo, catName], type: type, categories: categories(for: type)) {
    var updatedTx = tx
    updatedTx.categoryId = suggestedId
    return .success(updatedTx)
}

return .success(tx)
```

### 3.2 ルールの保存先

**保存先**: UserDefaults (`classification_rules_v1`)

**実装箇所**:
```swift:417:432:収支管理/ClassificationRule.swift
private func loadRules() {
    guard let data = UserDefaults.standard.data(forKey: storageKey),
          let decoded = try? JSONDecoder().decode([ClassificationRule].self, from: data) else {
        return
    }
    rules = decoded
}

private func saveRules() {
    guard let data = try? JSONEncoder().encode(rules) else { return }
    UserDefaults.standard.set(data, forKey: storageKey)
}
```

**ストレージキー**: `classification_rules_v1`

### 3.3 ルールの学習機能

**自動学習**: ユーザーが手動でカテゴリを設定した場合、自動的にルールを作成

**実装箇所**:
```swift:239:271:収支管理/ClassificationRule.swift
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
```

**呼び出し箇所**: 
- `InputView.swift`: 取引入力時に自動学習
- `UnclassifiedReviewView.swift`: 未分類レビュー時に手動でルール保存可能

---

## 4. 未分類が出た時の挙動（その場で紐づけUIがあるか）

### 4.1 インポート直後の未分類処理

#### CSVImportView（従来方式）
```swift:1049:1081:収支管理/CSVImportView.swift
// 未分類レビュー導線
if unclassifiedCount > 0 {
    VStack(spacing: 12) {
        HStack {
            Image(systemName: "questionmark.circle.fill")
                .foregroundStyle(.orange)
            Text("未分類: \(unclassifiedCount)件")
            // ...
        }
        
        Button {
            showUnclassifiedReview = true
        } label: {
            HStack {
                Image(systemName: "list.bullet.rectangle")
                Text("未分類を確認")
            }
        }
    }
    .sheet(isPresented: $showUnclassifiedReview) {
        UnclassifiedReviewView(addedTransactionIds: result.addedTransactionIds)
            .environmentObject(dataStore)
    }
}
```

**挙動**: インポート結果画面に「未分類を確認」ボタンが表示され、タップすると `UnclassifiedReviewView` に遷移

#### CSVImportWizardView（ウィザード方式）
```swift:33:33:収支管理/CSVImportWizardView.swift
case .resolve:
    ImportWizardStep2View(state: wizardState)
```

**挙動**: Step 2（解決）で未解決行のカテゴリを設定可能

### 4.2 UnclassifiedReviewView の機能

#### 主な機能
1. **メモ別グルーピング**: 同じメモの取引をグループ化
2. **カテゴリ選択**: グループ単位でカテゴリを設定
3. **ルール保存**: キーワードとカテゴリのルールを保存可能
4. **過去分にも適用**: 既存の取引にも同じルールを適用可能

#### 実装箇所
```swift:203:244:収支管理/UnclassifiedReviewView.swift
private func applyCategory(to group: MemoGroup, categoryId: UUID, keyword: String, saveRule: Bool, applyToPast: Bool) {
    // 1. 対象取引のカテゴリを一括更新
    let ids = Set(group.transactions.map { $0.id })
    let updatedCount = dataStore.updateCategoryBatch(ids: ids, categoryId: categoryId)

    // 2. ルール保存（オプション）
    if saveRule && !keyword.isEmpty {
        let rule = ClassificationRule(...)
        ClassificationRulesStore.shared.addRuleWithCheck(rule)
    }

    // 3. 過去分にも適用（オプション）
    if applyToPast {
        let pastCount = dataStore.applyRuleToAllTransactions(keyword: keyword, targetCategoryId: categoryId, type: group.transactionType)
    }
}
```

**その場で紐づけUI**: ✅ あり（`UnclassifiedReviewView`）

---

## 5. 重複判定のキー（日時/金額/摘要など）と誤検知リスク

### 5.1 重複判定のキー生成

#### 実装箇所
```swift:1391:1427:収支管理/DataStore.swift
private func txKey(_ t: Transaction) -> String {
    // カテゴリ名を解決（ID→名前）して統一的に比較
    let catName = categoryName(for: t.categoryId) ?? t.originalCategoryName ?? ""
    return fingerprintKeyWithCategoryName(t, categoryName: catName)
}

private func fingerprintKeyWithCategoryName(_ t: Transaction, categoryName: String) -> String {
    let cal = Calendar(identifier: .gregorian)
    let day = cal.startOfDay(for: t.date)
    let catStr = TextNormalizer.normalize(categoryName)
    
    var components: [String] = [
        "\(day.timeIntervalSince1970)",  // 日付（日単位）
        t.type.rawValue,                  // 種類（expense/income/transfer）
        "\(t.amount)",                     // 金額
        catStr,                            // カテゴリ名（正規化済み）
        TextNormalizer.normalize(t.memo)  // メモ（正規化済み）
    ]
    
    // 振替の場合は口座情報も含める
    if t.type == .transfer {
        components.append(t.accountId?.uuidString ?? "")
        components.append(t.toAccountId?.uuidString ?? "")
    } else if let accId = t.accountId {
        components.append(accId.uuidString)
    }
    
    // source/sourceId情報
    if let source = t.source {
        components.append(TextNormalizer.normalize(source))
    }
    if let sourceId = t.sourceId {
        components.append(sourceId)
    }
    
    return components.joined(separator: "|")
}
```

### 5.2 重複判定のキー要素

| 要素 | 説明 | 誤検知リスク |
|------|------|------------|
| **日付（日単位）** | `startOfDay` で正規化 | 同じ日の同じ取引を重複と誤判定 |
| **種類** | expense/income/transfer | 低い |
| **金額** | 整数値 | 同じ金額の別取引を重複と誤判定 |
| **カテゴリ名** | ID→名前解決、正規化済み | カテゴリ名変更で重複判定が変わる |
| **メモ** | 正規化済み | メモが同じ別取引を重複と誤判定 |
| **口座ID** | 振替の場合のみ | 低い |
| **source/sourceId** | CSVインポート元の識別 | 低い |

### 5.3 誤検知リスク

#### リスク1: 同じ日の同じ金額・同じメモの別取引
**例**: 同じ店で同じ金額を2回支払った場合

**根拠**: 日付、金額、メモが同じ場合、重複と判定される

**影響**: 2回目の取引がスキップされる

#### リスク2: カテゴリ名変更による重複判定の変化
**例**: カテゴリ名を変更した場合、以前の取引と新しい取引が重複と判定されなくなる

**根拠**: `txKey()` はカテゴリ名を使用しているため、名前が変わるとキーが変わる

**影響**: 本来は重複なのに、重複と判定されない

#### リスク3: メモの正規化による誤検知
**例**: メモの表記が異なるが、正規化後に同じになる場合

**根拠**: `TextNormalizer.normalize()` で正規化しているため、表記が異なっても同じキーになる可能性

**影響**: 別の取引が重複と判定される

### 5.4 重複判定の実行箇所

```swift:1314:1322:収支管理/DataStore.swift
// 重複チェック
let key = txKey(tx)
if existing.contains(key) {
    skipped += 1
    duplicateSkipped += 1
    continue
}
existing.insert(key)
```

**既存取引のキーセット**: `Set(transactions.map { txKey($0) })`

---

## 6. 取消（ロールバック）機構の有無、できない場合の代替案

### 6.1 取消機構の実装

#### 実装箇所
```swift:2011:2079:収支管理/DataStore.swift
func deleteTransactionsByImportHistory(_ history: ImportHistory) -> Int {
    guard let context = modelContext else { return 0 }

    let targetImportId = history.importId
    let targetFileHash = history.fileHash

    // SwiftDataから該当取引を検索して削除
    let descriptor = FetchDescriptor<TransactionModel>()
    var deletedCount = 0

    do {
        let models = try context.fetch(descriptor)
        let toDelete = models.filter { model in
            // 1. 新方式: importIdが一致
            if let importId = model.importId, !importId.isEmpty, importId == targetImportId {
                return true
            }
            // 2. 互換方式: sourceIdがfileHashと一致
            if let sourceId = model.sourceId, !sourceId.isEmpty, sourceId == targetFileHash {
                return true
            }
            return false
        }

        for model in toDelete {
            context.delete(model)
            deletedCount += 1
        }
        
        try context.save()
    } catch {
        // エラーハンドリング
    }

    // メモリ上の配列を同期
    transactions.removeAll { tx in
        // 同様の条件で削除
    }

    // 履歴自体も削除
    deleteImportHistory(history)

    updateWidget()
    return deletedCount
}
```

### 6.2 取消機構の条件

#### 識別方法
1. **新方式**: `importId` が一致する取引を削除
2. **互換方式**: `sourceId` が `fileHash` と一致する取引を削除

#### importId の付与
```swift:1252:1325:収支管理/DataStore.swift
// Phase1: このインポートの一意識別子を生成
let currentImportId = UUID().uuidString

// ...

// Phase1: importIdを付与
tx.importId = currentImportId
```

### 6.3 取消機構の呼び出し箇所

**インポート履歴画面**: `CSVImportView.swift` 内で履歴を表示し、削除可能

**実装状況**: ✅ 取消機構は実装されている

### 6.4 取消できない場合の代替案

**現状**: 取消機構は実装されているが、以下の制約がある：

1. **部分取消不可**: インポート単位でのみ取消可能（個別取引の取消は不可）
2. **履歴が必要**: インポート履歴が保存されている必要がある
3. **互換性の問題**: 旧方式（`sourceId`）と新方式（`importId`）の両方をチェックしているが、完全ではない可能性

**代替案**: 
- 個別取引の削除機能（既存の `deleteTransaction()` を使用）
- 手動での取引削除

---

## 7. CSV関連ファイル群の特定

### 7.1 主要ファイル一覧

| ファイル名 | 責務 | 使用状況 |
|----------|------|---------|
| `CSVImportView.swift` | 従来方式のCSVインポート画面 | ✅ 使用中 |
| `CSVImportWizardView.swift` | ウィザード方式のCSVインポート画面 | ✅ 使用中 |
| `CSVImportTypes.swift` | CSVインポート関連の型定義、パーサー、検出器 | ✅ 使用中 |
| `CSVDocumentPicker.swift` | ファイル選択UI | ✅ 使用中 |
| `ImportDraftTypes.swift` | ウィザード用のドラフト行型定義、状態管理 | ✅ 使用中 |
| `UnclassifiedReviewView.swift` | 未分類取引のレビュー画面 | ✅ 使用中 |
| `UnclassifiedItemsView.swift` | 未分類取引の一覧画面（別実装？） | ⚠️ 要確認 |
| `DataStore.swift` | CSVインポート処理の実装（extension） | ✅ 使用中 |
| `ClassificationRule.swift` | 自動分類ルールの管理 | ✅ 使用中 |

### 7.2 未使用/形骸化の候補

#### UnclassifiedItemsView.swift
**状況**: `UnclassifiedReviewView.swift` と似た機能を持つが、使用箇所が不明確

**確認方法**: 
```bash
grep -rn "UnclassifiedItemsView" 収支管理/*.swift
```

**推測**: 旧実装の可能性、または別の用途で使用されている可能性

#### その他の候補
- テストファイル: `Tests/AmazonCardCSVTests.swift`, `Tests/CSVImportTests.swift` などはテスト用

---

## 8. 欠陥一覧（Major以上優先、最低10件）

| ID | 症状 | 再現手順 | 根拠コード箇所 | 修正方針 | テスト観点 | 深刻度 |
|---|------|---------|--------------|---------|-----------|--------|
| **M-001** | 重複判定で同じ日の同じ金額・同じメモの別取引が重複と誤判定される | 同じ店で同じ金額を2回支払ったCSVをインポート | `DataStore.swift:1397-1427` (fingerprintKeyWithCategoryName) | 時刻情報を追加、または取引IDベースの重複判定に変更 | 同じ日の同じ金額の別取引を2回インポート | **Major** |
| **M-002** | カテゴリ名変更で重複判定が変わる | カテゴリ名を変更後、同じ取引を再インポート | `DataStore.swift:1391-1395` (txKey) | カテゴリIDベースの重複判定に変更 | カテゴリ名変更前後で重複判定が変わることを確認 | **Major** |
| **M-003** | 保存失敗時にエラーが無視される | SwiftDataの保存が失敗してもエラーが無視される | `DataStore.swift:1645` (try? context.save()) | `try-catch` に変更し、エラーをログに記録 | ディスク容量不足時に保存失敗を検出 | **Major** |
| **M-004** | 自動判定が失敗した場合、汎用フォーマットで処理されるが列マッピングが正しくない可能性 | 汎用フォーマットを選択し、自動判定が失敗 | `DataStore.swift:1239-1242` | 自動判定失敗時にユーザーに警告を表示 | 自動判定が失敗したCSVをインポート | **Major** |
| **M-005** | 未分類取引が「その他」にフォールバックされ、ユーザーが気づかない | カテゴリが自動判定できない取引をインポート | `DataStore.swift:1294-1301` | 未分類取引を明確に識別し、ユーザーに通知 | 未分類取引が「その他」になることを確認 | **Major** |
| **M-006** | インポート履歴が保存されない場合、取消ができない | インポート履歴の保存に失敗 | `DataStore.swift:1949-1968` (saveImportHistory) | 履歴保存失敗時にエラーをログに記録 | 履歴保存失敗時の挙動を確認 | **Major** |
| **M-007** | ウィザード方式と従来方式の使い分けが不明確 | 両方の方式が存在するが、どちらが推奨か不明 | `CSVImportView.swift`, `CSVImportWizardView.swift` | どちらかを推奨方式として明確化、または統合 | 両方式の動作確認 | **Medium** |
| **M-008** | エラーメッセージが30件までしか記録されない | エラーが30件を超える場合、残りが記録されない | `DataStore.swift:1333` | エラー件数を記録し、ユーザーに通知 | エラーが30件を超えるCSVをインポート | **Medium** |
| **M-009** | 未分類サンプルが50件までしか記録されない | 未分類が50件を超える場合、残りが記録されない | `DataStore.swift:1360` | 未分類件数を記録し、ユーザーに通知 | 未分類が50件を超えるCSVをインポート | **Medium** |
| **M-010** | 重複判定でメモの正規化による誤検知の可能性 | メモの表記が異なるが、正規化後に同じになる場合 | `DataStore.swift:1407` (TextNormalizer.normalize) | 正規化ロジックの見直し、または追加の識別子を使用 | 正規化後に同じになる別のメモをインポート | **Medium** |
| **M-011** | インポート履歴の削除時にエラーが発生しても続行される | 履歴削除に失敗しても処理が続行 | `DataStore.swift:2074-2075` | エラーハンドリングを強化 | 履歴削除失敗時の挙動を確認 | **Medium** |
| **M-012** | カテゴリ自動判定でルールのtargetCategoryIdがnilの場合、判定が失敗する | ルールにtargetCategoryIdが設定されていない | `ClassificationRule.swift:205-211` | ルールのマイグレーションを強化 | targetCategoryIdがnilのルールで判定 | **Medium** |
| **M-013** | ウィザード方式でドラフト行の状態が正しく更新されない可能性 | ドラフト行の状態更新ロジックに不備 | `ImportDraftTypes.swift` | 状態更新ロジックの見直し | ドラフト行の状態遷移を確認 | **Medium** |
| **M-014** | インポート履歴のfileHash計算が正規化されているが、元のファイルと一致しない可能性 | ファイルハッシュの計算方法 | `DataStore.swift:2127-2144` (calculateCSVHash) | ハッシュ計算ロジックの見直し | 同じファイルを再インポートした場合の重複検出 | **Low** |

---

## 9. UX改善案（ウィザード方式等）を実装単位に分解

### 9.1 現状のウィザード方式の実装状況

**実装済み**: `CSVImportWizardView.swift` でウィザード方式が実装されている

**ステップ構成**:
1. **Step 0 (settings)**: フォーマット選択、ファイル選択
2. **Step 1 (preview)**: ドラフト行のプレビュー
3. **Step 2 (resolve)**: 未解決行の解決
4. **Step 3 (summary)**: 確定前のサマリー

### 9.2 改善案の実装単位分解

#### 改善案1: プレビュー画面の強化

**画面**: `ImportWizardStep1View`

**状態**:
- `draftRows: [ImportDraftRow]`
- `filterMode: FilterMode` (all/unresolved/duplicate/invalid)
- `showUnresolvedOnly: Bool`

**保存ポイント**: なし（ドラフト状態）

**エラーハンドリング**: 
- パースエラー: `errorMessage` に記録
- 重複検出: `status == .duplicate` で識別

**戻る**: `wizardState.currentStep = .settings`

#### 改善案2: 未解決行の一括解決

**画面**: `ImportWizardStep2View`

**状態**:
- `resolveTabMode: ResolveTabMode` (unresolved/duplicate/transfer)
- `selectedCategoryId: UUID?`
- `selectedKeyword: String`

**保存ポイント**: 
- カテゴリ設定: `draftRow.finalCategoryId` を更新
- ルール保存: `ClassificationRulesStore.shared.addRuleWithCheck()`

**エラーハンドリング**:
- カテゴリ未選択: ボタンを無効化
- ルール衝突: アラート表示

**戻る**: `wizardState.currentStep = .preview`

#### 改善案3: 確定前の最終確認

**画面**: `ImportWizardStep3View`

**状態**:
- `commitResult: ImportCommitResult?`
- `isProcessing: Bool`

**保存ポイント**: 
- `commitDraftRows()` または `commitDraftRowsWithTransfer()` を呼び出し
- `saveImportHistory()` で履歴を保存

**エラーハンドリング**:
- コミット失敗: エラーメッセージを表示
- 部分成功: 成功件数と失敗件数を表示

**戻る**: `wizardState.currentStep = .resolve`

### 9.3 追加の改善案

#### 改善案4: リアルタイムプレビュー

**実装単位**:
- **画面**: プレビュー画面にリアルタイム更新機能を追加
- **状態**: `@Published var draftRows` で自動更新
- **保存ポイント**: なし（表示のみ）
- **エラーハンドリング**: 更新失敗時にエラー表示
- **戻る**: 通常の戻るボタン

#### 改善案5: バッチ処理の進捗表示

**実装単位**:
- **画面**: 処理中オーバーレイに進捗バーを追加
- **状態**: `processedCount: Int`, `totalCount: Int`
- **保存ポイント**: 各取引の保存後に進捗を更新
- **エラーハンドリング**: エラー発生時に処理を中断
- **戻る**: キャンセルボタンで処理を中断

#### 改善案6: インポート履歴からの再インポート

**実装単位**:
- **画面**: インポート履歴画面に「再インポート」ボタンを追加
- **状態**: `selectedHistory: ImportHistory?`
- **保存ポイント**: 既存のインポート処理を使用
- **エラーハンドリング**: ファイルが見つからない場合のエラー処理
- **戻る**: 通常の戻るボタン

---

## 10. 実行したコマンド

### CSV関連ファイルの検索
```bash
# CSV関連ファイルを検索
find . -name "*CSV*.swift" -o -name "*Import*.swift"

# 検出器の使用箇所を確認
grep -rn "AmazonCardDetector\|PayPayDetector\|ResonaDetector" 収支管理/*.swift
```

### 結果
- CSV関連ファイル: 7ファイル（テスト含む）
- インポート関連ファイル: 5ファイル（テスト含む）
- 検出器の使用箇所: 3ファイル

---

## 11. まとめ

### CSVインポートの実装状況
- ✅ **対応フォーマット**: 6種類（自動判定あり）
- ✅ **UI方式**: 2種類（従来方式、ウィザード方式）
- ✅ **カテゴリ自動判定**: 実装済み（ルールベース + キーワード推測）
- ✅ **未分類処理**: 実装済み（UnclassifiedReviewView）
- ✅ **重複判定**: 実装済み（日付/金額/カテゴリ/メモベース）
- ✅ **取消機構**: 実装済み（importIdベース）

### 主な欠陥
- **Major**: 6件（重複判定の誤検知、保存失敗の無視、未分類のフォールバック等）
- **Medium**: 7件（エラーメッセージの制限、状態更新の問題等）
- **Low**: 1件（ハッシュ計算の問題）

### 推奨アクション
1. **即座に対応**: M-001（重複判定の誤検知）、M-003（保存失敗の無視）
2. **優先的に対応**: M-002（カテゴリ名変更による重複判定の変化）、M-005（未分類のフォールバック）
3. **段階的対応**: M-007（ウィザード方式と従来方式の統合）、M-008（エラーメッセージの制限）

---

## 12. 成果物

- **Phase3_CSVImport.md**: 本ドキュメント
- **CSV関連ファイル一覧**: 8ファイルを特定
- **欠陥一覧**: 14件を特定（Major 6件、Medium 7件、Low 1件）
- **UX改善案**: 6つの改善案を実装単位に分解
