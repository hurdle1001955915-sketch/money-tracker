# 家計簿アプリ 第5回実装完了

## 実装内容：OS統合＋OCR

### 1. Face ID / Touch ID認証（アプリロック）

**AppLockManager.swift**
- シングルトンパターン（AppLockManager.shared）
- 生体認証タイプ自動検出（Face ID / Touch ID / Optic ID）
- 認証失敗時のパスコードフォールバック
- バックグラウンド移行時の自動ロック機能
- 認証状態管理（isLocked, isAuthenticating, authError）

**LockScreenView.swift**
- ロック画面UI
- 自動認証トリガー（画面表示時）
- scenePhase監視でバックグラウンド/フォアグラウンド対応
- `.withLockScreen()` モディファイアで簡単統合

**AppLockSettingView.swift**
- アプリロック設定画面
- 生体認証の有効化/無効化トグル
- バックグラウンド時ロック設定
- 対応認証方法の表示

### 2. レシートOCR（カメラでレシート読み取り）

**ReceiptParser.swift**
- Vision Framework使用
- 日本語優先テキスト認識（ja-JP, en-US）
- 抽出機能：
  - 店舗名（最初の非金額行）
  - 日付（複数フォーマット対応：yyyy年M月d日, yyyy/M/d等）
  - 合計金額（合計/小計キーワード優先）
  - 明細アイテム（商品名＋金額）
- 金額パターン認識（¥1,234 / 1,234円 / 数字のみ）

**ReceiptScannerView.swift**
- カメラ/写真ライブラリからの画像選択
- 読み取り結果プレビュー（店舗/日付/合計/明細）
- 取引情報入力フォーム（日付/金額/カテゴリ/メモ）
- 読み取り結果から自動入力
- ImagePicker（UIImagePickerController wrapper）

### 3. ホーム画面ウィジェット

**WidgetDataProvider.swift**
- App Groups対応（group.com.kakeibo.app）
- ウィジェット用データ構造（WidgetData）
  - 今日の支出
  - 今月の収入/支出/残高
  - 直近の取引リスト
- メインアプリからの更新機能
- ウィジェットからの読み取り機能

**WidgetViews.swift**
- 小サイズ（今日の支出）
- 中サイズ（今日＋今月収支）
- 大サイズ（収支サマリー＋直近取引）
- containerBackground対応（iOS 17+）

### 4. Siriショートカット

**AppIntents.swift**（iOS 16+ App Intents Framework）

| Intent | 説明 | 音声コマンド例 |
|--------|------|---------------|
| GetTodayExpenseIntent | 今日の支出確認 | 「今日いくら使った？」 |
| GetMonthSummaryIntent | 今月の収支確認 | 「今月の家計簿を見せて」 |
| AddExpenseIntent | 支出記録 | 「家計簿に支出を記録」 |
| AddIncomeIntent | 収入記録 | 「収入を記録して」 |
| OpenKakeiboIntent | アプリを開く | - |

**KakeiboShortcuts**
- AppShortcutsProvider準拠
- ショートカットアプリで自動表示

### 5. UI統合

**KakeiboApp.swift更新**
- AppLockManager環境オブジェクト追加
- `.withLockScreen()` モディファイア適用

**AppSettings.swift更新**
- appLockEnabled: アプリロック有効/無効
- lockOnBackground: バックグラウンド時自動ロック

**SettingsView.swift更新**
- セキュリティセクション追加（アプリロック設定）
- ツールセクション追加（レシート読取）

**InputView.swift更新**
- レシート読取ボタン追加（振替/分割と並列）
- レシート読取シート

**DataStore.swift更新**
- WidgetKit import追加
- saveTransactions()でウィジェットデータ自動更新

## ファイル一覧（39ファイル）

### 第5回新規作成（8ファイル）
| ファイル | 説明 |
|---------|------|
| AppLockManager.swift | 生体認証管理 |
| LockScreenView.swift | ロック画面UI |
| AppLockSettingView.swift | ロック設定画面 |
| ReceiptParser.swift | レシートOCR解析 |
| ReceiptScannerView.swift | レシート読取UI |
| WidgetDataProvider.swift | ウィジェットデータ |
| WidgetViews.swift | ウィジェットビュー |
| AppIntents.swift | Siriショートカット |

### 第5回更新（5ファイル）
| ファイル | 更新内容 |
|---------|---------|
| KakeiboApp.swift | ロック画面統合 |
| AppSettings.swift | ロック設定プロパティ追加 |
| SettingsView.swift | セキュリティ/ツールセクション追加 |
| InputView.swift | レシート読取ボタン追加 |
| DataStore.swift | ウィジェット更新処理追加 |

### 既存ファイル（26ファイル）
AccountStore.swift, AccountsView.swift, BackupPayload.swift, BasicSettingsViews.swift, Budget.swift, CalendarGraphSettingsViews.swift, CalendarView.swift, Category.swift, ClassificationRule.swift, ClassificationRulesView.swift, ContentView.swift, CSVDocumentPicker.swift, CSVImportTypes.swift, CSVImportView.swift, DayDetailView.swift, DeletionManager.swift, Extensions.swift, FixedCost.swift, FixedCostBudgetViews.swift, GraphView.swift, SplitTransactionView.swift, Transaction.swift, TransactionSearchView.swift, TransferInputView.swift, UndoBannerView.swift

## Xcodeプロジェクト設定

### Info.plist追加項目
```xml
<!-- カメラ使用許可 -->
<key>NSCameraUsageDescription</key>
<string>レシートを撮影して読み取るために使用します</string>

<!-- 写真ライブラリ使用許可 -->
<key>NSPhotoLibraryUsageDescription</key>
<string>レシート画像を選択するために使用します</string>

<!-- Face ID使用許可 -->
<key>NSFaceIDUsageDescription</key>
<string>アプリのロックを解除するために使用します</string>
```

### Capabilities追加
1. **App Groups** - ウィジェットとのデータ共有
   - group.com.kakeibo.app

2. **Siri** - Siriショートカット対応

### Widget Extension作成
1. File > New > Target > Widget Extension
2. App Group設定（group.com.kakeibo.app）
3. WidgetViews.swiftの内容をWidget Extensionに移動

## 全5回の実装まとめ

| 回 | テーマ | 主な機能 |
|----|--------|---------|
| 第1回 | 土台改修＋信頼性 | マイグレーション、削除Undo、バックアップ、インポートレポート |
| 第2回 | インポート体験 | テンプレート自動判定、マイテンプレ保存、詳細結果表示UI |
| 第3回 | 入力高速化 | 取引複製、自動分類ルール、検索強化 |
| 第4回 | 会計の正しさ | 口座管理、振替、分割取引 |
| 第5回 | OS統合＋OCR | Face ID、ウィジェット、Siri、レシートOCR |

## 技術スタック

- **UI**: SwiftUI
- **データ**: UserDefaults + Codable
- **認証**: LocalAuthentication (LAContext)
- **OCR**: Vision Framework (VNRecognizeTextRequest)
- **ウィジェット**: WidgetKit + App Groups
- **Siri**: App Intents Framework (iOS 16+)

## 注意事項

1. **Widget Extension**は別ターゲットとして作成が必要
2. **App Groups**のIDは実際のプロジェクトに合わせて変更
3. **レシートOCR**は日本語レシートに最適化されているが、フォーマットによっては認識精度が変動
4. **Siriショートカット**はiOS 16以上で動作

---

## Phase A: SwiftDataマイグレーション準備（安全装置）

### 実装内容

#### 1. MigrationStatus (MigrationStatus.swift)
- UserDefaultsベースのマイグレーションフラグ管理
- 一度だけの移行を保証（重複データ防止）
- マイグレーション日時・件数の記録

#### 2. Diagnostics (Diagnostics.swift)
- 起動時診断ログ
  - JSONファイルの存在・サイズ確認
  - データ件数（Transaction, Category, Account等）
  - マイグレーションステータス
- CSVインポート時のログ記録
- ログエクスポート機能

#### 3. JSONデータ保護方針
- Application Support配下のJSONファイルは削除しない
- 旧カテゴリファイルは `.bak` にリネームして保持
- resetAllData()はメモリ上のクリア＋ファイル上書きのみ

### テストチェックリスト

```
□ 起動時の診断ログ確認
  - Xcodeコンソールで [STARTUP], [JSON], [MIGRATION] ログを確認
  - JSONファイルの件数が正しく表示されるか

□ マイグレーションフラグの動作確認
  - MigrationStatus.shared.needsMigration が正しく判定されるか
  - markJsonToSwiftDataMigrationCompleted() で完了フラグが立つか
  - 再起動後も完了状態が維持されるか

□ 一覧表示の確認
  - カレンダービューで取引が正しく表示されるか
  - カテゴリ別集計が正しいか

□ 入力の確認
  - 新規支出/収入を追加できるか
  - カテゴリ選択が機能するか
  - 保存後、一覧に反映されるか

□ 再起動後のデータ永続化確認
  - アプリを完全終了して再起動
  - 入力したデータが残っているか
  - JSONファイルが存在し、サイズが増えているか

□ CSVインポートのログ確認
  - インポート実行時に [CSV_IMPORT] ログが出力されるか
  - added/skipped/errors が記録されるか
```

### 新規ファイル

| ファイル | 説明 |
|---------|------|
| MigrationStatus.swift | マイグレーションフラグ管理 |
| Diagnostics.swift | 診断・ロギングシステム |

### 更新ファイル

| ファイル | 更新内容 |
|---------|---------|
| KakeiboApp.swift | 起動時診断ログ呼び出し追加 |
| DataStore.swift | CSVインポート時のDiagnosticsログ追加 |
