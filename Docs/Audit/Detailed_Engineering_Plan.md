# 全体修正詳細計画書 (Detailed Engineering Plan)

## 1. 概要と基本方針

本計画書は、Phase0〜Phase7の監査結果に基づき、**堅牢性(Robustness)**、**整合性(Consistency)**、**保守性(Maintainability)** を回復させるための技術的詳細計画である。

**基本方針**:

1. **Stop the Bleeding (止血)**: クラッシュとデータ消失リスクは最優先（P0）で修正する。
2. **Single Source of Truth (SSOT)**: 重複する機能（UI/ロジック）は一つに統合し、メンテナンスコストを下げる。
3. **Defensive Programming (防御的プログラミング)**: 外部入力（CSV/ユーザー入力）やシステム状態（DB初期化）に対し、常に失敗を想定したハンドリングを行う。

---

## 2. フェーズ別詳細実装計画

### Phase R0: 止血・安定化 (Stability)

**目標**: クラッシュ率 0%、データ消失リスクの最小化。

#### R0-1: DB初期化クラッシュの防止

- **対象**: `KakeiboApp.swift`
- **問題**: `modelContainer` 初期化時の `try!` および `fatalError`。
- **実装方針**:
  - `do-catch` ブロックで初期化をラップする。
  - 失敗時は「インメモリコンテナ」へのフォールバックを試みる（少なくともアプリは起動させる）。
  - 起動後にユーザーへ「データ読み込みエラー」を警告するフラグを State で保持する。

#### R0-2: データ永続化の保証

- **対象**: `DataStore.swift`, `SettingsView.swift`
- **問題**: オンメモリ管理であり、明示的な保存タイミング以外でクラッシュするとデータが消える。
- **実装方針**:
  - **短期策**: `updateTransaction`, `addTransaction` などの更新メソッド内で、必ず `save()` を呼び出すように変更（パフォーマンスは犠牲にするが安全性優先）。
  - **長期策（Phase R4移行）**: SwiftDataの標準機能（AutoSave）への完全移行。

#### R0-3: 本番環境ログの隠蔽

- **対象**: `Diagnostics.swift`, `SceneDelegate` (もしあれば)
- **問題**: 個人情報ログ出力。
- **実装方針**:
  - `log()` メソッド全体を `#if DEBUG` で囲むか、リリースビルドでは空実装になるようにコンパイラディレクティブを追加する。

---

### Phase R1: CSVインポート機能の統合 (Unification)

**目標**: CSVインポート動線を「ウィザード形式」に一本化し、レガシーコードを排除する。

#### R1-1: エントリポイントの修正

- **対象**: `SettingsView.swift`
- **実装方針**:
  - 「データをインポート」ボタンのアクションを `CSVImportWizardView` 起動のみにする。
  - `menu` で分岐している「履歴管理」などは、ウィザード内のメニューか、設定画面の別項目へ移動。

#### R1-2: レガシーViewの削除・統合

- **対象**: `CSVImportView.swift`, `UnclassifiedItemsView.swift`, `UnclassifiedReviewView.swift`
- **実装方針**:
  - `CSVImportWizardView` が使用しているサブビュー（`ImportWizardStepXView`）に機能が網羅されているか確認。
  - 特に `UnclassifiedReviewView`（インポート後の仕分け）は、ウィザードの完了画面 (`ImportWizardStep3View`) から遷移できるように導線を確保する。
  - 旧 `CSVImportView.swift` をプロジェクトから削除（Delete）。

#### R1-3: 手動マッピングの救済フロー

- **対象**: `CSVImportWizardView`, `CSVFormatDetector`
- **実装方針**:
  - 自動判定 (`CSVFormatDetector`) が `unknown` を返した場合、またはユーザーがフォーマットを強制指定した場合に、列マッピング（Step 2相当）を手動修正できるUIステップを追加/復元する。

---

### Phase R2: 機能不全の改修 (Functional Fixes)

**目標**: ユーザーが期待する当たり前の動作（検索編集、正規化）を実現する。

#### R2-1: 検索機能の実用化

- **対象**: `TransactionSearchView.swift`
- **問題**: 検索結果が Read-only に近い状態。
- **実装方針**:
  - リストタップ時に `TransactionInputView` をシート表示する（`editingTransaction` を渡す）。
  - 編集保存後、検索結果リストをリロード（再検索）するトリガーを実装。

#### R2-2: 自動分類ルールの正規化適用

- **対象**: `DataStore.migrateTransactionCategoryIds`, `ClassificationRulesStore.swift`
- **問題**: "Ａｍａｚｏｎ" と "Amazon" が別扱いされる。
- **実装方針**:
  - `TextNormalizer.swift` (新規作成または既存活用) に `normalize(String) -> String` を実装（NFKC正規化、全角英数→半角、小文字化）。
  - ルールマッチング時とマイグレーション時の比較双方でこの正規化を通す。

---

### Phase R3: パフォーマンス最適化 (Performance)

**目標**: 取引データ5万件でもUIがスタックしない（60fps維持）。

#### R3-1: 残高計算の差分更新化

- **対象**: `AccountStore.swift`
- **問題**: 取引1件追加ごとの全件再計算 `O(N)`。
- **実装方針**:
  - 口座ごとの「現在残高」をキャッシュプロパティとして持つ。
  - 取引追加時は `balance += amount`、編集時は `balance += (new - old)` のように `O(1)` で更新するロジックへ変更。
  - 定期的な整合性チェック（リ計算）はバックグラウンドで行う。

#### R3-2: グラフ描画の最適化

- **対象**: `GraphView.swift`, `CalendarView.swift`
- **問題**: `DataStore` 全体の変更を検知して再描画される。
- **実装方針**:
  - グラフ用データを `Equatable` な Struct (`GraphDataModel`) に切り出す。
  - View側で `.onChange(of: graphData)` を監視し、データが変わった時だけ描画計算を行う。

---

## 3. 実行順序とマイルストーン

1. **Step 1 (R0)**: クラッシュとログの修正。【所要: 1日】
2. **Step 2 (R1)**: CSV機能の統廃合。【所要: 2-3日】
3. **Step 3 (R2)**: 検索・ルールのロジック修正。【所要: 2日】
4. **Step 4 (R3)**: パフォーマンスチューニング。【所要: 3-4日】
5. **Step 5 (Feature)**: 新機能開発（別計画）へ。

## 4. エンジニアリングルール

- **変更の原子性**: 1つのPR（または作業単位）で複数のPhaseを混ぜない。
- **リグレッションテスト**: 特に CSVインポート と データ保存 については、修正後に必ず手動テスト（または単体テスト）を行う。
- **コミットメッセージ**: `[Phase R1] Remove legacy CSVImportView` のようにプレフィックスを付ける。
