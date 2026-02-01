# AI分類機能 実装後監査レポート

## 調査日時

2026-01-25

## 調査対象ファイル

| ファイル | 確認結果 |
|---------|---------|
| AIClassificationService.swift | ✅ 問題なし |
| AIClassificationTypes.swift | ⚠️ P2-1修正済み |
| KeychainStore.swift | ✅ 問題なし |
| ImportDraftTypes.swift | ⚠️ P0-1, P1-2修正済み |
| CSVImportWizardView.swift | ⚠️ P1-1修正済み |
| SettingsView.swift | ✅ 問題なし |

---

## 残タスク一覧

### P0: 必須修正（修正済み）

#### P0-1: `canPerformAIClassification` 条件の不整合

**問題**: 条件が `unresolvedCount > 0` のみで、transfer型やresolvedCategoryId設定済みを考慮していなかった

**修正箇所**: [ImportDraftTypes.swift L848-852](file:///Users/shotaroihara/Library/Mobile%20Documents/com~apple~CloudDocs/アプリ開発/収支管理/収支管理/ImportDraftTypes.swift#L848-852)

```diff
 var canPerformAIClassification: Bool {
-    unresolvedCount > 0 && !isAIClassifying
+    aiClassificationTargetCount > 0 && !isAIClassifying
 }
```

---

### P1: 保守負債（修正済み）

#### P1-1: UI進捗参照の混在

**問題**: UIが`AIClassificationService.shared.progress`を直参照していたが、`state.aiClassificationProgress`は未使用

**修正箇所**: [CSVImportWizardView.swift L965](file:///Users/shotaroihara/Library/Mobile%20Documents/com~apple~CloudDocs/アプリ開発/収支管理/収支管理/CSVImportWizardView.swift#L965)

```diff
-if let progress = AIClassificationService.shared.progress {
+if let progress = state.aiClassificationProgress {
```

#### P1-2: progress同期処理の追加

**修正箇所**: [ImportDraftTypes.swift L889-896](file:///Users/shotaroihara/Library/Mobile%20Documents/com~apple~CloudDocs/アプリ開発/収支管理/収支管理/ImportDraftTypes.swift#L889-896)

```swift
// service.progressをstate.aiClassificationProgressに反映するための購読
var cancellable: AnyCancellable?
cancellable = service.$progress
    .receive(on: DispatchQueue.main)
    .sink { [weak self] progress in
        self?.aiClassificationProgress = progress
    }
```

---

### P2: 軽微な修正（修正済み）

#### P2-1: モデル名の修正

**問題**: `gpt-4.1-mini`は存在しないモデル名

**修正箇所**: [AIClassificationTypes.swift L8](file:///Users/shotaroihara/Library/Mobile%20Documents/com~apple~CloudDocs/アプリ開発/収支管理/収支管理/AIClassificationTypes.swift#L8)

```diff
-static let modelName = "gpt-4.1-mini"
+static let modelName = "gpt-4o-mini"
```

---

## 確認済み（問題なし）

### A) Responses APIレスポンス取り出し（追加修正済み）

[AIClassificationService.swift L267-295](file:///Users/shotaroihara/Library/Mobile%20Documents/com~apple~CloudDocs/アプリ開発/収支管理/収支管理/AIClassificationService.swift#L267-L295) で適切に実装済み:

1. `AIClassificationAPIResponse`でAPI全体をデコード
2. `type == "message"` のoutputを優先的に探索
3. `type == "refusal"` をチェックし、拒否応答を適切に処理
4. `type == "output_text"` のcontentからJSONテキストを取得
5. JSONパースして`AIClassificationResponse`を取得

**追加修正（2026-01-25）:**
- `AIClassificationOutput`に`role`, `status`フィールド追加
- `AIOutputContent`に`refusal`フィールド追加
- refusal応答のハンドリング追加

### D) エラーハンドリング（追加修正済み）

[AIClassificationService.swift L232-248](file:///Users/shotaroihara/Library/Mobile%20Documents/com~apple~CloudDocs/アプリ開発/収支管理/収支管理/AIClassificationService.swift#L232-L248):

- 401: `.unauthorized` (キー無効)
- 429: `.rateLimited` (レート制限)
- 5xx: `.httpError(statusCode:)` (サーバーエラー)
- タイムアウト: `.timeout` (60秒経過) ← **今回追加**
- JSON不正: `.invalidJSON()`
- 拒否応答: `.refusal(reason)` ← **今回追加**

バッチ処理中のエラー時は「確定済み分は残して中断」方針

---

## ビルド確認

```
xcodebuild -project 収支管理.xcodeproj -scheme 収支管理 -destination 'platform=iOS Simulator,name=iPhone 17' build
```

**結果**: `** BUILD SUCCEEDED **`

---

## 動作確認手順（手動）

### 1. APIキー未設定時のアラート

1. 設定 > AI機能 > OpenAI APIキー でキーを削除
2. CSVインポート > 未分類タブ > AI補完ボタンをタップ
3. **期待**: 「APIキーが未設定」アラート表示

### 2. AI補完ボタンの有効/無効条件

- 未分類が0件の場合: ボタンがグレーアウト
- 未分類があるが全てtransfer型の場合: ボタンがグレーアウト ← **今回修正**
- 未分類があってtransfer以外がある場合: ボタンが有効

### 3. バッチ分割確認（26件以上）

1. 26件以上の未分類行を含むCSVをインポート
2. AI補完を実行
3. **期待**: 進捗が「(1/2バッチ)」等と表示

### 4. エラーケース

1. 無効なAPIキーを設定
2. AI補完を実行
3. **期待**: 「APIキーが無効です」エラー表示
