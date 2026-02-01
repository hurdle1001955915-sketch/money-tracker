# Phase7: 品質監査（性能・保守・セキュリティ・形骸化）

## 実行日時

- 実行日: 2026-01-23
- 目的: 将来の開発を阻害する構造問題と、リスクの高い実装（性能/クラッシュ/セキュリティ）を洗い出し、形骸化コードを特定する。

---

## 1. 性能 (Performance)

### 1.1 計算量と再計算

- **`AccountStore.balance` のO(N)計算**: 取引追加/削除のたびに全取引を走査して残高を再計算している。1万件を超えるとUIブロックの原因になる。
- **グラフ描画の非効率性**: `GraphView` が `DataStore` を丸ごと `@EnvironmentObject` で監視しているため、無関係なプロパティ変更（例えば設定変更など）でもグラフ再描画が走る構造。

### 1.2 メモリ使用とリソース

- **全件オンメモリ**: `DataStore` が全取引・全カテゴリを配列としてメモリに保持している。JSONデコード時も一括読み込みであり、データ量増加に弱い（5万件程度で起動が遅くなる）。

---

## 2. 保守性 (Maintainability)

### 2.1 肥大化クラス・View

- **`DefaultHierarchicalCategories`**: 定義がハードコードされており、変更にはコンパイルが必要。JSONや設定ファイル化すべき。
- **`DataStore.swift`**: 2500行を超え、責務が多すぎる（CRUD、CSV、バックアップ、集計、マイグレーション）。「God Object」化している。

### 2.2 責務の混在

- **`SettingsView`**: ZIPバックアップ機能、CSVエクスポート/インポートなど、設定ではない「ツール・管理機能」が混在しすぎており、Viewが肥大化している。
- **`CSVImportWizardView`**: ステート管理が複雑で、`ImportWizardState` とViewの責務分担が曖昧。

---

## 3. セキュリティ/プライバシー (Security & Privacy)

### 3.1 データの保護

- **ログの平文出力**: `Diagnostics.swift` がコンソールにログを出しており、リリースビルドでも残っていると個人情報（カテゴリ名や金額）が漏れるリスクがある。
- **Face ID Usage**: `AppLockManager.swift` でFace ID使用が実装されているが、`NSFaceIDUsageDescription` が `Info.plist` にない場合、クラッシュする（コード内でチェックロジックはあるが、設定漏れリスクが高い）。

### 3.2 ログとデバッグ情報

- **生体認証バイパス**: `AppLockManager` の認証ロジックにおいて、生体認証不可時のフォールバックが「パスコード認証」のみであり、アプリ独自のPINコードを持たないため、端末パスコードを知っている人がいれば見れてしまう（仕様上の許容範囲か要確認）。

---

## 4. 形骸化/死にコード (Dead Code)

### 抽出一覧（最低15件）

| ID | ファイル/シンボル | 状態 | 根拠（参照数/重複） |
|---|---|---|---|
| DC-001 | `RulesManagementView.swift` | **Zombie** | `ClassificationRulesView.swift` と機能重複。`SettingsView` は後者を使用。インポート画面だけ前者を使っているが、統一すべき。 |
| DC-002 | `AppFeatureFlags.swift` | **Minimal** | `cloudSyncEnabled` のみ。今後フラグが増えなければ過剰な抽象化。 |
| DC-003 | `InputView.swift` | **Wrapper** | `TransactionInputView` の単なるラッパー。直接 `TransactionInputView` を呼べば不要。 |
| DC-004 | `BasicSettingsViews.swift` | **Fragments** | 小さなViewが散らばっている。`SettingsView+Subviews.swift` 等にまとめるか、各機能別ファイルへ移動すべき。 |
| DC-005 | `BackupPayload.expenseCategories` | **Legacy** | v3では `categoryItems` を使うため、v2以前の互換用フィールド。新規データでは空でも良いはず。 |
| DC-006 | `TransactionModel` (SwiftData) | **Waiting** | `DataMigration.swift` で定義されているが、アプリ本体(`KakeiboApp.swift`)ではまだ全面的にJSONを使用しており、実質未使用（将来用）。 |
| DC-007 | `Diagnostics.logSwiftDataCounts` | **Empty** | "Not yet implemented" ログのみ。実装漏れ。 |
| DC-008 | `CSVImportFormat.formatHint` | **Unused** | 一部ロジックで参照されるが、実質 `.appExport` かそれ以外かの判定しかしていない。 |
| DC-009 | `ZipBackupDocument` (Preview) | **No Preview** | Preview用コードがない、または動かない。 |
| DC-010 | `TextNormalizer.normalize` | **Duplicated** | `ClassificationRule.swift` 内にも `normalizeForMatching` があり、ロジックが分散・重複している。 |
| DC-011 | `SettingsView.zipBackupFileName` | **Logic in View** | ファイル名生成ロジックはViewModelやHelperに移すべき。 |
| DC-012 | `WidgetDataProvider.sharedDefaults` | **Hardcoded** | AppGroup ID `"group.com.kakeibo.app"` がハードコードされており、ビルド設定と乖離するリスク。 |
| DC-013 | `MigrationStatus.resetMigrationStatus` | **Debug Only** | デバッグ用コードだがリリースビルドに含まれる。 |
| DC-014 | `ReceiptParser.swift` | **Unknown** | 今回の監査範囲（Settings/Categories/Graph）では使用箇所が見当たらなかった（ツール画面用？）。 |
| DC-015 | `UnclassifiedReviewView` | **Unknown** | `CSVImportView` からの呼び出し経路が不明瞭（Menu内にあるが、機能として`ImportWizard`と重複気味）。 |

---

## 5. 改善提案（優先度・難易度別）

### 5.1 即時対応（Low Risk / High Impact）

- **`RulesManagementView` の削除**: `ClassificationRulesView` に統一し、メンテコストを下げる。
- **ログの無効化**: リリースビルドでは `print` や `Diagnostics` ログを無効化するプリプロセッサマクロを入れる。

### 5.2 中期対応（Refactoring）

- **`DataStore` の分割**: `RuleManager`, `CSVManager`, `BackupManager` などに責務を分散させる。
- **`AccountStore` の計算最適化**: 残高計算を「差分更新」または「DBクエリ」に変更する。

### 5.3 大規模改修（Architecture Change）

- **SwiftData完全移行**: オンメモリJSON管理をやめ、`@Model` を全面採用してメモリ圧迫と起動時間を解決する。
- **モジュール分割**: UIコンポーネント、データ層、ユーティリティを別ターゲットまたはパッケージに切り出す。
