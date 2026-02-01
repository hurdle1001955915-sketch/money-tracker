# 実装途中・未使用機能 監査レポート

## A. サマリ

- **実装途中の件数**: 約 8 件
- **重大度別統計**:
  - **Blocker**: 0 件
  - **Critical**: 1 件 (iCloud同期の無効化)
  - **Major**: 3 件 (Diagnosticsプレースホルダ、DataStoreの肥大化、重複ロジックの散見)
  - **Minor**: 4 件 (UIバランス用のダミー、空の辞書初期化、デバッグ用ログの残存)

### 影響が大きい機能トップ5

1. **iCloud同期 (AppFeatureFlags)**: コードは存在するがフラグで完全に閉じられている。
2. **診断システム (Diagnostics)**: SwiftDataの統計取得がプレースホルダのみ。
3. **データ永続化の二重管理 (DataStore)**: SwiftDataへの移行途中であり、JSONとSwiftDataのロジックが混在。
4. **レシートOCR解析 (ReceiptParser)**: 精度向上や特定項目の抽出が「TODO」段階。
5. **UIハンドラの空実装 (SettingsView)**: アラートのキャンセルボタン等が空クロージャ。

---

## B. 実装途中リスト

| ID | 重大度 | 種別 | 症状 | 根拠 | 到達経路 | 期待仕様 | 修正方針 | テスト観点 |
|:---|:---|:---|:---|:---|:---|:---|:---|:---|
| AF-001 | Critical | 設定未反映 | iCloud同期が機能しない。 | `AppFeatureFlags.swift:8` | 設定 > iCloud同期 | 複数デバイス間のデータ同期。 | 開発チームの課金/設定後、フラグをONにする。 | 別端末での同期確認。 |
| AF-002 | Major | 仮実装 | DiagnosticsのSwiftData集計が未実装。 | `Diagnostics.swift:64` | アプリ起動(デバッグ環境) | SwiftDataモデルの総数を正確にログ出力する。 | ModelContext.fetchCountで実数を取得。 | ログ出力の確認。 |
| AF-003 | Major | 永続化不完全 | JSONとSwiftDataのハイブリッド状態。 | `DataStore.swift:1624` | 全データ操作時 | SwiftDataを正本とし、JSONを完全廃止する。 | JSONロード・保存コードを完全に除去。 | 再起動後のデータ維持確認。 |
| AF-004 | Major | 例外未実装 | ReceiptParserのOCRエラー処理が簡易的。 | `ReceiptParser.swift` TODO | 入力 > レシート | 読み取り失敗時の詳細な原因提示。 | Vision APIのエラーをキャッチしてユーザーに通知。 | ぼけた画像などでの挙動確認。 |
| AF-005 | Minor | 未接続 | UIバランスのためのダミー要素。 | `HierarchicalCategoryPicker.swift:78` | カテゴリ選択画面 | 左右対称のレイアウト維持。 | 削除OK（Spacer等の変更で対応可能）。 | レイアウト崩れの確認。 |
| AF-006 | Minor | 仮実装 | 空の初期値（`return []`）が多く存在する。 | `stub_returns.txt` ログ参照 | ロジック内部 | データの不備がある場合に安全にフォールバック。 | 正常系が既に実装済みなら、これらは適切なエラーハンドリング。 | 境界値テスト。 |
| AF-007 | Minor | 未使用 | `TransactionTypes` 等の古い構造体。 | `AppTheme.swift` 内部 | N/A | 共通定数としての利用。 | `AppStrings` へ統一・統合。 | 参照なし確認。 |
| AF-008 | Major | 例外未実装 | CSVパース時の極端な例外系。 | `ImportDraftTypes.swift:558` | CSVインポート | 不正なフォーマットのCSVを完全に拒絶。 | エラーメッセージの具体化。 | 壊れたCSVでの動作確認。 |

---

## C. “未使用/削除候補”棚卸し

- **削除OK**:
  - `AppTheme.swift` の一部の定数（`FontSize` 等のレガシー用）。
  - `DataStore.swift` 内の古いJSON保存関連のメソッド（SwiftData移行が安定している場合）。
- **残すべき**:
  - `KakeiboShortcuts`: 現在活用されていなくても、Siri対応として重要。
  - `Diagnostics.swift`: 今後の不具合調査に必須。
- **要確認**:
  - `TransferCandidateDetector` 内のコンビニキーワードの網羅性。

---

## D. 次アクション提案

1. **R1 (安定化)**:
   - `AF-003`: SwiftDataへの完全移行とJSONコードのクリーンアップ。
   - `AF-002`: Diagnosticsのカウント機能を正式実装。
2. **R2 (UX改善)**:
   - `AF-004`: ReceiptParserのエラーハンドリングを強化。
   - `AF-008`: CSV読み込みエラー時の詳細表示。
3. **R3 (将来課題)**:
   - `AF-001`: iCloud同期の有効化（環境面が整い次第）。
   - `AF-007`: レガシー定数の削除とリファクタ。
