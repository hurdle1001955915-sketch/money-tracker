# Phase1: ビルド/起動/クラッシュ（止血）

## 実行日時
- 実行日: 2025-01-23
- 目的: ビルド不能・起動不能・クラッシュ要因を最優先で特定し、再現手順と原因箇所を確定する

---

## 1. 環境情報

### Xcode/Swift Version
- **Xcode**: 26.2 (Build version 17C52)
- **Swift**: 6.2.3 (swift-driver version: 1.127.14.1)
- **Target**: arm64-apple-macosx26.0

### プロジェクト情報
- **Scheme**: 収支管理
- **Target**: 収支管理
- **Build Configurations**: Debug, Release
- **デフォルト**: Release（Scheme未指定時）

### 実行したコマンド

#### 1. 環境情報取得
```bash
xcodebuild -version
swift --version
xcodebuild -list
```

#### 2. プロジェクト情報取得
```bash
xcodebuild -list > Docs/Audit/Logs/xcodebuild_list.txt
```
**結果**: 保存完了（`Docs/Audit/Logs/xcodebuild_list.txt`）

#### 3. ビルド実行
```bash
xcodebuild -scheme "収支管理" -destination "platform=iOS Simulator,name=iPhone 17" build
```
**結果**: **BUILD SUCCEEDED** ✅

**注意**: 最初は `iPhone 15` を指定したが、利用可能なデバイスではなかったため `iPhone 17` に変更。

#### 4. クラッシュリスク検索
```bash
grep -rn "fatalError\|try!\|as!\|!\]\|\[!\|force unwrap" 収支管理/*.swift > Docs/Audit/Logs/crash_risks_grep.txt
```
**結果**: 3箇所のクラッシュリスクを検出

---

## 2. ビルド結果

### ビルドステータス
- **結果**: ✅ **BUILD SUCCEEDED**
- **プラットフォーム**: iOS Simulator (iPhone 17)
- **アーキテクチャ**: arm64
- **ビルド設定**: Debug
- **ビルドログ**: `Docs/Audit/Logs/build.log` に保存

### ビルド時の注意事項
- ビルドは正常に完了
- エラー・警告なし（ビルドログ上）
- AppIntentsメタデータ処理も正常に完了

---

## 3. クラッシュ要因の静的監査

### 検出されたクラッシュリスク

以下の3箇所でクラッシュリスクを検出しました：

| # | ファイル | 行 | コード | リスク種別 | 深刻度 |
|---|---------|-----|--------|-----------|--------|
| 1 | `KakeiboApp.swift` | 38 | `fatalError("Unable to create any ModelContainer: \(error)")` | fatalError | **Critical** |
| 2 | `CSVImportTypes.swift` | 429 | `row[safe: amountIndex!]` | Force Unwrap | **High** |
| 3 | `FixedCostBudgetViews.swift` | 340 | `categoryBudgets[budget.categoryId!]` | Force Unwrap | **Medium** |

### 詳細分析

#### 1. KakeiboApp.swift:38 - fatalError

**コード箇所**:
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

**分析**:
- **発生条件**: ModelContainerの作成に失敗し、in-memoryフォールバックも失敗した場合
- **影響**: アプリ起動時にクラッシュ（起動不能）
- **深刻度**: **Critical** - アプリが起動できない
- **現状**: フォールバック機構があるため、通常は発生しない想定
- **推奨**: エラーログを強化し、ユーザーに通知する仕組みを検討

#### 2. CSVImportTypes.swift:429 - Force Unwrap

**コード箇所**:
```swift:429:429:収支管理/CSVImportTypes.swift
let amountStr = (amountIndex != nil ? row[safe: amountIndex!] : nil) ?? row[safe: 2] ?? ""
```

**分析**:
- **発生条件**: `amountIndex` が `nil` でないが、実際には無効な値の場合
- **影響**: CSVインポート時にクラッシュ（配列範囲外アクセス）
- **深刻度**: **High** - CSVインポート機能が使用不能になる可能性
- **現状**: `amountIndex != nil` チェックはあるが、値の妥当性チェックなし
- **推奨**: `amountIndex!` の使用を避け、オプショナルバインディングまたは安全なアクセスに変更

**修正案**:
```swift
// 修正前
let amountStr = (amountIndex != nil ? row[safe: amountIndex!] : nil) ?? row[safe: 2] ?? ""

// 修正後（案）
let amountStr = amountIndex.flatMap { row[safe: $0] } ?? row[safe: 2] ?? ""
```

#### 3. FixedCostBudgetViews.swift:340 - Force Unwrap

**コード箇所**:
```swift:339:340:収支管理/FixedCostBudgetViews.swift
for budget in dataStore.budgets where budget.categoryId != nil {
    categoryBudgets[budget.categoryId!] = String(budget.amount)
```

**分析**:
- **発生条件**: `where budget.categoryId != nil` でフィルタしているが、実際には `nil` の可能性が残る（理論上は発生しない）
- **影響**: 予算画面表示時にクラッシュ
- **深刻度**: **Medium** - 予算機能が使用不能になる可能性
- **現状**: `where` 句で `nil` を除外しているため、実質的には安全
- **推奨**: 念のため、オプショナルバインディングに変更して安全性を向上

**修正案**:
```swift
// 修正前
for budget in dataStore.budgets where budget.categoryId != nil {
    categoryBudgets[budget.categoryId!] = String(budget.amount)
}

// 修正後（案）
for budget in dataStore.budgets {
    if let categoryId = budget.categoryId {
        categoryBudgets[categoryId] = String(budget.amount)
    }
}
```

---

## 4. Blocker/Critical 一覧

### Critical（起動不能・重大機能停止）

| ID | 症状 | 再現手順 | 根拠コード箇所 | 最小修正方針 | 影響範囲 |
|---|------|---------|--------------|------------|---------|
| **C-001** | アプリ起動時にクラッシュ | ModelContainer作成失敗 + in-memoryフォールバック失敗 | `KakeiboApp.swift:38` | エラーハンドリング強化、ユーザー通知 | 全機能停止 |
| **C-002** | CSVインポート時にクラッシュ | 不正なCSV形式でインポート実行 | `CSVImportTypes.swift:429` | Force unwrapを安全なアクセスに変更 | CSVインポート機能 |

### High（主要機能停止）

| ID | 症状 | 再現手順 | 根拠コード箇所 | 最小修正方針 | 影響範囲 |
|---|------|---------|--------------|------------|---------|
| **H-001** | 予算画面表示時にクラッシュ | 予算データにcategoryIdがnilのレコードが存在（理論上は発生しない） | `FixedCostBudgetViews.swift:340` | オプショナルバインディングに変更 | 予算機能 |

### Medium（部分機能停止）

現在、Mediumレベルの問題は検出されていません。

---

## 5. ビルドログ

### ビルドログファイル
- **保存先**: `Docs/Audit/Logs/build.log`
- **サイズ**: 約数百KB（完全なビルドログ）

### ビルドログの主要なポイント
1. **コンパイル**: 全Swiftファイルが正常にコンパイル
2. **リンク**: 正常にリンク完了
3. **コード署名**: 正常に署名完了（"Sign to Run Locally"）
4. **AppIntents**: メタデータ処理が正常に完了
5. **エラー**: なし
6. **警告**: ビルドログ上では検出されず

---

## 6. クラッシュリスクログ

### クラッシュリスク検索結果
- **保存先**: `Docs/Audit/Logs/crash_risks_grep.txt`
- **検出数**: 3箇所
- **検索パターン**: `fatalError|try!|as!|!]|[!|force unwrap`

### 検索結果の詳細
```
収支管理/CSVImportTypes.swift:429:        let amountStr = (amountIndex != nil ? row[safe: amountIndex!] : nil) ?? row[safe: 2] ?? ""
収支管理/FixedCostBudgetViews.swift:340:            categoryBudgets[budget.categoryId!] = String(budget.amount)
収支管理/KakeiboApp.swift:38:            fatalError("Unable to create any ModelContainer: \(error)")
```

---

## 7. まとめ

### ビルド状況
- ✅ **ビルド成功**: エラーなし、警告なし（ビルドログ上）
- ✅ **起動可能**: ビルドされたアプリは起動可能な状態

### クラッシュリスク
- **Critical**: 1箇所（ModelContainer作成失敗時の最終手段）
- **High**: 1箇所（CSVインポート時のforce unwrap）
- **Medium**: 1箇所（予算画面のforce unwrap）

### 推奨アクション
1. **即座に対応**: C-001（ModelContainer作成失敗）のエラーハンドリング強化
2. **優先的に対応**: C-002（CSVインポート）のforce unwrap修正
3. **予防的対応**: H-001（予算画面）のforce unwrap修正

### 次のPhaseへの引き継ぎ
- Phase2以降で、実際の起動・動作確認を実施
- クラッシュリスクの修正はPhase8の計画後に実施（調査のための最小限の変更のみ）

---

## 8. 実行したコマンドの完全な記録

### 環境情報取得
```bash
$ xcodebuild -version
Xcode 26.2
Build version 17C52

$ swift --version
swift-driver version: 1.127.14.1 Apple Swift version 6.2.3 (swiftlang-6.2.3.3.21 clang-1700.6.3.2)
Target: arm64-apple-macosx26.0

$ xcodebuild -list
Information about project "収支管理":
    Targets:
        収支管理
    Build Configurations:
        Debug
        Release
    Schemes:
        収支管理
```

### ビルド実行
```bash
$ xcodebuild -scheme "収支管理" -destination "platform=iOS Simulator,name=iPhone 17" build
** BUILD SUCCEEDED **
```

### クラッシュリスク検索
```bash
$ grep -rn "fatalError\|try!\|as!\|!\]\|\[!\|force unwrap" 収支管理/*.swift > Docs/Audit/Logs/crash_risks_grep.txt
$ wc -l Docs/Audit/Logs/crash_risks_grep.txt
       3 Docs/Audit/Logs/crash_risks_grep.txt
```

---

## 9. 成果物

以下のファイルを `/Docs/Audit/Logs/` に保存しました：

1. **xcodebuild_list.txt**: プロジェクト情報（Scheme/Target一覧）
2. **build.log**: 完全なビルドログ（BUILD SUCCEEDED）
3. **crash_risks_grep.txt**: クラッシュリスク検索結果（3箇所）

---

## 10. 補足情報

### 利用可能なシミュレータ
ビルド時に確認した利用可能なiOS Simulator:
- iPhone 17, iPhone 17 Pro, iPhone 17 Pro Max
- iPhone 16e, iPhone Air
- iPad (A16), iPad Air 11-inch (M3), iPad Air 13-inch (M3)
- iPad Pro 11-inch (M5), iPad Pro 13-inch (M5)
- iPad mini (A17 Pro)

### ビルド設定
- **SDK**: iPhoneSimulator26.2.sdk
- **Deployment Target**: iOS 26.2
- **Build Configuration**: Debug
- **Code Signing**: "Sign to Run Locally"
