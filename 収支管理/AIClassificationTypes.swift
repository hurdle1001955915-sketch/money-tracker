import Foundation

// MARK: - AI Classification Types

/// AI分類の設定
enum AIClassificationConfig {
    /// 使用するモデル名（差し替え可能）
    static let modelName = "gpt-4o-mini"

    /// 1バッチあたりの最大件数
    static let batchSize = 25

    /// 自動確定する最低confidence
    static let confidenceThreshold: Double = 0.80

    /// OpenAI API エンドポイント（Responses API）
    static let apiEndpoint = "https://api.openai.com/v1/responses"
}

// MARK: - Request Types

/// API送信用の取引データ
struct AIClassificationRequestItem: Codable {
    let id: String           // DraftRow.id (UUID文字列)
    let date: String         // yyyy-MM-dd
    let amount: Int
    let direction: String    // "in" or "out"
    let description: String
    let memo: String?
}

/// APIリクエストボディ
struct AIClassificationRequest: Codable {
    let model: String
    let store: Bool?
    let input: [AIClassificationMessage]
    let text: AITextConfig

    struct AIClassificationMessage: Codable {
        let role: String
        let content: String
    }

    struct AITextConfig: Codable {
        let format: AITextFormat
    }

    struct AITextFormat: Codable {
        let type: String
        let name: String
        let schema: AIResponseSchema
        let strict: Bool
    }

    struct AIResponseSchema: Codable {
        let type: String
        let properties: AIResponseProperties
        let required: [String]
        let additionalProperties: Bool
    }

    struct AIResponseProperties: Codable {
        let results: AIResultsProperty
    }

    struct AIResultsProperty: Codable {
        let type: String
        let items: AIResultItemSchema
    }

    struct AIResultItemSchema: Codable {
        let type: String
        let properties: AIResultItemProperties
        let required: [String]
        let additionalProperties: Bool
    }

    struct AIResultItemProperties: Codable {
        let id: AIStringProperty
        let categoryId: AIStringProperty
        let confidence: AINumberProperty
        let reason: AIStringProperty
    }

    struct AIStringProperty: Codable {
        let type: String
    }

    struct AINumberProperty: Codable {
        let type: String
    }
}

// MARK: - Response Types

/// APIレスポンス全体
struct AIClassificationAPIResponse: Codable {
    let id: String?
    let output: [AIClassificationOutput]?
    let error: AIErrorResponse?
}

struct AIClassificationOutput: Codable {
    let type: String
    let role: String?
    let status: String?
    let content: [AIOutputContent]?
}

struct AIOutputContent: Codable {
    let type: String
    let text: String?
    let refusal: String?  // AIが回答を拒否した場合
}

struct AIErrorResponse: Codable {
    let message: String?
    let type: String?
    let code: String?
}

/// パース済みの分類結果
struct AIClassificationResponse: Codable {
    let results: [AIClassificationResultItem]
}

/// 各取引の分類結果
struct AIClassificationResultItem: Codable {
    let id: String
    let categoryId: String
    let confidence: Double
    let reason: String
}

// MARK: - Error Types

/// AI分類のエラー
enum AIClassificationError: LocalizedError {
    case apiKeyNotSet
    case networkError(Error)
    case timeout
    case httpError(statusCode: Int)
    case invalidJSON(String)
    case parseError(String)
    case emptyResponse
    case refusal(String)  // AIが回答を拒否
    case rateLimited
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .apiKeyNotSet:
            return "OpenAI APIキーが設定されていません。設定画面から登録してください。"
        case .networkError(let error):
            return "ネットワークエラー: \(error.localizedDescription)"
        case .timeout:
            return "リクエストがタイムアウトしました。再試行してください。"
        case .httpError(let statusCode):
            return "APIエラー (HTTP \(statusCode))"
        case .invalidJSON(let detail):
            return "JSONパースエラー: \(detail)"
        case .parseError(let detail):
            return "レスポンス解析エラー: \(detail)"
        case .emptyResponse:
            return "APIからの応答が空でした"
        case .refusal(let reason):
            return "AIが分類を拒否しました: \(reason)"
        case .rateLimited:
            return "APIのレート制限に達しました。しばらく待ってから再試行してください。"
        case .unauthorized:
            return "APIキーが無効です。設定画面で正しいキーを入力してください。"
        }
    }
}

// MARK: - Progress Types

/// バッチ処理の進捗
struct AIClassificationProgress {
    let currentBatch: Int
    let totalBatches: Int
    let processedCount: Int
    let totalCount: Int
    let confirmedCount: Int  // confidence >= threshold で確定した件数

    var progressRatio: Double {
        guard totalCount > 0 else { return 0 }
        return Double(processedCount) / Double(totalCount)
    }

    var displayText: String {
        "処理中... (\(currentBatch)/\(totalBatches)バッチ)"
    }
}

/// バッチ処理の結果
struct AIClassificationBatchResult {
    let processedCount: Int
    let confirmedCount: Int
    let skippedCount: Int  // confidence不足でスキップ
    let errorCount: Int    // UUID変換失敗など
}

/// 全体の処理結果
struct AIClassificationResult {
    let totalProcessed: Int
    let totalConfirmed: Int
    let totalSkipped: Int
    let totalErrors: Int
    let error: AIClassificationError?

    var isSuccess: Bool {
        return error == nil
    }

    var summaryText: String {
        if let error = error {
            return "エラー: \(error.localizedDescription)"
        }
        return "AI分類完了: \(totalConfirmed)件を自動分類しました"
    }
}

// MARK: - Request Builder

/// APIリクエストを構築するヘルパー
enum AIClassificationRequestBuilder {

    /// Structured Outputsのスキーマを含むリクエストボディを構築
    static func buildRequest(
        items: [AIClassificationRequestItem],
        categories: [(id: UUID, name: String, groupName: String?)],
        hints: [(description: String, categoryName: String, groupName: String?)] = []
    ) -> AIClassificationRequest {

        // カテゴリ一覧をテキスト化（階層構造を表示）
        let categoryList = categories.map { cat in
            let groupPrefix = cat.groupName != nil ? "[\(cat.groupName!)] " : ""
            return "- \(groupPrefix)\(cat.name): \(cat.id.uuidString)"
        }.joined(separator: "\n")

        // システムプロンプト
        let systemPrompt = """
あなたは家計簿アプリのカテゴリ分類器です。
与えられた取引ごとに、下の「カテゴリ候補」から最適な1つを選び、結果をJSONスキーマ通りに返してください。

制約（厳守）:
- categoryId は必ず「カテゴリ候補」に存在するUUIDのみ
- confidence は 0.0〜1.0
- confidence >= 0.80 のときだけ「自信あり」。それ未満は自信が低い前提で付ける
- reason は日本語で1〜2文、根拠を簡潔に（店舗/用途/文脈）
- 出力は必ず指定スキーマのみ（余計な文章は禁止）

カテゴリ候補:
\(categoryList)

\(hints.isEmpty ? "" : "過去の分類例（ヒント、最大20件）:\n" + hints.map { "- [\( $0.groupName ?? "未分類")] \($0.categoryName): \($0.description)" }.joined(separator: "\n") + "\n")
"""

        // ユーザープロンプト（取引データ）
        let transactionsJSON: String
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(items)
            transactionsJSON = String(data: data, encoding: .utf8) ?? "[]"
        } catch {
            transactionsJSON = "[]"
        }

        let userPrompt = """
以下の取引を分類してください（最大\(items.count)件）。
{ "transactions": \(transactionsJSON) }
"""

        // Structured Outputsスキーマ
        let schema = AIClassificationRequest.AIResponseSchema(
            type: "object",
            properties: AIClassificationRequest.AIResponseProperties(
                results: AIClassificationRequest.AIResultsProperty(
                    type: "array",
                    items: AIClassificationRequest.AIResultItemSchema(
                        type: "object",
                        properties: AIClassificationRequest.AIResultItemProperties(
                            id: AIClassificationRequest.AIStringProperty(type: "string"),
                            categoryId: AIClassificationRequest.AIStringProperty(type: "string"),
                            confidence: AIClassificationRequest.AINumberProperty(type: "number"),
                            reason: AIClassificationRequest.AIStringProperty(type: "string")
                        ),
                        required: ["id", "categoryId", "confidence", "reason"],
                        additionalProperties: false
                    )
                )
            ),
            required: ["results"],
            additionalProperties: false
        )

        return AIClassificationRequest(
            model: AIClassificationConfig.modelName,
            store: false,
            input: [
                AIClassificationRequest.AIClassificationMessage(role: "system", content: systemPrompt),
                AIClassificationRequest.AIClassificationMessage(role: "user", content: userPrompt)
            ],
            text: AIClassificationRequest.AITextConfig(
                format: AIClassificationRequest.AITextFormat(
                    type: "json_schema",
                    name: "classification_response",
                    schema: schema,
                    strict: true
                )
            )
        )
    }
}
