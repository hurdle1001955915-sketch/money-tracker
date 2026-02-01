# 収支管理アプリ 包括的監査レポート

## 調査日時
2026-01-26

---

## A. 現状仕様サマリ

### アーキテクチャ概要

| 層 | 技術 | 概要 |
|----|------|------|
| UI | SwiftUI | TabView構成（入力・カレンダー・グラフ・資産・設定） |
| 状態管理 | ObservableObject + @Published | DataStore/AppSettings/AccountStore等のシングルトン |
| 永続化 | SwiftData + メモリキャッシュ | ModelContextから読み込み後、@Publishedプロパティで保持 |
| 同期 | CloudKit（無効） | Feature Flagで無効化中（Apple Developer Program制約） |
| セキュリティ | Keychain | OpenAI APIキーの保存 |
| OCR | Vision Framework | レシートスキャン機能 |
| AI | OpenAI Responses API | CSV未分類自動分類（Structured Outputs使用） |

### データモデル

```
Transaction
├── id: UUID
├── date: Date
├── type: TransactionType (.expense/.income/.transfer)
├── amount: Int
├── categoryId: UUID? (新仕様)
├── originalCategoryName: String? (移行用)
├── memo: String
├── accountId: UUID? (振替用)
├── toAccountId: UUID? (振替用)
├── transferId: String? (振替ペアリング)
├── importId: String? (インポート追跡)
└── isDeleted: Bool (ソフト削除)

CategoryItem
├── id: UUID
├── name: String
├── groupId: UUID (階層カテゴリ)
├── type: TransactionType
└── colorHex: String

Account
├── id: UUID
├── name: String
├── type: AccountType
└── initialBalance: Int
```

### 主要機能

1. **手動入力**: 金額・カテゴリ・日付・メモを入力
2. **CSVインポート**: PayPay/りそな銀行/Amazonカード形式対応
3. **AI分類**: OpenAI APIで未分類取引を自動分類
4. **振替**: 口座間の資金移動（ペアリング管理）
5. **固定費自動生成**: 月次テンプレートから取引自動作成
6. **予算管理**: 全体予算・カテゴリ別予算
7. **グラフ**: 円グラフ・棒グラフ・推移グラフ
8. **レシートスキャン**: Vision OCRで店舗名・金額・日付抽出
9. **検索**: キーワード/除外検索・日付/金額フィルタ
10. **Undo削除**: 6秒間の取り消し猶予

---

## B. 課題一覧（15項目以上）

| # | カテゴリ | 重要度 | 課題 | 影響 | 解決策 |
|---|---------|--------|------|------|--------|
| 1 | データ整合性 | P0 | CloudKit同期のマージロジックが`createdAt`比較のみで、`updatedAt`フィールドがない | 更新時刻がないためオフライン編集の競合解決が不正確 | `updatedAt`フィールド追加、Last-Write-Wins または Conflict Resolution UI |
| 2 | データ整合性 | P0 | 振替ペア作成時にトランザクション性がない | 片方のみ保存されるとデータ不整合 | バッチ保存または`transferId`による整合性チェック追加 |
| 3 | データ整合性 | P1 | `fingerprintKey`がカテゴリID移行前後で変化し、重複判定が不正確になる可能性 | 同一取引の再インポート時に重複発生 | `importFingerprintKey`を一貫して使用、またはhash保存 |
| 4 | セキュリティ | P1 | CSVファイルのサニタイズ不足（改行・カンマ・引用符のエスケープ） | CSV Injection攻撃の可能性 | CSV出力時の適切なエスケープ処理 |
| 5 | パフォーマンス | P1 | `DataStore.transactions`が全件メモリ保持、フィルタリングで毎回O(n)走査 | 数万件で顕著なメモリ使用量・処理遅延 | インデックス付きキャッシュ（日付別Dictionary等）の導入 |
| 6 | パフォーマンス | P1 | `CalendarView.gridDates`が毎描画で42日分計算 | スクロール時の不要な再計算 | `@State`または`EquatableView`でキャッシュ |
| 7 | UX | P1 | AI分類エラー時のリトライ機能がない | 一時的なネットワークエラーで全て失敗扱い | 指数バックオフリトライ、部分成功の継続処理 |
| 8 | UX | P2 | Undo削除が1件のみ対応、一括削除はUndo不可 | インポート取り消し時に復元不可 | スタック形式のUndo履歴、またはインポート単位でのロールバック |
| 9 | UX | P2 | `ReceiptParser`の店舗パターンがハードコード | 新店舗追加時にアプリ更新が必要 | ユーザー定義パターン、または学習型マッチング |
| 10 | 同期 | P1 | CloudKit subscriptionのリアルタイム通知処理が未実装 | 他デバイスでの変更が即時反映されない | `application(_:didReceiveRemoteNotification:)`でfetch処理 |
| 11 | 同期 | P2 | iCloud同期のカテゴリ・口座・予算がTransaction以外未実装 | デバイス間でマスタデータ不整合 | CategoryModel/AccountModel/BudgetModelもCloudKit対応 |
| 12 | コード品質 | P2 | `DataStore`が1000行超の God Object | 保守性・テスト性の低下 | Repository Pattern分離（TransactionRepository等） |
| 13 | コード品質 | P2 | `ClassificationRulesStore`がUserDefaultsにJSON保存 | 大量ルールで起動遅延、移行困難 | SwiftData移行 |
| 14 | エラーハンドリング | P2 | SwiftData保存エラーが`try?`で握りつぶされている箇所多数 | データ消失の原因追跡困難 | Result型またはエラーログ記録 |
| 15 | アクセシビリティ | P2 | VoiceOver対応が不完全（カスタムViewに`accessibilityLabel`なし） | 視覚障害ユーザーが利用困難 | 主要コンポーネントにa11y対応追加 |
| 16 | テスト | P2 | ユニットテスト・UIテストが存在しない | リグレッション検知不可 | XCTest/XCUITest導入、主要ロジックのカバレッジ確保 |
| 17 | ローカライズ | P3 | 日本語ハードコード多数 | 多言語展開時に大規模修正必要 | `String(localized:)`への移行 |
| 18 | 機能 | P2 | 固定費の「休日前倒し/後ろ倒し」がWeekendHolidayHandling設定と連動していない | 設定が効いていない | `processFixedCosts`でsettings参照 |

---

## C. 優先度別ロードマップ

### Phase 1: 必須修正（P0）

```
1. 振替ペアのトランザクション性確保
   - createTransferPair内でバッチ保存
   - 失敗時のロールバック処理

2. CloudKit同期のupdatedAt対応
   - TransactionにupdatedAtフィールド追加
   - マージロジック修正
```

### Phase 2: 重要改善（P1）

```
3. fingerprintKey一貫性
   - 既存データのsourceHash再計算
   - インポート時の判定ロジック統一

4. CSV出力サニタイズ
   - generateCSVのエスケープ処理強化

5. パフォーマンス最適化
   - 日付別トランザクションキャッシュ
   - CalendarView計算のメモ化

6. AI分類リトライ
   - 指数バックオフ（1s, 2s, 4s）
   - 最大3回リトライ

7. CloudKit通知処理
   - didReceiveRemoteNotification実装
```

### Phase 3: 品質向上（P2-P3）

```
8-18. コード品質・テスト・a11y対応
```

---

## D. 機能改善提案（10項目以上）

| # | 機能名 | 概要 | 価値 |
|---|--------|------|------|
| 1 | **定期取引の柔軟化** | 週次・隔週・年次の定期取引サポート | 保険料・サブスク対応 |
| 2 | **スマート分類学習** | ユーザーの手動分類を学習し、AI分類の精度向上 | 分類ヒントの自動蓄積 |
| 3 | **CSV自動検出** | CSVフォーマットを自動判別し、マッピング不要に | インポートUX向上 |
| 4 | **予算アラート通知** | 予算80%/100%到達時にローカル通知 | 使いすぎ防止 |
| 5 | **家計簿共有** | 家族間でデータ共有（CloudKit Sharing） | ファミリーユースケース |
| 6 | **レポート出力** | 月次/年次レポートのPDF出力 | 確定申告・振り返り |
| 7 | **Apple Watch対応** | クイック入力・残高確認 | 即時記録 |
| 8 | **ウィジェット強化** | 今月の残予算・直近取引表示 | ホーム画面で把握 |
| 9 | **銀行API連携** | Open Banking APIで自動取込 | 手入力削減 |
| 10 | **目標貯金機能** | 貯金目標設定と進捗トラッキング | モチベーション |
| 11 | **タグ機能** | カテゴリとは別の横断的タグ付け | 旅行費など横断集計 |
| 12 | **為替対応** | 外貨取引の円換算表示 | 海外旅行・投資 |

---

## E. 多角的分析

### 表（ユーザー視点）

**強み:**
- シンプルで直感的なUI
- よく使うカテゴリのショートカット
- レシートスキャン機能
- AI分類による入力効率化

**課題:**
- 初回セットアップが煩雑（カテゴリ設定）
- CSV形式が限定的
- オフライン編集後の同期が不安

### 裏（システム視点）

**強み:**
- SwiftUIの宣言的UIで保守性良好
- SwiftDataによる型安全な永続化
- Feature Flagによる段階的リリース可能

**課題:**
- God Object（DataStore）の肥大化
- テストカバレッジ0%
- エラーハンドリングの一貫性欠如
- CloudKit同期の競合解決が未成熟

### 横（競合・市場視点）

**ポジショニング:**
```
        手軽さ
           ↑
    [本アプリ]  [Zaim]
           │
    ───────┼──────→ 機能充実度
           │
    [シンプル家計簿] [MoneyForward]
```

**差別化ポイント:**
- AI分類によるCSVインポート効率化
- レシートOCR（無料で利用可能）
- オフラインファースト設計

**脅威:**
- MoneyForward/Zaimの銀行自動連携
- Apple標準アプリとの競合可能性

---

## 質問（最大5件）

1. **CloudKit同期の優先度**: 現在Feature Flagで無効化されていますが、有料Developer登録後にフル実装予定でしょうか？優先度を確認したいです。

2. **多通貨対応のニーズ**: 海外旅行や投資関連の外貨取引を扱う予定はありますか？

3. **Open Banking API連携**: 銀行API連携（マネーフォワード等の機能）の実装意向はありますか？技術的にはScreen Scrapingよりも安全ですが、各銀行との契約が必要です。

4. **ユニットテストの方針**: テスト導入は計画されていますか？優先的にカバーすべきモジュール（DataStore、インポート処理等）の指定があれば教えてください。

5. **リリース形態**: App Store公開予定でしょうか？TestFlightでの限定配布でしょうか？プライバシーポリシー対応の要否を確認したいです。

---

## 付録: 読み込みファイル一覧

| ファイル | 行数 | 概要 |
|---------|------|------|
| DataStore.swift | ~1200 | 中央データ管理（God Object） |
| Transaction.swift | 431 | 取引モデル |
| CloudKitSyncManager.swift | 452 | iCloud同期 |
| AIClassificationService.swift | 329 | AI分類サービス |
| AIClassificationTypes.swift | 317 | AI分類型定義 |
| ImportDraftTypes.swift | ~1000 | CSVインポートステート |
| CSVImportWizardView.swift | ~1500 | CSVインポートUI |
| ReceiptParser.swift | 353 | レシートOCR |
| AppSettings.swift | 182 | アプリ設定 |
| KeychainStore.swift | 89 | Keychain操作 |
| DeletionManager.swift | 176 | Undo削除管理 |
| ContentView.swift | 68 | メインTabView |
| InputView.swift | ~600 | 取引入力画面 |
| CalendarView.swift | ~500 | カレンダー画面 |
| GraphView.swift | ~700 | グラフ画面 |
| ClassificationRule.swift | 662 | 分類ルール |
| AppFeatureFlags.swift | 10 | 機能フラグ |
