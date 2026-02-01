# Phase4: 基本UX監査（検索・一覧・編集・削除）

## 実行日時

- 実行日: 2026-01-23
- 目的: 日常運用で最も触る基本UX（検索、一覧、編集、削除、フィルタ）に関して、現状の仕様・挙動を根拠付きで確定し、欠陥/機能不足/形骸化を洗い出し、改善案を優先度付きで提示すること。

---

## 1. 現状の仕様・挙動

### 1.1 検索 (Search)

- **関連ファイル**: `TransactionSearchView.swift`, `DataStore.swift`
- **検索ロジック**:
  - `DataStore.searchTransactions` メソッドで実行
  - **キーワード検索対象**: `memo` (メモ), `categoryName` (カテゴリ名) のみ
  - **マッチング**: スペース区切りでAND検索、正規化（全角半角/大文字小文字無視）あり
  - **フィルタ条件**: 期間（開始〜終了）、種類（収入/支出）、カテゴリ（単一選択）、金額範囲（最小〜最大）
- **表示**:
  - 日付降順（`date >`）で固定
  - 表示項目: 日付、カテゴリ名、金額、メモ

### 1.2 一覧 (List)

- **関連ファイル**: `CalendarView.swift`, `DayDetailView.swift`
- **表示ロジック**:
  - カレンダー: 月ごとの取引を取得し、日ごとに集計して表示（42マス固定グリッド）
  - 日次詳細: 選択した日付の取引一覧を表示。並び順は `settings.sameDaySortOrder` で設定可能（作成順/金額順）
- **操作**:
  - スワイプで削除（論理削除ではない）、複製
  - タップで編集、ダブルタップ（カレンダー）で新規作成

### 1.3 編集/詳細 (Edit)

- **関連ファイル**: `InputView.swift`, `TransactionInputView.swift`
- **データフロー**:
  - 編集モード時は既存の `Transaction` オブジェクトのコピーをStateに展開
  - 保存時に `updateTransaction` を呼び出し（ID維持）
  - カテゴリ変更時、ルール学習機能が動作 (`ClassificationRulesStore.learn`)
- **バリデーション**:
  - 金額が1以上であること
  - カテゴリは必須（空の場合はデフォルトまたは先頭を選択）

### 1.4 削除 (Delete)

- **関連ファイル**: `DeletionManager.swift`, `DataStore.swift`
- **削除ロジック**:
  - 「即時削除 ＋ Undo可能期間（6秒）」方式
  - `DataStore` からは即座に削除される（メモリ＆永続化領域から消える）
  - `DeletionManager` が削除されたオブジェクトをメモリ上に一時保持し、Undo時に `addTransaction` で復元
  - 復元時は `id` を維持したまま再登録される（`DataStore.addTransaction` 実装依存だが、StructコピーなのでID維持される）

---

## 2. 欠陥・不足一覧

| ID | 重大度 | 種別 | 症状/不足機能 | 根拠コード/現状 | 改善案 | テスト観点 |
|---|---|---|---|---|---|---|
| **UX-001** | **Major** | 機能不足 | 金額や日付でのキーワード検索ができない | `DataStore.swift:665`<br>`memo.contains` と `catName.contains` のみ判定 | キーワード検索対象に `amount` (文字列化) と `date` (yyyy/MM/dd) を追加する | "1000" で検索して1000円の取引がヒットするか |
| **UX-002** | **Minor** | UX | 検索結果の並び順が変更できない（日付降順固定） | `DataStore.swift:698`<br>`.sorted { $0.date > $1.date }` で固定 | 検索画面右上にソート順変更メニューを追加（金額順、作成順） | 金額順でソートできるか |
| **UX-003** | **Major** | UX/Data | アプリ強制終了時にUndo期間中の削除データが消失する | `DeletionManager.swift:61`<br>`dataStore.deleteTransaction(tx)` で即物理削除 | **論理削除 (isDeletedフラグ)** を導入し、Undo期間終了後に物理削除、または「ゴミ箱」機能を実装 | 削除後即アプリ終了し、再起動後にデータが消えていること確認 |
| **UX-004** | **Minor** | UX | 金額入力フィールドで計算式が使えない | `InputView.swift:450`<br>`Int(trimmed)` でパースしており、数式不可 | 電卓ボタン(`CalculatorInputView`)へ誘導するか、数式パーサーを導入 (`100+200` 等) | "100+50" と入力して保存できるか |
| **UX-005** | **Minor** | 機能不足 | 検索フィルタで「カテゴリなし（未分類）」のみを抽出できない | `TransactionSearchView.swift:350`<br>カテゴリ選択が `UUID?` であり、`nil` は「すべて」扱い | カテゴリ選択肢に「未分類」(nil) を明示的に追加 | 未分類を選択して絞り込めるか |
| **UX-006** | **Minor** | UX | 検索履歴（最近の検索）機能がない | `TransactionSearchView.swift`<br>履歴機能の実装なし | 直近5件程度の検索条件/ワードを保存し、検索画面初期表示時に提示 | 検索後に履歴が残るか |
| **UX-007** | **Minor** | UI | カレンダーの日付詳細リストが0件の時、表示が寂しい | `DayDetailView.swift:34`<br>単にテキスト「取引がありません」のみ | イラストや「＋ボタンで追加」などの誘導を表示 | 0件の日の表示確認 |
| **UX-008** | **Major** | 機能不足 | グラフ画面でのフィルタ機能が貧弱（期間指定不可） | `GraphView.swift`<br>月単位の移動のみで、任意の期間（例: 1/15〜2/15）集計が不可 | 検索画面同様のフィルタ機能をグラフ画面にも導入、または検索結果からグラフ表示へ遷移可能に | 任意期間でグラフが見れるか |
| **UX-009** | **Minor** | 機能不足 | 除外検索（マイナス検索）ができない | `DataStore.swift:660`<br>単なる `split` と `contains` のみ | 先頭 `-` で除外条件とするロジックを追加 | "食費 -コンビニ" で検索できるか |
| **UX-010** | **Minor** | UX | 詳細画面(`DayDetailView`)からカレンダーに戻る際、スクロール位置が保持されない可能性 | `CalendarView.swift`<br>NavigationViewの標準挙動依存 | `ScrollViewReader` を導入し、選択していた日付までスクロール復帰させる | 詳細から戻った時の位置確認 |

---

## 3. 改善および修正方針（優先度順）

### Phase 4.1: 検索機能の強化 (UX-001, UX-005, UX-009)

最も利用頻度が高い検索機能の実用性を向上させる。

- **検索対象拡充**: 金額文字列も含める。
- **未分類フィルタ**: フィルタUIのPickerに `.tag(UUID?.some(nil))` 相当の選択肢を追加（実装要検討）。
- **ロジック改良**: DataStoreの検索ロジックを修正。

### Phase 4.2: 削除の安全性向上 (UX-003)

データ消失リスクを軽減する。

- **論理削除の導入**: `Transactions` モデルに `isDeleted` フラグを追加（スキーマ変更伴うため慎重に）。Phase 8等の大規模改修で実施推奨。暫定としてUndo期間中の物理削除は維持しつつ、警告を強める等のUI対応を行う。

### Phase 4.3: 一覧・詳細のUX改善 (UX-002, UX-007, UX-004)

- **ソート機能**: 検索画面にソートボタン配置。
- **計算入力**: 入力フィールドのUX改善。

---

## 4. 実行したログ・参照ファイル

- `Docs/Audit/Logs/feature_grep.txt`
- `TransactionSearchView.swift`
- `CalendarView.swift`
- `DataStore.swift`
- `InputView.swift`
- `DeletionManager.swift`
