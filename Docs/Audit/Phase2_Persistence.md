# Phase2: 永続化・データ消失リスク監査

## 実行日時
- 実行日: 2025-01-23
- 目的: 再起動でデータが消える/保存されない/保存先が揺れる原因を、実装根拠で確定する

---

## 1. 保存方式の種類と使用箇所

### 1.1 SwiftData（主要な永続化方式）

#### 使用箇所
- **主要データ**: Transaction, CategoryGroup, CategoryItem, Account, Budget, FixedCostTemplate, ImportHistory
- **保存先**: iOS Application Support ディレクトリ（自動管理）
- **コンテナ名**: `KakeiboDatabase`
- **設定**: `SwiftDataModels.swift:621-627` の `DatabaseConfig.modelConfiguration`

#### 実装根拠
```swift:609:634:収支管理/SwiftDataModels.swift
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
```

### 1.2 JSON（レガシー・フォールバック）

#### 使用箇所
- **フォールバック**: SwiftDataが利用できない場合
- **マイグレーション**: JSON → SwiftData の移行用
- **保存先**: Application Support ディレクトリ内のJSONファイル

#### ファイル一覧
```swift:1080:1084:収支管理/DataStore.swift
private var transactionsFileURL: URL { applicationSupportDirectory.appendingPathComponent("transactions.json") }
private var categoryGroupsFileURL: URL { applicationSupportDirectory.appendingPathComponent("category_groups.json") }
private var categoryItemsFileURL: URL { applicationSupportDirectory.appendingPathComponent("category_items.json") }
private var fixedCostsFileURL: URL { applicationSupportDirectory.appendingPathComponent("fixed_costs.json") }
private var budgetsFileURL: URL { applicationSupportDirectory.appendingPathComponent("budgets.json") }
```

#### Application Support ディレクトリの取得
```swift:1075:1079:収支管理/DataStore.swift
private var applicationSupportDirectory: URL {
    let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}
```

**根拠**: `FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!`
- iOS標準のApplication Supportディレクトリを使用
- アプリ削除時に自動削除される
- iCloudバックアップ対象

### 1.3 UserDefaults（設定・ルール）

#### 使用箇所
- **分類ルール**: `ClassificationRulesStore` が管理
- **アプリ設定**: `AppSettings` が管理
- **iCloud同期設定**: `CloudKitSyncManager` が管理

#### 分類ルールの保存
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

### 1.4 CloudKit（iCloud同期）

#### 使用箇所
- **条件**: `AppFeatureFlags.cloudSyncEnabled == true` かつ `syncEnabled == true`
- **Record Type**: `Transaction`
- **データベース**: Private Cloud Database

#### 同期処理
```swift:233:267:収支管理/CloudKitSyncManager.swift
func performFullSync(localTransactions: [Transaction]) async throws -> [Transaction] {
    guard AppFeatureFlags.cloudSyncEnabled else { return localTransactions }
    guard syncEnabled && iCloudAvailable else { return localTransactions }
    
    // ... 同期処理 ...
}
```

---

## 2. ロード/保存の時系列（起動→操作→終了）

### 2.1 アプリ起動時

```
1. KakeiboApp.init
   └─→ modelContainer 初期化（KakeiboApp.swift:22-40）
       ├─→ DatabaseConfig.createContainer() を試行
       ├─→ 失敗時: in-memory フォールバック
       └─→ それも失敗時: fatalError

2. KakeiboApp.body.onAppear
   ├─→ modelContainer.mainContext を取得
   ├─→ DataMigration.migrateIfNeeded(context) （初回のみ）
   │   └─→ JSON → SwiftData マイグレーション
   ├─→ DataStore.shared.setModelContext(context)
   │   └─→ loadAllFromSwiftData()
   │       ├─→ loadTransactionsFromSwiftData()
   │       ├─→ loadCategoriesFromSwiftData()
   │       ├─→ loadFixedCostsFromSwiftData()
   │       └─→ loadBudgetsFromSwiftData()
   ├─→ AccountStore.shared.setModelContext(context)
   │   └─→ loadAccountsFromSwiftData()
   └─→ DataStore.shared.processAllFixedCostsUntilNow()
```

#### ロード処理の実装
```swift:1591:1604:収支管理/DataStore.swift
private func loadAllFromSwiftData() {
    guard let context = modelContext else {
        Diagnostics.shared.log("ModelContext not available, falling back to JSON", category: .error)
        loadAllFromJSON()
        return
    }

    loadTransactionsFromSwiftData(context: context)
    loadCategoriesFromSwiftData(context: context)
    loadFixedCostsFromSwiftData(context: context)
    loadBudgetsFromSwiftData(context: context)

    Diagnostics.shared.log("Loaded from SwiftData: \(transactions.count) transactions, \(categoryItems.count) categories", category: .swiftData)
}
```

### 2.2 データ操作時（取引追加・更新・削除）

```
1. 取引追加: DataStore.addTransaction(tx)
   ├─→ transactions.append(tx) （メモリ更新）
   ├─→ insertTransactionToSwiftData(tx)
   │   ├─→ TransactionModel(from: tx)
   │   ├─→ context.insert(model)
   │   └─→ try? context.save() （即座に保存）
   ├─→ updateWidget()
   └─→ CloudKitSyncManager.uploadTransaction(tx) [条件付き]

2. 取引更新: DataStore.updateTransaction(tx)
   ├─→ transactions[idx] = tx （メモリ更新）
   ├─→ updateTransactionInSwiftData(tx)
   │   ├─→ 既存モデルを検索
   │   ├─→ フィールド更新
   │   └─→ try? context.save() （即座に保存）
   └─→ CloudKitSyncManager.uploadTransaction(tx) [条件付き]

3. 取引削除: DataStore.deleteTransaction(tx)
   ├─→ transactions.removeAll { $0.id == tx.id } （メモリ更新）
   ├─→ deleteTransactionFromSwiftData(tx.id)
   │   ├─→ 既存モデルを検索
   │   ├─→ context.delete(model)
   │   └─→ try? context.save() （即座に保存）
   └─→ CloudKitSyncManager.deleteTransaction(tx) [条件付き]
```

#### 保存処理の実装
```swift:1641:1646:収支管理/DataStore.swift
private func insertTransactionToSwiftData(_ tx: Transaction) {
    guard let context = modelContext else { return }
    let model = TransactionModel(from: tx)
    context.insert(model)
    try? context.save()
}
```

**重要**: すべての保存処理で `try?` を使用しており、エラーが発生しても**無視される**。

### 2.3 アプリ終了時

**現在の実装では明示的な保存処理はない**。
- SwiftDataは自動的に保存される（`context.save()` が呼ばれた時点で永続化）
- ただし、`try?` でエラーが無視されるため、保存失敗に気づかない可能性がある

---

## 3. 保存失敗時のフォールバック

### 3.1 ModelContainer作成失敗

#### フォールバック機構
```swift:22:40:収支管理/KakeiboApp.swift
private var modelContainer: ModelContainer = {
    do {
        return try DatabaseConfig.createContainer()
    } catch {
        // Fallback to in-memory container to avoid app hang/black screen
        print("⚠️ Failed to create persistent ModelContainer. Falling back to in-memory: \(error)")
        let config = ModelConfiguration(
            "KakeiboDatabase_Fallback",
            schema: DatabaseConfig.schema,
            isStoredInMemoryOnly: true,
            allowsSave: true
        )
        if let container = try? ModelContainer(for: DatabaseConfig.schema, configurations: [config]) {
            return container
        }
        // As a last resort, crash with context to surface the real error
        fatalError("Unable to create any ModelContainer: \(error)")
    }
}()
```

**フォールバック条件**:
1. 永続化ModelContainer作成失敗 → in-memory コンテナにフォールバック
2. in-memory コンテナも失敗 → fatalError（アプリクラッシュ）

**リスク**: in-memory の場合、アプリ再起動でデータが消失

### 3.2 ModelContext未設定時のフォールバック

#### JSONフォールバック
```swift:1591:1596:収支管理/DataStore.swift
private func loadAllFromSwiftData() {
    guard let context = modelContext else {
        Diagnostics.shared.log("ModelContext not available, falling back to JSON", category: .error)
        loadAllFromJSON()
        return
    }
    // ...
}
```

**フォールバック条件**: `modelContext == nil` の場合、JSONファイルから読み込む

**リスク**: JSONファイルが存在しない、または古い場合、データが読み込めない

### 3.3 context.save() 失敗時の処理

**現在の実装**: すべて `try?` でエラーを無視

```swift:1645:1645:収支管理/DataStore.swift
try? context.save()
```

**リスク**: 保存失敗に気づかず、データが消失する可能性

---

## 4. パスの根拠

### 4.1 SwiftDataの保存先

**自動管理**: SwiftDataが自動的にApplication Supportディレクトリ内に保存
- **パス**: `~/Library/Application Support/[Bundle ID]/default.store`
- **根拠**: `ModelConfiguration` のデフォルト動作

### 4.2 JSONファイルの保存先

**Application Support ディレクトリ**:
```swift:1075:1079:収支管理/DataStore.swift
private var applicationSupportDirectory: URL {
    let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}
```

**ファイルパス**:
- `transactions.json`
- `category_groups.json`
- `category_items.json`
- `fixed_costs.json`
- `budgets.json`

### 4.3 UserDefaultsの保存先

**システム管理**: iOSが自動的に管理
- **場所**: `~/Library/Preferences/[Bundle ID].plist`
- **根拠**: `UserDefaults.standard` の標準動作

### 4.4 CloudKitの保存先

**iCloud Private Database**: Appleが管理
- **場所**: iCloudサーバー
- **根拠**: `CKContainer.default().privateCloudDatabase`

---

## 5. 永続化関連コード参照点（10箇所以上）

| # | ファイル | 型/関数 | 行 | 目的 | リスク |
|---|---------|---------|-----|------|--------|
| 1 | `KakeiboApp.swift` | `modelContainer` | 22-40 | ModelContainer初期化 | in-memoryフォールバック時、データ消失 |
| 2 | `KakeiboApp.swift` | `setModelContext` | 66-67 | ModelContext注入 | 注入失敗時、JSONフォールバック |
| 3 | `DataStore.swift` | `loadAllFromSwiftData()` | 1591-1604 | SwiftDataから全データロード | ModelContext未設定時、JSONフォールバック |
| 4 | `DataStore.swift` | `insertTransactionToSwiftData()` | 1641-1646 | 取引追加保存 | `try?` でエラー無視、保存失敗に気づかない |
| 5 | `DataStore.swift` | `updateTransactionInSwiftData()` | 1648-1675 | 取引更新保存 | `try?` でエラー無視、保存失敗に気づかない |
| 6 | `DataStore.swift` | `deleteTransactionFromSwiftData()` | 1677-1686 | 取引削除保存 | `try?` でエラー無視、削除失敗に気づかない |
| 7 | `DataStore.swift` | `saveAllTransactionsToSwiftData()` | 1701-1716 | 全取引一括保存 | 内部で `try?` を使用、エラー無視 |
| 8 | `DataStore.swift` | `loadAllFromJSON()` | 1907-1912 | JSONフォールバック読み込み | JSONファイルが存在しない場合、データが空 |
| 9 | `DataStore.swift` | `applicationSupportDirectory` | 1075-1079 | Application Support パス取得 | `first!` で強制unwrap、ディレクトリ取得失敗時クラッシュ |
| 10 | `DataMigration.swift` | `migrateIfNeeded()` | 13-59 | JSON→SwiftDataマイグレーション | マイグレーション失敗時、データが移行されない |
| 11 | `AccountStore.swift` | `loadAccountsFromSwiftData()` | 120-132 | 口座データロード | ModelContext未設定時、UserDefaultsフォールバック |
| 12 | `AccountStore.swift` | `saveAccountToSwiftData()` | 134-160 | 口座データ保存 | `try-catch` でエラーをprintのみ、保存失敗に気づかない |
| 13 | `ClassificationRule.swift` | `saveRules()` | 429-432 | 分類ルール保存 | `guard let` でエンコード失敗時、保存されない |
| 14 | `CloudKitSyncManager.swift` | `performFullSync()` | 233-267 | iCloud同期 | 同期失敗時、エラーをthrowするが呼び出し側で `try?` 使用の可能性 |
| 15 | `DataStore.swift` | `addTransaction()` | 274-284 | 取引追加（CloudKit同期含む） | CloudKit同期が `try?` で無視される |

---

## 6. データ消失シナリオ（5つ以上）

### シナリオ1: ModelContainer作成失敗 → in-memory フォールバック

**発生条件**:
- SwiftDataの永続化コンテナ作成に失敗
- in-memory コンテナにフォールバック

**根拠コード**:
```swift:22:40:収支管理/KakeiboApp.swift
private var modelContainer: ModelContainer = {
    do {
        return try DatabaseConfig.createContainer()
    } catch {
        // Fallback to in-memory container
        let config = ModelConfiguration(
            "KakeiboDatabase_Fallback",
            schema: DatabaseConfig.schema,
            isStoredInMemoryOnly: true,  // ← メモリのみ
            allowsSave: true
        )
        if let container = try? ModelContainer(for: DatabaseConfig.schema, configurations: [config]) {
            return container
        }
        fatalError("Unable to create any ModelContainer: \(error)")
    }
}()
```

**影響**:
- アプリ再起動でデータが消失
- ユーザーは警告を受け取らない（printのみ）

**検出方法**: 現在は検出不可（ログのみ）

---

### シナリオ2: context.save() 失敗 → エラー無視

**発生条件**:
- SwiftDataの保存処理が失敗（ディスク容量不足、権限エラー等）
- `try?` でエラーが無視される

**根拠コード**:
```swift:1641:1646:収支管理/DataStore.swift
private func insertTransactionToSwiftData(_ tx: Transaction) {
    guard let context = modelContext else { return }
    let model = TransactionModel(from: tx)
    context.insert(model)
    try? context.save()  // ← エラーを無視
}
```

**影響**:
- メモリ上にはデータがあるが、永続化されていない
- アプリ再起動でデータが消失
- ユーザーは保存成功と誤認

**検出方法**: 現在は検出不可（エラーが無視される）

**同様の箇所**:
- `updateTransactionInSwiftData()` (1670行)
- `deleteTransactionFromSwiftData()` (1684行)
- `saveCategoryGroupToSwiftData()` (1734行)
- `saveCategoryItemToSwiftData()` (1752行)
- `saveBudgetToSwiftData()` (1836行)
- その他すべての保存処理

---

### シナリオ3: ModelContext未設定 → JSONフォールバック失敗

**発生条件**:
- `modelContext` が `nil` の状態でロードが実行される
- JSONファイルが存在しない、または破損している

**根拠コード**:
```swift:1591:1596:収支管理/DataStore.swift
private func loadAllFromSwiftData() {
    guard let context = modelContext else {
        Diagnostics.shared.log("ModelContext not available, falling back to JSON", category: .error)
        loadAllFromJSON()  // ← JSONフォールバック
        return
    }
    // ...
}
```

```swift:1914:1919:収支管理/DataStore.swift
private func loadTransactionsFromJSON() {
    if let data = try? Data(contentsOf: transactionsFileURL),
       let arr = try? JSONDecoder().decode([Transaction].self, from: data) {
        transactions = arr
    }  // ← ファイルが存在しない場合、空のまま
}
```

**影響**:
- データが読み込まれない（空の状態）
- ユーザーはデータが消失したと誤認

**検出方法**: Diagnosticsログで検出可能

---

### シナリオ4: マイグレーション失敗 → データが移行されない

**発生条件**:
- JSON → SwiftData のマイグレーションが失敗
- エラーがログに記録されるが、処理は続行

**根拠コード**:
```swift:13:59:収支管理/DataMigration.swift
static func migrateIfNeeded(context: ModelContext) {
    // ...
    do {
        // 1. Transactions
        transactionCount = migrateTransactionsFromJSON(context: context)
        // ...
        try context.save()
        status.markJsonToSwiftDataMigrationCompleted(...)
    } catch {
        Diagnostics.shared.log("Migration failed: \(error.localizedDescription)", category: .error)
        // ← エラーをログに記録するが、処理は続行
    }
}
```

**影響**:
- JSONデータがSwiftDataに移行されない
- アプリは空の状態で起動
- ユーザーはデータが消失したと誤認

**検出方法**: Diagnosticsログで検出可能

---

### シナリオ5: Application Support ディレクトリ取得失敗

**発生条件**:
- `FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!` が `nil`
- 強制unwrapでクラッシュ

**根拠コード**:
```swift:1075:1079:収支管理/DataStore.swift
private var applicationSupportDirectory: URL {
    let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}
```

**影響**:
- アプリがクラッシュ
- JSONフォールバックが使用できない

**検出方法**: クラッシュログで検出可能

**補足**: 通常は `first!` が `nil` になることはないが、理論上のリスク

---

### シナリオ6: 分類ルールの保存失敗（エンコード失敗）

**発生条件**:
- 分類ルールのJSONエンコードに失敗
- `guard let` で早期リターン

**根拠コード**:
```swift:429:432:収支管理/ClassificationRule.swift
private func saveRules() {
    guard let data = try? JSONEncoder().encode(rules) else { return }
    UserDefaults.standard.set(data, forKey: storageKey)
}
```

**影響**:
- 分類ルールが保存されない
- アプリ再起動でルールが消失
- ユーザーはルールが保存されたと誤認

**検出方法**: 現在は検出不可（早期リターンのみ）

---

### シナリオ7: CloudKit同期失敗 → ローカルデータと不整合

**発生条件**:
- CloudKit同期が失敗
- ローカルデータは保存されているが、iCloudと不整合

**根拠コード**:
```swift:274:284:収支管理/DataStore.swift
func addTransaction(_ tx: Transaction) {
    transactions.append(tx)
    insertTransactionToSwiftData(tx)  // ← ローカル保存
    updateWidget()
    if AppFeatureFlags.cloudSyncEnabled {
        Task {
            try? await CloudKitSyncManager.shared.uploadTransaction(tx)  // ← エラー無視
        }
    }
}
```

**影響**:
- ローカルデータは保存されている
- iCloudと同期されていない
- 他のデバイスでデータが表示されない

**検出方法**: 現在は検出不可（`try?` でエラー無視）

---

## 7. まとめ

### 保存方式の優先順位
1. **SwiftData**（主要）: すべての主要データ
2. **JSON**（フォールバック）: SwiftDataが利用できない場合
3. **UserDefaults**（設定）: 分類ルール、アプリ設定
4. **CloudKit**（同期）: オプション、マルチデバイス同期

### 主なリスク要因
1. **`try?` によるエラー無視**: 保存失敗に気づかない
2. **in-memory フォールバック**: 再起動でデータ消失
3. **JSONフォールバック**: ファイルが存在しない場合、データが空
4. **マイグレーション失敗**: データが移行されない
5. **CloudKit同期失敗**: ローカルとiCloudの不整合

### 推奨アクション
1. **保存エラーの検出**: `try?` を `try-catch` に変更し、エラーをログに記録
2. **in-memory 検出**: in-memory コンテナ使用時にユーザーに警告
3. **保存確認**: 保存成功/失敗をユーザーに通知
4. **データ整合性チェック**: 起動時にデータ整合性を確認

---

## 8. 実行したコマンド

### コード検索
```bash
# context.save() の使用箇所を検索
grep -rn "context\.save()" 収支管理/*.swift

# try? の使用箇所を確認
grep -rn "try\?" 収支管理/DataStore.swift | head -20
```

### 調査結果
- `context.save()` は約15箇所で使用
- すべて `try?` でエラーを無視
- エラーハンドリングが不十分

---

## 9. 成果物

- **Phase2_Persistence.md**: 本ドキュメント
- **永続化関連コード参照点**: 15箇所を特定
- **データ消失シナリオ**: 7つを特定

---

## 10. 補足: 調査用ログ追加の検討

現在、保存失敗を検出する仕組みが不足しています。Phase8の計画後、以下のログ追加を検討：

1. **保存エラーログ**: `try?` を `try-catch` に変更し、エラーをDiagnosticsに記録
2. **in-memory 検出ログ**: in-memory コンテナ使用時に警告ログを出力
3. **保存成功ログ**: 保存成功時にログを出力（デバッグ用）

**注意**: 現時点では「調査のための最小限」の変更のみ実施。挙動を変える修正はPhase8の計画後。
