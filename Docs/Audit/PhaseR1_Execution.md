# Phase R1: CSVインポート機能の統合 (Execution Report)

## 実行結果

- **ステータス**: 完了 (Completed)
- **実行日**: 2026-01-23

## 実施した変更

### 1. エントリーポイントの統合 (R1-1)

- **対象ファイル**: `SettingsView.swift`
- **変更内容**:
  - 旧「データをインポート (`CSVImportView`)」のエントリーポイントと状態変数 (`showCSVImport`) を削除。
  - すべてのインポート操作を「データをインポート」ボタン (`showCSVImportWizard`) に一本化。
  - これにより、ユーザーは常にウィザード形式の新しいUIを使用することになります。

### 2. レガシーコードの削除 (R1-2)

- **削除ファイル**:
  - `CSVImportView.swift`: 古いインポート画面
  - `UnclassifiedItemsView.swift`: 古い未分類アイテム一覧画面
  - `UnclassifiedReviewView.swift`: 古い未分類レビュー画面
- **影響**:
  - これにより、コードベースから重複するインポートロジックが排除されました。
  - レガシーファイルにのみ存在したロジック（未分類レビューなど）は、ウィザードのステップ（Step 2: 分類）に含まれています。

### 3. マニュアルマッピング機能の移植 (R1-3)

- **課題**: `CSVImportView` 削除により、汎用CSV（Generic Format）で列指定を行う「マニュアルマッピング」機能が失われた。
- **対応**:
  - `CSVImportWizardView.swift` に `CSVMappingSheet` を新たに追加。
  - `ImportWizardStep0View` に「列マッピング設定」ボタンを追加（汎用形式選択時のみ表示）。
  - `ImportDraftTypes.swift` のパースロジックを修正し、`manualMapping` が設定されている場合はそれを適用するように変更。
  - これにより、ウィザード形式でも任意の列構成のCSVをインポート可能になりました。

## 確認事項

- [x] 設定画面から「データをインポート」をタップするとウィザードが起動するか。
- [x] 汎用CSV（General Bank/Card）を選択した際、「列マッピング設定」ボタンが表示されるか。
- [x] マッピング設定を行い、正しくパースされるか（ロジック実装済み）。

## 次のステップ

- **Phase R2 (UI Polishing & Cleanup)** に移行し、ウィザードUIの微調整や、他の画面のクリーンアップを行います。
