# 現状仕様まとめ（Kakeibo App）

このドキュメントは、現在のコードベースから読み取れるアプリの機能・構成・保存方式をまとめたものです。実装の詳細はファイル名・型名をコードスタイルで併記しています。

## 概要
- 家計簿アプリ（SwiftUI）
- 主な機能:
  - 取引の登録・編集・削除（`Transaction`）
  - カテゴリ管理（`Category`）
  - CSVインポート/エクスポート（`DataStore.importCSV`, `DataStore.generateCSV`）
  - 自動分類ルール（`ClassificationRule`, `ClassificationRulesStore`）
  - 検索・フィルタ（`TransactionSearchView`）
  - グラフ表示（`GraphView` + Swift Charts）
  - 口座管理（`Account` / `AccountsView`）
  - 予算・固定費（`Budget`, `FixedCostTemplate`）
  - レシート読み取り（OCR, `ReceiptParser` / Vision）

## データモデル（主要）
- `Transaction`
  - `id`, `date`, `type: TransactionType`, `amount`, `category`, `memo`, `createdAt`
  - 追加情報: `source`, `sourceId`, `accountId`, `toAccountId`, `parentId`, `isSplit`, `isDeleted`
  - 重複判定用のキー（`uniqueKey`/`fingerprintKey`）や検索用正規化文字列（`normalizedSearchText`）を提供
- `TransactionType`: `.expense`, `.income`, `.transfer`
- `Category`: `id`, `name`, `colorHex`, `type`, `order`
- `Account`: 口座種別 `AccountType`（銀行/カード/電子マネー/現金/投資/その他）
- `Budget`, `FixedCostTemplate`: 予算・固定費（保存/読み込みは `DataStore`）
- SwiftData 用のモデル（`TransactionModel`, `CategoryModel`, `AccountModel`, `BudgetModel`, `FixedCostTemplateModel`）は存在するが、現状は互換レイヤのみ（後述）

## 永続化（保存方式）
- 実体は `DataStore`（`@MainActor final class DataStore`）が担う
- 現状は UserDefaults に保存
  - キー: `ds_transactions_v1`, `ds_expense_categories_v1`, `ds_income_categories_v1`, `ds_fixed_costs_v1`, `ds_budgets_v1`
  - 読み書き: `loadTransactions()`, `saveTransactions()` など
- SwiftData について
  - `SwiftDataModels.swift` にモデル定義あり
  - `DataStore+SwiftData.swift` は「未統合のため UserDefaults 互換のダミー実装」を提供
  - `loadAllFromSwiftData()`/`saveToSwiftData()` は内部で UserDefaults を使う
- 現状、CloudKit/iCloud 同期は未実装（クラウド保存はしていない）

## CSV インポート/エクスポート
- エクスポート: `DataStore.generateCSV()`
  - ヘッダー: `日付,種類,金額,カテゴリ,メモ`
- インポート: `DataStore.importCSV(_:format:manualMapping:)`
  - サポート形式（`CSVImportFormat`）:
    - `.appExport`（このアプリのCSV）
    - `.bankGeneric`（銀行汎用）
    - `.cardGeneric`（クレカ汎用）
    - `.amazonCard`（三井住友カード/Amazonカード等）
  - 列マッピング: `ColumnMap` + 任意の手動マッピング（`CSVManualMapping`）
  - 自動判定: `CSVFormatDetector.detectWithConfidence(from:)`
  - 文字コード判定（`CSVImportView.readCSVText`）: UTF-8/UTF-16（LE/BE）/Shift_JIS/EUC-JP/Windows-31J
  - 正規化: BOM除去、CRLF→LF、TSV→CSV 変換
  - Amazonカード検出: `AmazonCardDetector`
  - 重複判定: 既存取引のキー集合で判定（`txKey(_:)`）
  - 結果: `CSVImportResult`（追加件数/重複スキップ/不正行/未分類サンプル/成功率）
  - UI:
    - `CSVImportView`: フォーマット選択、プレビュー、マッピング保存（`SavedMappingsStore`）、実行、結果表示
    - `ImportResultView`: 取り消し（Undo）や未分類レビュー導線

## 自動分類ルール
- `ClassificationRule`（キーワード・マッチ方法・対象カテゴリ・タイプ・優先度）
- `ClassificationRulesStore`
  - 追加/更新/削除/並び替え、優先度再設定
  - 既定ルールのセットアップ（多数）
  - ルール学習: `learn(from:)`（手動分類からの簡易学習）
  - キーワード衝突チェックと上書き（`addRuleWithCheck`, `overwriteRule`）
- 正規化: `TextNormalizer.normalize(_:)`（全角半角・長音・空白・記号揺らぎの吸収）

## 検索・フィルタ
- `TransactionSearchView`
  - 検索対象: `memo`, `category`, `amount`, `date(yyyy/MM/dd)`, `type`
  - フィルタ: 種類、カテゴリ、期間、金額範囲
  - 検索ロジック: `DataStore.searchTransactions(...)`
  - 結果から編集/削除/複製が可能

## グラフ
- `GraphView`（Swift Charts）
  - 種類: 支出円グラフ、収入円グラフ、貯金額、年間支出/収入棒グラフ、収支推移、予算
  - 月移動、横スワイプで種類変更
  - カテゴリ詳細グラフ（`CategoryDetailGraphView`）から月別明細へ遷移
  - 表示設定: 並び順・有効/無効（`settings.graphTypeOrder`, `settings.enabledGraphTypes`）

## カテゴリ・口座・予算・固定費
- カテゴリ
  - 追加/編集/削除/並び替え（`CategoryEditView`）
  - `DataStore` による保存
- 口座
  - 一覧/追加/編集/削除/並び替え（`AccountsView`, `AccountEditView`）
  - 口座別残高は `AccountStore` が算出
- 予算/固定費
  - `DataStore.budgets`, `DataStore.fixedCostTemplates` で保持・保存
  - 予算: 合計/カテゴリ別の取得（`totalBudget`, `categoryBudget`）
  - 固定費: テンプレートの追加/更新/削除

## レシート読み取り（OCR）
- `ReceiptParser`（Vision）
  - テキスト認識 → 金額/日付/店舗名の抽出（正規表現ベースの簡易パーサ）

## UI/状態管理
- SwiftUI + `@EnvironmentObject`
  - 代表: `DataStore.shared`, `AppSettings.shared`, `DeletionManager`
- 各種シート/アラート/プレビュー/進捗オーバーレイ
- 入力支援: 電卓入力（`CalculatorInputView`）

## エラーハンドリング/重複・未分類対応
- CSV インポート結果で詳細を提示（重複/不正行/未分類サンプル）
- 未分類レビュー（`UnclassifiedReviewView`）
  - 同一メモでグルーピング → カテゴリ設定 → ルール保存/過去適用

## 既知の制約・未実装
- データ保存はローカル（UserDefaults）。クラウド同期なし
- SwiftData モデルはあるが、`DataStore` とは未統合（後方互換のシムのみ）
- 一部の拡張（例: `keyboardToolbar`）やメソッド（例: 固定費の自動処理 `processFixedCosts`）は未実装/別途実装が必要
- 週開始日の表示補助（`WeekDays`）など UI ユーティリティは簡易実装

## クラウド保存について（現状）
- 現状はクラウド保存（iCloud/CloudKit）は行っていません
- すべてのデータは UserDefaults に保存されています
- `SwiftData` モデルはあるものの、`DataStore` はまだ SwiftData/CloudKit と接続されていません

## クラウド対応の方針（提案）
- SwiftData + CloudKit を採用
  1. `ModelContainer` を CloudKit 構成で用意
  2. `DataStore` の読み書きを SwiftData 経由に段階移行（UserDefaults からの移行スクリプトを用意）
  3. 競合解決/重複判定の整合性（`fingerprintKey`/`txKey`）を維持
  4. パフォーマンスとデータサイズに応じたフェッチ戦略検討
- 代替案
  - iCloud Key-Value は容量/競合の観点で非推奨
  - 独自バックエンド連携は別途 API 設計が必要

---

最終更新: 自動生成（このファイルはコードベースから現状を要約したものです）
