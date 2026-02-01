# Phase6: カテゴリ/ルール/マイグレーション 監査

## 実行日時

- 実行日: 2026-01-23
- 目的: カテゴリ体系・ID参照・未分類・ルール適用順序・後方互換（移行）の健全性を監査し、データ汚染を防ぐ。

---

## 1. 現状の仕様と実装根拠

### 1.1 カテゴリモデル (Category)

- **IDベースへの移行**: 旧来の`String`名ベースから`UUID`ベース（`categoryId`）へ移行中。
- **階層構造**: `CategoryGroup` (大分類) と `CategoryItem` (中分類) の2階層。`CategoryItem` が `groupId` を持ち、実質的なカテゴリ（取引が紐づく先）として機能する。
- **互換性**: `CategoryItem` は `.toCategory()` メソッドで旧 `Category` 構造体へ変換可能。

### 1.2 分類ルール (ClassificationRule)

- **保存**: `UserDefaults` (`classification_rules_v1`) にJSON配列として保存。SwiftDataには移行されていない（監査時点）。
- **ID対応**: `targetCategoryId` を持ち、IDベースのマッチングを優先。`targetCategoryName` はバックアップ/移行用。
- **適用ロジック**: 優先度(`priority`)順に評価し、最初にマッチ(`matches()`)したものを適用。`targetCategoryId` が `nil` の場合、警告ログが出る（実装上の不備）。

### 1.3 マイグレーション (Migration)

- **フロー**: `DataMigration.migrateIfNeeded` で起動時に1回だけ実行。JSONファイルからSwiftDataへデータをコピーし、重複をIDで排除。
- **カテゴリID移行**: `DataStore.performCategoryIdMigration` にて、取引データの旧カテゴリ名(`originalCategoryName`)からID(`categoryId`)への解決を試みる。解決できない場合は `nil` (未分類) となる。

---

## 2. データ汚染リスク（10選）

| ID | リスクレベル | リスク内容 | 根拠・コード |
|---|---|---|---|
| **CR-001** | **Critical** | カテゴリID解決不可による未分類化 | `DataStore.swift:57`<br>マイグレーション時に名前が不一致（例: スペース有無）だと `categoryId` が埋まらず、過去データが大量に「未分類」になる。 |
| **CR-002** | **High** | ルール適用時のID参照切れ | `ClassificationRulesStore.swift:206`<br>ルールの `targetCategoryId` が指すカテゴリが削除された場合、自動適用された取引が「存在しないカテゴリID」を持つことになり、グラフ等で非表示になる。 |
| **CR-003** | **Medium** | ルール学習の競合 | `ClassificationRulesStore.swift:255`<br>既存ルールとの重複チェックが「完全一致」のみ。包含関係（例: "Amazon" と "Amazon JP"）を考慮せず、矛盾するルールが複数登録される可能性がある。 |
| **CR-004** | **Medium** | デフォルトルールのカテゴリID未解決 | `ClassificationRulesStore.swift:420`<br>デフォルトルール生成時、カテゴリマスタがまだロードされていない、あるいは名前が変わっていると、ルール生成に失敗するか `targetCategoryId=nil` の不正ルールが作られる。 |
| **CR-005** | **Low** | マイグレーションの不可逆性 | `MigrationStatus.swift`<br>一度 `needsMigration` が false になると、JSON側に未取り込みデータがあっても二度と読まれない。アプリ再インストール後のiCloud同期との競合リスク。 |
| **CR-006** | **Low** | カテゴリ並び替えの不整合 | `CategoryItem` の `order` は配列インデックス依存の場合があり、削除・追加を繰り返すと `order` が重複し、表示順が不安定になる。 |
| **CR-007** | **Medium** | 旧データの文字列揺らぎ | `TextNormalizer.normalize` は強力だが、移行ロジック(`DataStore.migrateTransactionCategoryIds`)では `findCategory` (完全一致) を使用しており、正規化されていない旧データがマッチしない。 |
| **CR-008** | **Low** | ルールの保存先不整合 | カテゴリや取引はSwiftDataへ移行済みだが、ルールだけ `UserDefaults` に残っており、バックアップ/復元時に整合性が取れなくなる恐れがある。 |
| **CR-009** | **Low** | 循環参照・デッドリンク | 振替などでの口座ID参照と同様、カテゴリグループ削除時に項目(`CategoryItem`)が削除されず、`groupId` が無効な項目が残る（孤立レコード）。 |
| **CR-010** | **Low** | SwiftData競合 | バックグラウンド同期とUI操作が重なった際、`context.save()` のタイミング次第でカテゴリ変更が巻き戻る可能性がある（Lock機構なし）。 |

---

## 3. 改善案（安全性順）

### 3.1 参照整合性の確保 (CR-002, CR-009)

**外部キー制約の模擬**

- カテゴリ削除処理 (`deleteCategory`) で、それを参照している「取引」「ルール」「固定費テンプレート」を全検索し、`nil` または「その他」カテゴリIDに付け替える処理をトランザクション的に実行する。

### 3.2 マイグレーションの堅牢化 (CR-001, CR-007)

**正規化マッチングの導入**

- `migrateTransactionCategoryIds` において、カテゴリ名検索時に `TextNormalizer` を通した緩いマッチング（あいまい検索）を導入し、救済率を上げる。

### 3.3 ルールのSwiftData化 (CR-008)

**保存先の一元化**

- `ClassificationRule` もSwiftData (`@Model`) に移行し、iCloud同期やバックアップの仕組みに乗せる。これにより、機種変更時のルール消失リスクもなくなる。

### 3.4 監査ログの強化

**未分類データの定期レポート**

- 起動時に `categoryId == nil` の取引数をカウントし、一定数以上あればユーザーに「カテゴリ整理」を促すアラートを出す機能（`Diagnostics` 経由）。
