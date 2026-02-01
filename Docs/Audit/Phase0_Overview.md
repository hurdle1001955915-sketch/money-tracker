# Phase0: プロジェクト全体スキャン（地図作り）

## 実行日時
- 実行日: 2025-01-23
- 目的: プロジェクト全体の構造・責務・データフロー・保存方式を確定し、後続調査の参照点を作る

## 実行したコマンド

### 1. ディレクトリ作成
```bash
mkdir -p Docs/Audit/Logs
```

### 2. Swiftファイル一覧の生成
```bash
find . -name "*.swift" | sort > Docs/Audit/Logs/swift_files.txt
```
**結果**: 61ファイル（テスト5ファイル + アプリ56ファイル）

### 3. 永続化関連キーワードの検索
```bash
grep -rn "ModelContainer|SwiftData|FileManager|Application Support|CloudKit|CKContainer|JSONEncoder|JSONDecoder" 収支管理/*.swift > Docs/Audit/Logs/persistence_grep.txt
```
**結果**: 4.6KB（約100行以上）

### 4. 機能関連キーワードの検索
```bash
grep -rn "DataStore|Transaction|Category|Rule|Import|CSV|Receipt|Graph|Calendar" 収支管理/*.swift > Docs/Audit/Logs/feature_grep.txt
```
**結果**: 9.3KB（約200行以上）

---

## 1. ディレクトリ構造

### 主要フォルダ
```
収支管理/
├── 収支管理/              # メインアプリケーションコード
│   ├── SwiftDataModels.swift      # SwiftData永続化モデル
│   ├── DataStore.swift            # データ管理の中核
│   ├── AccountStore.swift         # 口座管理
│   ├── Transaction.swift          # 取引モデル
│   ├── Category.swift             # カテゴリモデル（旧フラット）
│   ├── HierarchicalCategory.swift # 階層カテゴリ（新仕様）
│   ├── ClassificationRule.swift   # 自動分類ルール
│   ├── Budget.swift               # 予算モデル
│   ├── FixedCost.swift            # 固定費テンプレート
│   ├── KakeiboApp.swift           # アプリエントリーポイント
│   ├── ContentView.swift          # メイン画面
│   ├── CloudKitSyncManager.swift  # iCloud同期
│   └── [その他55ファイル]
├── Tests/                  # ユニットテスト
│   ├── AmazonCardCSVTests.swift
│   ├── AmountParserTests.swift
│   ├── CSVImportTests.swift
│   ├── CSVParserTests.swift
│   └── DateParserTests.swift
└── Docs/Audit/            # 監査用ドキュメント（本Phaseで作成）
    └── Logs/              # 自動棚卸しログ
```

---

## 2. 主要Swiftファイル一覧（責務）

### アプリケーションコア
| ファイル名 | 責務 | 行数（概算） |
|----------|------|------------|
| `KakeiboApp.swift` | アプリエントリーポイント、ModelContainer初期化、環境オブジェクト注入 | 78行 |
| `ContentView.swift` | メイン画面（TabView）、画面遷移管理 | 68行 |
| `DataStore.swift` | データ管理の中核（CRUD、集計、CSVインポート、永続化） | 2512行 |
| `AccountStore.swift` | 口座管理（CRUD、残高計算） | 227行 |

### データモデル
| ファイル名 | 責務 | 行数（概算） |
|----------|------|------------|
| `SwiftDataModels.swift` | SwiftData永続化モデル（@Modelクラス群） | 635行 |
| `Transaction.swift` | 取引データ構造、振替ヘルパー、重複判定 | 427行 |
| `Category.swift` | カテゴリデータ構造（旧フラット形式） | 106行 |
| `HierarchicalCategory.swift` | 階層カテゴリ（CategoryGroup/CategoryItem） | 213行 |
| `ClassificationRule.swift` | 自動分類ルール、キーワードマッチング | 657行 |
| `Budget.swift` | 予算データ構造 | 66行 |
| `FixedCost.swift` | 固定費テンプレートデータ構造 | 95行 |

### 永続化・同期
| ファイル名 | 責務 | 行数（概算） |
|----------|------|------------|
| `CloudKitSyncManager.swift` | iCloud同期（CloudKit連携、マージ処理） | 452行 |

### 画面・UI
| ファイル名 | 責務 |
|----------|------|
| `InputView.swift` | 取引入力画面 |
| `CalendarView.swift` | カレンダー表示 |
| `GraphView.swift` | グラフ表示 |
| `AccountsView.swift` | 口座一覧・管理画面 |
| `SettingsView.swift` | 設定画面 |
| `CSVImportView.swift` | CSVインポート画面 |
| `CSVImportWizardView.swift` | CSVインポートウィザード |

---

## 3. 主要コンポーネントの関係

### アーキテクチャ概要
```
┌─────────────────────────────────────────────────────────┐
│                    KakeiboApp                           │
│  - ModelContainer初期化                                 │
│  - EnvironmentObject注入                                │
└────────────┬────────────────────────────────────────────┘
             │
             ├─→ DataStore (shared)
             │   ├─→ ModelContext (SwiftData)
             │   ├─→ transactions: [Transaction]
             │   ├─→ categoryGroups: [CategoryGroup]
             │   ├─→ categoryItems: [CategoryItem]
             │   ├─→ budgets: [Budget]
             │   └─→ fixedCostTemplates: [FixedCostTemplate]
             │
             ├─→ AccountStore (shared)
             │   ├─→ ModelContext (SwiftData)
             │   └─→ accounts: [Account]
             │
             ├─→ ClassificationRulesStore (shared)
             │   └─→ rules: [ClassificationRule] (UserDefaults)
             │
             └─→ AppSettings (shared)
                 └─→ アプリ設定 (UserDefaults)
```

### データフロー（永続化層）
```
┌─────────────────────────────────────────────────────────┐
│  SwiftData (ModelContainer)                             │
│  - TransactionModel                                      │
│  - CategoryGroupModel                                    │
│  - CategoryItemModel                                     │
│  - AccountModel                                          │
│  - BudgetModel                                           │
│  - FixedCostTemplateModel                                │
│  - ImportHistoryModel                                    │
└────────────┬────────────────────────────────────────────┘
             │
             ├─→ DataStore.loadAllFromSwiftData()
             │   └─→ メモリキャッシュ（@Published）
             │
             └─→ DataStore.saveAllToSwiftData()
                 └─→ 永続化
```

### 画面層とデータ層の関係
```
ContentView (TabView)
├─→ TransactionInputView
│   └─→ DataStore.addTransaction()
│
├─→ CalendarView
│   └─→ DataStore.transactionsForDate()
│
├─→ GraphView
│   └─→ DataStore.transactionsForMonth()
│
├─→ AssetDashboardView
│   ├─→ AccountStore.accounts
│   └─→ AccountStore.balance()
│
└─→ SettingsView
    ├─→ CSVImportView
    │   └─→ DataStore.importCSV()
    └─→ ClassificationRulesView
        └─→ ClassificationRulesStore
```

---

## 4. データモデル一覧と保存先

### 主要データモデル

| モデル | 構造体/クラス | 保存先 | 備考 |
|--------|--------------|--------|------|
| **取引** | `Transaction` (struct) | SwiftData (`TransactionModel`) | メインエンティティ、IDベースカテゴリ対応 |
| **カテゴリ（階層）** | `CategoryGroup` (struct) | SwiftData (`CategoryGroupModel`) | 大分類 |
| | `CategoryItem` (struct) | SwiftData (`CategoryItemModel`) | 中分類（旧Categoryと互換） |
| **カテゴリ（旧）** | `Category` (struct) | 互換性維持のみ | フラット形式、段階的廃止予定 |
| **口座** | `Account` (struct) | SwiftData (`AccountModel`) | 振替・残高計算用 |
| **予算** | `Budget` (struct) | SwiftData (`BudgetModel`) | 月次予算、カテゴリID対応 |
| **固定費** | `FixedCostTemplate` (struct) | SwiftData (`FixedCostTemplateModel`) | 定期取引テンプレート |
| **分類ルール** | `ClassificationRule` (struct) | UserDefaults (`classification_rules_v1`) | 自動分類用、カテゴリID対応 |
| **インポート履歴** | `ImportHistory` (struct) | SwiftData (`ImportHistoryModel`) | CSVインポート追跡 |

### 保存方式の詳細

#### SwiftData（主要データ）
- **場所**: iOS Application Support ディレクトリ（自動管理）
- **モデル**: `DatabaseConfig.schema` で定義
- **コンテナ名**: `KakeiboDatabase`
- **モデル一覧**:
  - `TransactionModel`
  - `CategoryGroupModel`
  - `CategoryItemModel`
  - `AccountModel`
  - `BudgetModel`
  - `FixedCostTemplateModel`
  - `ImportHistoryModel`

#### UserDefaults（設定・ルール）
- **分類ルール**: `classification_rules_v1` (JSON)
- **アプリ設定**: `AppSettings` が管理
- **iCloud同期設定**: `icloud_sync_enabled`, `icloud_last_sync_date`

#### JSON（レガシー・フォールバック）
- **場所**: Application Support ディレクトリ
- **ファイル**:
  - `transactions.json` (レガシー、マイグレーション用)
  - `category_groups.json` (レガシー)
  - `category_items.json` (レガシー)
  - `expense_categories.json` (旧形式、マイグレーション用)
  - `income_categories.json` (旧形式、マイグレーション用)
  - `fixed_costs.json` (レガシー)
  - `budgets.json` (レガシー)

#### CloudKit（iCloud同期）
- **条件**: `AppFeatureFlags.cloudSyncEnabled == true` かつ `syncEnabled == true`
- **Record Type**: `Transaction`
- **データベース**: Private Cloud Database
- **同期方式**: 手動同期（`performFullSync`）または個別アップロード

---

## 5. データフロー（時系列）

### アプリ起動時
```
1. KakeiboApp.init
   └─→ ModelContainer作成（DatabaseConfig.createContainer）
       └─→ 失敗時は in-memory フォールバック

2. KakeiboApp.body.onAppear
   ├─→ DataStore.setModelContext(context)
   │   ├─→ loadAllFromSwiftData()
   │   │   ├─→ loadTransactionsFromSwiftData()
   │   │   ├─→ loadCategoriesFromSwiftData()
   │   │   ├─→ loadFixedCostsFromSwiftData()
   │   │   └─→ loadBudgetsFromSwiftData()
   │   ├─→ ensureDefaultCategoriesIfNeeded()
   │   └─→ performCategoryIdMigration()
   │       ├─→ migrateTransactionCategoryIds()
   │       ├─→ migrateRuleCategoryIds()
   │       ├─→ migrateFixedCostCategoryIds()
   │       └─→ migrateBudgetCategoryIds()
   │
   ├─→ AccountStore.setModelContext(context)
   │   ├─→ loadAccountsFromSwiftData()
   │   └─→ ensureDefaultAccountsIfNeeded()
   │
   ├─→ DataMigration.migrateIfNeeded(context)
   │   └─→ JSON → SwiftData マイグレーション（初回のみ）
   │
   └─→ DataStore.processAllFixedCostsUntilNow()
       └─→ 過去12ヶ月分の固定費を自動生成
```

### 取引入力時
```
1. TransactionInputView → DataStore.addTransaction(tx)
   ├─→ transactions.append(tx)
   ├─→ insertTransactionToSwiftData(tx)
   │   └─→ TransactionModel(from: tx) → context.insert() → context.save()
   ├─→ updateWidget()
   └─→ CloudKitSyncManager.uploadTransaction(tx) [条件付き]
```

### CSVインポート時
```
1. CSVImportView → DataStore.importCSV(csvText, format)
   ├─→ CSVParser.parse(csvText)
   ├─→ buildTransaction(from: row, format, map)
   │   └─→ ClassificationRulesStore.suggestCategoryId()
   │       └─→ キーワードマッチングでカテゴリID推測
   ├─→ 重複チェック（txKey()使用）
   ├─→ importId付与（Phase1）
   ├─→ transactions.append(contentsOf: toAppend)
   ├─→ insertTransactionToSwiftData() [一括]
   └─→ saveImportHistory()
```

### 集計・表示時
```
1. CalendarView → DataStore.transactionsForDate(date)
   └─→ transactions.filter { Calendar.current.isDate(...) }

2. GraphView → DataStore.transactionsForMonth(monthDate)
   └─→ transactions.filter { year/month一致 }

3. AssetDashboardView → AccountStore.balance(accountId, transactions)
   └─→ initialBalance + 取引の加算/減算
```

---

## 6. Single Source of Truth の特定

### 結論
**Single Source of Truth は SwiftData (ModelContainer) である。**

### 根拠

#### 1. アプリ起動時のロード順序
- `KakeiboApp.swift:66-67`: `DataStore.shared.setModelContext(context)` でSwiftDataからロード
- `DataStore.swift:1591-1604`: `loadAllFromSwiftData()` がSwiftDataを優先
- フォールバック: SwiftDataが失敗した場合のみJSONを読み込む（`loadAllFromJSON()`）

#### 2. 保存時の優先順位
- `DataStore.swift:1641-1646`: `insertTransactionToSwiftData()` が常に呼ばれる
- `DataStore.swift:1701-1716`: `saveAllTransactionsToSwiftData()` でSwiftDataに保存
- JSON保存はレガシーコード（`saveTransactions()`）で、現在は使用されていない

#### 3. データモデルの設計
- `SwiftDataModels.swift:609-634`: `DatabaseConfig.schema` でSwiftDataモデルを定義
- すべての主要エンティティが `@Model` クラスとして定義されている

#### 4. マイグレーション戦略
- `DataMigration.swift`: JSON → SwiftData の一方向マイグレーション
- 旧JSONファイルはバックアップとして残るが、読み込みは初回のみ

### 例外・補助的な保存先

#### UserDefaults
- **分類ルール**: `ClassificationRulesStore` が管理（`classification_rules_v1`）
  - 理由: 設定データとして扱われ、SwiftDataとは別管理
- **アプリ設定**: `AppSettings` が管理
  - 理由: ユーザー設定、永続化データではない

#### CloudKit
- **同期用**: SwiftDataのコピーをiCloudに保存
- **条件**: Feature Flag有効時のみ
- **役割**: マルチデバイス同期、バックアップ

---

## 7. 主要な設計パターン・アーキテクチャ

### Singleton パターン
- `DataStore.shared`
- `AccountStore.shared`
- `ClassificationRulesStore.shared`
- `AppSettings.shared`
- `AppLockManager.shared`
- `CloudKitSyncManager.shared`

### Repository パターン（DataStore）
- データアクセスの抽象化
- SwiftData操作を内部に隠蔽
- メモリキャッシュ（@Published）と永続化層の分離

### MVVM パターン（SwiftUI）
- View: SwiftUI Views
- ViewModel: `@ObservableObject` クラス（DataStore等）
- Model: SwiftData Models / Structs

### マイグレーション戦略
- **段階的移行**: JSON → SwiftData
- **後方互換性**: `originalCategoryName` フィールドで旧データを保持
- **IDベース移行**: カテゴリ名 → カテゴリID への移行を自動実行

---

## 8. 主要な機能モジュール

### CSVインポート
- **対応フォーマット**: 
  - `appExport` (自アプリエクスポート)
  - `bankGeneric` (汎用銀行CSV)
  - `cardGeneric` (汎用カードCSV)
  - `amazonCard` (Amazonカード専用)
  - `resonaBank` (りそな銀行専用)
  - `payPay` (PayPay専用)
- **処理フロー**: パース → 重複チェック → カテゴリ推測 → 保存
- **追跡**: `importId` でインポート単位を識別

### 自動分類
- **ルールエンジン**: `ClassificationRulesStore`
- **マッチング方式**: contains/prefix/suffix/exact
- **優先度**: priority フィールドで制御
- **学習機能**: ユーザーの手動分類を学習してルール追加

### 固定費自動生成
- **テンプレート**: `FixedCostTemplate`
- **実行タイミング**: アプリ起動時（`processAllFixedCostsUntilNow`）
- **処理範囲**: 過去12ヶ月分
- **重複防止**: `lastProcessedMonth` で管理

### 振替機能
- **ペアリング**: `transferId` で2件の取引を紐付け
- **方向**: `accountId` (出金元) / `toAccountId` (入金先)
- **集計**: 振替は集計対象外（`TransactionType.countableTypes`）

---

## 9. 技術スタック

### フレームワーク
- **SwiftUI**: UI構築
- **SwiftData**: 永続化（iOS 17+）
- **CloudKit**: iCloud同期（オプション）
- **Combine**: リアクティブプログラミング

### 依存関係
- 外部ライブラリなし（標準ライブラリのみ）

---

## 10. 既知の課題・技術的負債

### カテゴリID移行
- **現状**: 段階的移行中（`originalCategoryName` と `categoryId` の併用）
- **課題**: 重複判定で名前とIDの両方を考慮する必要がある

### 重複判定ロジック
- **現状**: `txKey()` でカテゴリ名を解決して比較
- **課題**: ID解決前後のデータでキーが変わる可能性

### CloudKit同期
- **現状**: Feature Flagで無効化可能
- **課題**: 完全同期の実装が簡易版（競合解決が基本的）

### レガシーコード
- **JSON保存**: コード内に残存しているが使用されていない
- **旧カテゴリ形式**: `Category` (フラット) から `CategoryGroup/CategoryItem` (階層) への移行中

---

## 11. 次のPhaseへの参照点

### Phase1以降で調査すべき項目
1. **データ整合性**: SwiftDataとメモリキャッシュの同期状況
2. **パフォーマンス**: 大量データ時のロード・保存速度
3. **エラーハンドリング**: SwiftData操作のエラー処理
4. **マイグレーション**: JSON → SwiftData の移行完了状況
5. **重複判定**: カテゴリID移行による影響

---

## 12. 自動棚卸しログ

以下のログファイルを `/Docs/Audit/Logs/` に保存:

1. `swift_files.txt`: 全Swiftファイル一覧（61ファイル）
2. `persistence_grep.txt`: 永続化関連キーワードの検索結果（4.6KB）
3. `feature_grep.txt`: 機能関連キーワードの検索結果（9.3KB）

詳細は各ログファイルを参照。

---

## まとめ

- **永続化**: SwiftDataがSingle Source of Truth
- **データフロー**: SwiftData → DataStore（メモリキャッシュ）→ View
- **主要責務**: DataStoreがデータ管理の中核
- **移行状況**: JSON → SwiftData、カテゴリ名 → カテゴリID の段階的移行中
- **同期**: CloudKit（オプション）、UserDefaults（設定・ルール）
