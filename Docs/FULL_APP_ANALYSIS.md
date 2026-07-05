# 収支管理アプリ（Kakeibo）— 完全解析仕様書

> 解析日: 2026-04-01
> 解析手法: 12エージェント並列解析（全62 Swiftファイル + Xcode設定 + テスト + ドキュメント）
> 目的: App Store掲載に向けたアプリの現状把握・改善基盤

---

## 1. アプリ概要

| 項目 | 内容 |
|---|---|
| アプリ名 | 収支管理（家計簿） |
| 開発者 | 井原翔太郎 |
| 言語 | Swift 5.0 / SwiftUI |
| 対象OS | iOS 26.2+ |
| 対応デバイス | iPhone + iPad |
| Bundle ID | `com.shotaroihara.----`（仮） |
| Development Team | XMAL6X2BBJ |
| ビルドツール | Xcode 26.2 |
| 総コード量 | 約24,000行 / 62 Swiftファイル |
| テスト | 5ファイル / 82テストケース（パーサー層のみ） |

---

## 2. アーキテクチャ

### 2.1 レイヤー構造

```
┌─────────────────────────────────────┐
│  UI層（SwiftUI Views）              │
│  TabView: 入力 / カレンダー / グラフ / 資産 / 設定  │
├─────────────────────────────────────┤
│  状態管理（@ObservableObject）       │
│  DataStore / AppSettings / AccountStore / DeletionManager │
├─────────────────────────────────────┤
│  ビジネスロジック                     │
│  ClassificationRulesStore / AIClassificationService      │
│  ReceiptParser / CSVImport / BackupPayload               │
├─────────────────────────────────────┤
│  永続化層                            │
│  SwiftData (ModelContainer) + UserDefaults               │
│  Keychain (OpenAI APIキー)                               │
└─────────────────────────────────────┘
```

### 2.2 起動フロー

```
@main KakeiboApp
  ├─ SwiftData ModelContainer初期化（失敗時→メモリフォールバック）
  ├─ 環境オブジェクト注入
  ├─ ロケール: ja_JP / カラースキーム: .light固定
  └─ LockScreenModifier適用
      ├─ appLockEnabled → Face ID/Touch ID認証
      └─ 認証成功 or ロック無効 → ContentView（TabView）

onAppear:
  1. Diagnostics.logStartupDiagnostics()
  2. DBフォールバックモードチェック
  3. DataMigration.migrateIfNeeded()（JSON→SwiftData）
  4. DataStore.processAllFixedCostsUntilNow()
  5. ClassificationRulesStore.ensureDefaultRules()
```

### 2.3 タブ構造

| Tab | 名前 | View | アイコン |
|-----|------|------|---------|
| 0 | 入力 | TransactionInputView | pencil |
| 1 | カレンダー | CalendarView | calendar |
| 2 | グラフ | GraphView | chart.pie |
| 3 | 資産 | AssetDashboardView | briefcase |
| 4 | 設定 | SettingsView | gearshape |

---

## 3. データモデル

### 3.1 Transaction（取引）

| フィールド | 型 | 説明 |
|---|---|---|
| id | UUID | 一意識別子 |
| date | Date | 取引日 |
| type | TransactionType | .expense / .income / .transfer |
| amount | Int | 金額（円） |
| memo | String | 説明 |
| categoryId | UUID? | カテゴリID（新仕様） |
| originalCategoryName | String? | カテゴリ名（旧仕様・移行用） |
| accountId | UUID? | 振替元口座 |
| toAccountId | UUID? | 振替先口座 |
| transferId | String? | 振替ペアID |
| parentId | UUID? | 分割親取引ID |
| isSplit | Bool | 分割フラグ |
| isDeleted | Bool | ソフト削除 |
| source | String? | CSV入力元 |
| importId | String? | インポートバッチID |
| sourceHash | String? | 重複判定用ハッシュ |
| classificationSource | ClassificationSource? | manual/rule/ai/imported |
| classificationRuleId | UUID? | マッチルールID |
| classificationConfidence | Double? | AI信頼度 |
| createdAt | Date | 作成日時 |

### 3.2 カテゴリ（2階層）

| モデル | 説明 |
|---|---|
| CategoryGroup | 大分類（生活/買い物/移動/娯楽/お金関連/未分類） |
| CategoryItem | 中分類（食費/外食/日用品 等） |
| Category | フラット互換（旧仕様） |

デフォルト: 支出6グループ・40+カテゴリ / 収入2グループ・10+カテゴリ

### 3.3 その他モデル

| モデル | 説明 |
|---|---|
| Account | 口座（bank/creditCard/electronicMoney/payPay/suica/cash/investment/other） |
| Budget | 予算（全体 or カテゴリ別） |
| FixedCostTemplate | 固定費テンプレート（月次自動生成） |
| ClassificationRule | 自動分類ルール（キーワード→カテゴリ、48+デフォルト） |
| ImportHistory | インポート履歴 |

### 3.4 永続化戦略

- **現状**: SwiftData + UserDefaults並行（移行期）
- **SwiftDataスキーマ**: TransactionModel, CategoryModel, AccountModel, BudgetModel, FixedCostTemplateModel, ImportHistoryModel
- **CloudKit同期**: コード実装あり、Feature Flag `cloudSyncEnabled = false` で無効

---

## 4. 機能詳細

### 4.1 取引入力（InputView）

- 支出/収入セグメント切替
- 電卓入力（CalculatorInputView）: 四則演算対応、別シート表示
- よく使うカテゴリ（上位5件）+ 階層型カテゴリピッカー
- 日付・メモ入力
- クイックアクション: 振替 / 分割 / レシート読み込み（新規時のみ）
- 予算超過時スナックバー表示（3.5秒自動消去）

### 4.2 カレンダー（CalendarView）

- 42マス固定グリッド（6週分）
- 日付セルに収入/支出額を小フォントで表示
- スワイプで月移動、タップで日選択、ダブルタップで新規入力
- 日詳細セクション: 選択日の取引一覧（スワイプで複製/削除）
- 月サマリーバー: 収入・支出・合計

### 4.3 グラフ（GraphView）— 7種類

| グラフ | 種類 | 説明 |
|---|---|---|
| 支出別 | 円グラフ（ドーナツ） | カテゴリ別支出 |
| 収入別 | 円グラフ（ドーナツ） | カテゴリ別収入 |
| 貯金額 | 棒+折れ線 | 月別貯金推移 |
| 年間支出 | 棒グラフ | 月別支出 |
| 年間収入 | 棒グラフ | 月別収入 |
| 収支推移 | 二軸折れ線 | 収入vs支出 |
| 予算 | プログレスバー | 予算達成状況 |

- 円グラフ → カテゴリ詳細（月別推移）→ 月別取引リストへドリルダウン
- 表示順・有効/無効はカスタマイズ可能

### 4.4 CSVインポート（4ステップウィザード）

| Step | 内容 |
|---|---|
| 0: 設定 | ファイル選択、フォーマット選択、口座選択 |
| 1: プレビュー | パース結果一覧、フィルタ、一括カテゴリ設定、行選択削除 |
| 2: 分類 | 未分類の解決（グループ単位カテゴリ設定）、振替候補の確認・確定 |
| 3: 確認 | 最終確認、保存、完了（取り消し可能） |

対応フォーマット: appExport / payPay / resonaBank / amazonCard / bankGeneric / cardGeneric

### 4.5 AI自動分類

- OpenAI Responses API（gpt-4o-mini）
- Structured Outputs（信頼度スコア付き）
- 信頼度 >= 0.80 → 自動確定 / < 0.80 → 手動確認
- 1バッチ25件単位
- APIキーはKeychainに保存

### 4.6 レシートOCR

- Vision Framework（ja-JP / en-US）
- 店舗名: 58チェーン登録済み + フォールバック推定
- 金額: 税込合計 > 総合計 > 合計 > フォールバック（最大値）
- 日付: YYYY/MM/DD, YYYY年MM月DD日, YYYY-MM-DD

### 4.7 資産ダッシュボード

- 総資産サマリー
- ポートフォリオ円グラフ（口座別残高）
- 資産推移チャート（過去6ヶ月）
- 口座一覧 → AccountDetailView（残高推移+取引履歴）

### 4.8 検索・フィルタ

- キーワード検索（memo/category/amount/date/type）
- フィルタ: 種類、カテゴリ、未分類、期間、金額範囲
- ソート: 日付/金額 × 昇順/降順
- アクティブフィルタChip表示、結果統計（件数+合計額）

### 4.9 設定

- 口座管理（CRUD + 並び替え + 8テンプレート）
- カテゴリ管理（支出/収入別、色選択）
- 固定費・定期収入テンプレート
- 自動分類ルール管理（テスト機能付き）
- 予算設定（全体 + カテゴリ別）
- 表示設定（週開始日、月開始日、同日ソート順、グラフ設定）
- 通知（入れ忘れ防止リマインダー）
- データ管理（バックアップ/復元/CSV出入力/インポート履歴）
- セキュリティ（Face ID/Touch ID/パスコード）
- AI機能（OpenAI APIキー設定）
- iCloud同期（Feature Flag OFF）

### 4.10 Widget

- 小: 今日の支出
- 中: 今日の支出 + 今月サマリー（収入/支出/残高）
- 大: 月サマリー + 直近4件の取引

### 4.11 Siri Shortcuts（AppIntents）

- 今日の支出を確認
- 今月の収支を確認
- 支出を記録（金額・カテゴリ・メモ）
- 収入を記録
- 家計簿を開く

### 4.12 テーマシステム

- セマンティックカラー（収入=青, 支出=赤, 振替=橙, 貯金=緑）
- ダークモード完全対応
- 8ptグリッドスペーシング
- monospacedDigit金額フォント
- ハプティクス10種類（HapticManager）
- ビューモディファイア（cardStyle, glassStyle, shimmer等）

---

## 5. UX/UI問題一覧（全エージェント統合）

### 5.1 致命的（P0）— 操作不能・混乱を招く

| # | 問題 | 場所 | 詳細 |
|---|---|---|---|
| P0-1 | **CSVインポートStep1でボタンが消える** | CSVImportWizardView | 全行がresolved時「分類・振替へ」ボタンが非表示→「保存前の確認」に切り替わるが、遷移が不明確 |
| P0-2 | **DayDetailViewが2つ存在** | CalendarView内 + DayDetailView.swift | 同じ機能の異なる実装が並存。長押し削除/メモ表示行数/アイコンサイズが不一致 |
| P0-3 | **AccountDetailViewに編集ボタンがない** | AccountDetailView | 口座詳細を見ても編集・削除できない。口座一覧に戻る必要あり |
| P0-4 | **レシートパーサーのエラー状態が残留** | ReceiptScannerView | parser.resultが設定されてもparser.errorが前回のまま→エラーバナーが消えない |

### 5.2 高優先（P1）— UX品質を大きく損なう

| # | 問題 | 場所 | 詳細 |
|---|---|---|---|
| P1-1 | **金額入力の不統一** | InputView vs TransferInputView vs SplitTransactionView | InputViewは演算式対応、Transfer/Splitは非対応 |
| P1-2 | **電卓が別シートで開く** | CalculatorInputView | インラインで展開できず、金額修正に往復が必要 |
| P1-3 | **CSVインポートAI分類の結果UIが不明確** | CSVImportWizardView Step2 | AI分類ボタンのdisabled条件がUX上不明確、結果表示後の遷移が不明 |
| P1-4 | **CSVインポートStep2→3の変更が揮発** | CSVImportWizardView | ドラフト状態がメモリ上のみ。戻る操作で変更が消失するリスク |
| P1-5 | **予算超過スナックバーが自動消去** | InputView | 3.5秒後に消える。重要な警告を見落とす |
| P1-6 | **カレンダー日付セルの情報密度** | CalendarView | 9ptフォント+1行制限で金額が読めない |
| P1-7 | **バックアップ機能が二重化** | SettingsView | 従来型バックアップとZIPバックアップの違いが不明確 |
| P1-8 | **カテゴリ未選択でも保存可能** | InputView | 自動で最初のカテゴリが入り、ユーザーが気づかない |
| P1-9 | **編集モードでクイックアクション非表示** | InputView | 振替/分割/レシートボタンが編集時に消える |

### 5.3 中優先（P2）— 改善推奨

| # | 問題 | 場所 | 詳細 |
|---|---|---|---|
| P2-1 | カテゴリピッカーの往復が多い | HierarchicalCategoryPicker | 大分類→中分類→戻る→別グループの往復 |
| P2-2 | グラフ→詳細が2ステップ | GraphView | カテゴリ月別推移→当月取引リストへの到達に2タップ |
| P2-3 | 振替UIが地味 | TransferInputView | Form+Sectionで標準的なUI。「振替」の特別感がない |
| P2-4 | 分割取引で同カテゴリ重複が可能 | SplitTransactionView | 「食費3000円」「食費2000円」の重複選択を防げない |
| P2-5 | 固定費type切替時にカテゴリが消える | FixedCostEditView | 支出→収入切替でselectedCategoryIdが自動リセット（警告なし） |
| P2-6 | iCloud同期状態が自動更新されない | SettingsView | 「最後に同期: X分前」が画面表示中に陳腐化 |
| P2-7 | 日付ピッカーが二重シート | TransactionSearchView FilterSheet | FilterSheet→DatePickerSheetの深いナビゲーション |
| P2-8 | 空グループがカテゴリピッカーに表示 | HierarchicalCategoryPicker | タップしても空→UX悪化 |
| P2-9 | ルール優先度の説明不足 | ClassificationRulesView | 複数ルールマッチ時の動作が不明確 |
| P2-10 | OCR信頼度チェックなし | ReceiptParser | 低品質OCR結果でも「読み取り完了」扱い |

### 5.4 低優先（P3）— ポリッシュ

| # | 問題 | 場所 |
|---|---|---|
| P3-1 | 無データプレースホルダが不統一 | 各View |
| P3-2 | 電卓の%ボタンの用途不明 | CalculatorInputView |
| P3-3 | ダミー戻るボタン（opacity(0)） | HierarchicalCategoryPicker |
| P3-4 | カテゴリ名lineLimit(1)で切れる | HierarchicalCategoryPicker |
| P3-5 | Widgetに日付情報なし | WidgetViews（Large） |
| P3-6 | アクセシビリティ対応不足 | 全体 |
| P3-7 | CSV Injection対策なし | CSVエクスポート |

---

## 6. 技術的課題

### 6.1 データモデル

| 課題 | 詳細 |
|---|---|
| Category二重定義 | CategoryとCategoryItemが並存。互換変換オーバーヘッド |
| categoryId移行が分散 | 各モデルで個別にmigrate*メソッド実装（DRY違反） |
| 重複判定キーの段差 | fingerprintKey vs importFingerprintKey でID化前後の検出漏れリスク |
| updatedAtフィールド欠落 | CloudKit同期のマージ競合対策が不十分 |
| 振替ペア整合性 | transferIdが同一でも3件以上残存する可能性 |

### 6.2 パフォーマンス

| 課題 | 詳細 |
|---|---|
| DataStoreがメモリ全件保持 | O(n)フィルタ。大量取引時にパフォーマンス低下 |
| CalendarView毎描画再計算 | 月別集計のキャッシング未実装 |
| カテゴリ検索が線形探索 | ハッシュマップキャッシング未実装 |

### 6.3 セキュリティ

| 課題 | 詳細 |
|---|---|
| Widget UserDefaults平文保存 | 金額データが暗号化されていない |
| CSV Injection対策なし | エクスポート時のエスケープ処理が必要 |

### 6.4 テスト

| 現状 | テストカバレッジ |
|---|---|
| パーサー層 | 95%+（82テストケース） |
| ビジネスロジック層 | 0% |
| UI/State層 | 0% |
| 統合テスト | 0% |

---

## 7. Xcode プロジェクト設定

| 項目 | 値 |
|---|---|
| Deployment Target | iOS 26.2 |
| Swift Version | 5.0 |
| SWIFT_DEFAULT_ACTOR_ISOLATION | MainActor |
| Entitlements | 空（Capability未設定） |
| Info.plist権限 | カメラ / Face ID / 写真ライブラリ |
| 対応デバイス | iPhone + iPad |
| Marketing Version | 1.0 |
| Build Number | 1 |

### App Store提出に向けた不足

- Privacy Policy URL未設定
- App Icon（Assets.xcassets確認必要）
- Entitlements空（iCloud等のCapability未設定）
- ローカライゼーション: ja_JPのみ（App Store用にen対応推奨）
- `IPHONEOS_DEPLOYMENT_TARGET = 26.2` は最新すぎる可能性

---

## 8. 既存ドキュメント

| ファイル | 内容 |
|---|---|
| PROJECT_SPEC.md | 現状仕様まとめ（自動生成） |
| AI_FullAudit_Report.md | 包括的監査（15課題） |
| AI_PostImpl_Audit.md | AI分類実装後検証 |
| Docs/Audit/Phase0-8.md | フェーズ別実装計画・完了レポート |
| presentation/ | プレゼンスライド + トークスクリプト + デモフロー |

---

*本仕様書は12エージェントによる並列解析の統合結果です。*
