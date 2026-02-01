import Foundation
import Combine

// MARK: - AI Classification Service

/// OpenAI APIを使用してDraftRowを分類するサービス
@MainActor
final class AIClassificationService: ObservableObject {

    static let shared = AIClassificationService()

    @Published private(set) var isClassifying = false
    @Published private(set) var progress: AIClassificationProgress?
    @Published private(set) var lastError: AIClassificationError?

    private init() {}

    // MARK: - Public API

    /// DraftRowの未分類行をAI分類する
    /// - Parameters:
    ///   - draftRows: 全DraftRow（unresolvedのみ抽出される）
    ///   - categories: 利用可能なカテゴリ一覧
    /// - Returns: 処理結果と更新情報（rowId -> categoryId）
    func classifyDraftRows(
        draftRows: [ImportDraftRow],
        categories: [(id: UUID, name: String, groupName: String?)],
        hints: [(description: String, categoryName: String, groupName: String?)] = []
    ) async -> (result: AIClassificationResult, updates: [UUID: (categoryId: UUID, reason: String)]) {

        // APIキーチェック
        guard let apiKey = KeychainStore.loadOpenAIAPIKey(), !apiKey.isEmpty else {
            let error = AIClassificationError.apiKeyNotSet
            lastError = error
            return (AIClassificationResult(
                totalProcessed: 0,
                totalConfirmed: 0,
                totalSkipped: 0,
                totalErrors: 0,
                error: error
            ), [:])
        }

        // 分類対象を抽出（unresolved かつ resolvedCategoryId == nil かつ transfer以外）
        let targetRows = draftRows.filter { row in
            row.status == .unresolved &&
            row.resolvedCategoryId == nil &&
            row.type != .transfer
        }

        guard !targetRows.isEmpty else {
            return (AIClassificationResult(
                totalProcessed: 0,
                totalConfirmed: 0,
                totalSkipped: 0,
                totalErrors: 0,
                error: nil
            ), [:])
        }

        isClassifying = true
        lastError = nil

        // バッチ分割
        let batches = targetRows.chunked(into: AIClassificationConfig.batchSize)
        let totalBatches = batches.count

        var totalProcessed = 0
        var totalConfirmed = 0
        var totalSkipped = 0
        var totalErrors = 0
        var allUpdates: [UUID: (categoryId: UUID, reason: String)] = [:]

        for (batchIndex, batchRows) in batches.enumerated() {
            // 進捗更新
            progress = AIClassificationProgress(
                currentBatch: batchIndex + 1,
                totalBatches: totalBatches,
                processedCount: totalProcessed,
                totalCount: targetRows.count,
                confirmedCount: totalConfirmed
            )

            // リクエスト用データ構築
            let items = batchRows.map { row -> AIClassificationRequestItem in
                let dateStr = formatDate(row.date)
                let direction = row.type == .income ? "in" : "out"
                return AIClassificationRequestItem(
                    id: row.id.uuidString,
                    date: dateStr,
                    amount: row.amount,
                    direction: direction,
                    description: row.description,
                    memo: row.memo.isEmpty ? nil : row.memo
                )
            }

            // API呼び出し
            let batchResult = await classifyBatch(
                items: items,
                categories: categories,
                hints: hints,
                apiKey: apiKey,
                batchRows: batchRows
            )

            switch batchResult {
            case .success(let (result, updates)):
                totalProcessed += result.processedCount
                totalConfirmed += result.confirmedCount
                totalSkipped += result.skippedCount
                totalErrors += result.errorCount
                allUpdates.merge(updates) { _, new in new }

            case .failure(let error):
                // エラー発生時は中断
                isClassifying = false
                progress = nil
                lastError = error
                return (AIClassificationResult(
                    totalProcessed: totalProcessed,
                    totalConfirmed: totalConfirmed,
                    totalSkipped: totalSkipped,
                    totalErrors: totalErrors,
                    error: error
                ), allUpdates)
            }
        }

        isClassifying = false
        progress = nil

        return (AIClassificationResult(
            totalProcessed: totalProcessed,
            totalConfirmed: totalConfirmed,
            totalSkipped: totalSkipped,
            totalErrors: totalErrors,
            error: nil
        ), allUpdates)
    }

    // MARK: - Private Methods

    private func classifyBatch(
        items: [AIClassificationRequestItem],
        categories: [(id: UUID, name: String, groupName: String?)],
        hints: [(description: String, categoryName: String, groupName: String?)],
        apiKey: String,
        batchRows: [ImportDraftRow]
    ) async -> Result<(AIClassificationBatchResult, [UUID: (categoryId: UUID, reason: String)]), AIClassificationError> {

        // リクエスト構築
        let request = AIClassificationRequestBuilder.buildRequest(
            items: items,
            categories: categories,
            hints: hints
        )

        // HTTP リクエスト実行
        let response: AIClassificationResponse
        do {
            response = try await executeRequest(request, apiKey: apiKey)
        } catch let error as AIClassificationError {
            return .failure(error)
        } catch {
            return .failure(.networkError(error))
        }

        // 結果を適用
        var confirmedCount = 0
        var skippedCount = 0
        var errorCount = 0
        var updates: [UUID: (categoryId: UUID, reason: String)] = [:]

        // ID→UUIDのマップを作成
        var idToRowId: [String: UUID] = [:]
        for row in batchRows {
            idToRowId[row.id.uuidString] = row.id
        }

        for resultItem in response.results {
            guard let rowId = idToRowId[resultItem.id] else {
                errorCount += 1
                continue
            }

            guard let categoryUUID = UUID(uuidString: resultItem.categoryId) else {
                errorCount += 1
                continue
            }

            // カテゴリが有効か確認
            guard categories.contains(where: { $0.id == categoryUUID }) else {
                errorCount += 1
                continue
            }

            // confidence チェック
            if resultItem.confidence >= AIClassificationConfig.confidenceThreshold {
                updates[rowId] = (categoryId: categoryUUID, reason: resultItem.reason)
                confirmedCount += 1
            } else {
                skippedCount += 1
            }
        }

        return .success((AIClassificationBatchResult(
            processedCount: items.count,
            confirmedCount: confirmedCount,
            skippedCount: skippedCount,
            errorCount: errorCount
        ), updates))
    }

    private func executeRequest(
        _ request: AIClassificationRequest,
        apiKey: String
    ) async throws -> AIClassificationResponse {

        guard let url = URL(string: AIClassificationConfig.apiEndpoint) else {
            throw AIClassificationError.networkError(URLError(.badURL))
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.timeoutInterval = 60

        let encoder = JSONEncoder()
        urlRequest.httpBody = try encoder.encode(request)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: urlRequest)
        } catch let urlError as URLError where urlError.code == .timedOut {
            throw AIClassificationError.timeout
        } catch {
            throw AIClassificationError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIClassificationError.networkError(URLError(.badServerResponse))
        }

        // HTTPステータスチェック
        switch httpResponse.statusCode {
        case 200...299:
            break
        case 401:
            throw AIClassificationError.unauthorized
        case 429:
            throw AIClassificationError.rateLimited
        default:
            throw AIClassificationError.httpError(statusCode: httpResponse.statusCode)
        }

        // レスポンスをパース
        let decoder = JSONDecoder()

        // まずAPIレスポンス全体をデコード
        let apiResponse: AIClassificationAPIResponse
        do {
            apiResponse = try decoder.decode(AIClassificationAPIResponse.self, from: data)
        } catch {
            let jsonString = String(data: data, encoding: .utf8) ?? "N/A"
            throw AIClassificationError.invalidJSON("APIレスポンスのデコードに失敗: \(jsonString.prefix(200))")
        }

        // エラーチェック
        if let errorResponse = apiResponse.error {
            throw AIClassificationError.parseError(errorResponse.message ?? "Unknown API error")
        }

        // outputからメッセージを探す
        guard let outputs = apiResponse.output else {
            throw AIClassificationError.emptyResponse
        }

        // type == "message" のoutputを探す
        let messageOutput = outputs.first { $0.type == "message" } ?? outputs.first
        guard let contents = messageOutput?.content else {
            throw AIClassificationError.emptyResponse
        }

        // refusalをチェック
        if let refusalContent = contents.first(where: { $0.type == "refusal" }),
           let refusalReason = refusalContent.refusal ?? refusalContent.text {
            throw AIClassificationError.refusal(refusalReason)
        }

        // output_textを探す
        guard let textContent = contents.first(where: { $0.type == "output_text" }),
              let jsonText = textContent.text else {
            throw AIClassificationError.emptyResponse
        }

        // JSONテキストをパース
        guard let jsonData = jsonText.data(using: .utf8) else {
            throw AIClassificationError.invalidJSON("JSONテキストのエンコードに失敗")
        }

        do {
            let classificationResponse = try decoder.decode(AIClassificationResponse.self, from: jsonData)
            return classificationResponse
        } catch {
            throw AIClassificationError.invalidJSON("分類結果のパースに失敗: \(error.localizedDescription)")
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

// MARK: - Array Extension for Chunking

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
