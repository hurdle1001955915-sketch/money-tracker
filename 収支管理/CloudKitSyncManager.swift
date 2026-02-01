import Foundation
import CloudKit
import Combine

/// CloudKitを使用したiCloud同期マネージャー
@MainActor
final class CloudKitSyncManager: ObservableObject {
    static let shared = CloudKitSyncManager()

    private var container: CKContainer? {
        guard AppFeatureFlags.cloudSyncEnabled else { return nil }
        return CKContainer.default()
    }
    private var database: CKDatabase? { container?.privateCloudDatabase }

    // Record Types
    private let transactionRecordType = "Transaction"

    // Published properties
    @Published private(set) var isSyncing = false
    @Published private(set) var lastSyncDate: Date?
    @Published private(set) var syncError: String?
    @Published private(set) var iCloudAvailable = false
    @Published var syncEnabled = false {
        didSet {
            UserDefaults.standard.set(syncEnabled, forKey: syncEnabledKey)
        }
    }

    private let syncEnabledKey = "icloud_sync_enabled"
    private let lastSyncKey = "icloud_last_sync_date"

    private var subscriptionSaved = false

    private init() {
        // Feature flagが無効の場合は初期化をスキップ
        guard AppFeatureFlags.cloudSyncEnabled else {
            syncEnabled = false
            iCloudAvailable = false
            return
        }

        syncEnabled = UserDefaults.standard.bool(forKey: syncEnabledKey)
        if let date = UserDefaults.standard.object(forKey: lastSyncKey) as? Date {
            lastSyncDate = date
        }
        Task {
            await checkiCloudStatus()
        }
    }

    // MARK: - iCloud Status

    /// iCloudアカウントの状態を確認
    func checkiCloudStatus() async {
        guard AppFeatureFlags.cloudSyncEnabled else {
            iCloudAvailable = false
            return
        }

        do {
            guard let container = container else { return }
            let status = try await container.accountStatus()
            iCloudAvailable = (status == .available)
            if !iCloudAvailable {
                syncError = statusiCloudMessage(status)
            } else {
                syncError = nil
            }
        } catch {
            iCloudAvailable = false
            syncError = "iCloud状態の確認に失敗: \(error.localizedDescription)"
        }
    }

    private func statusiCloudMessage(_ status: CKAccountStatus) -> String {
        switch status {
        case .available:
            return ""
        case .noAccount:
            return "iCloudアカウントにサインインしていません"
        case .restricted:
            return "iCloudが制限されています"
        case .couldNotDetermine:
            return "iCloud状態を確認できません"
        case .temporarilyUnavailable:
            return "iCloudが一時的に利用できません"
        @unknown default:
            return "不明なiCloud状態"
        }
    }

    // MARK: - Upload Transaction

    /// 単一の取引をCloudKitにアップロード
    func uploadTransaction(_ tx: Transaction) async throws {
        guard AppFeatureFlags.cloudSyncEnabled else { return }
        guard syncEnabled && iCloudAvailable else { return }

        let record = transactionToRecord(tx)
        _ = try await database?.save(record)
    }

    /// 複数の取引をCloudKitにアップロード
    func uploadTransactions(_ transactions: [Transaction]) async throws {
        guard AppFeatureFlags.cloudSyncEnabled else { return }
        guard syncEnabled && iCloudAvailable else { return }
        guard !transactions.isEmpty else { return }

        let records = transactions.map { transactionToRecord($0) }

        // バッチ処理（CloudKitは一度に400件まで）
        let batchSize = 400
        for i in stride(from: 0, to: records.count, by: batchSize) {
            let batch = Array(records[i..<min(i + batchSize, records.count)])
            let operation = CKModifyRecordsOperation(recordsToSave: batch, recordIDsToDelete: nil)
            operation.savePolicy = .changedKeys

            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                operation.modifyRecordsResultBlock = { result in
                    switch result {
                    case .success:
                        continuation.resume()
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
                database?.add(operation)
            }
        }
    }

    // MARK: - Delete Transaction

    /// 取引をCloudKitから削除
    func deleteTransaction(_ tx: Transaction) async throws {
        guard AppFeatureFlags.cloudSyncEnabled else { return }
        guard syncEnabled && iCloudAvailable else { return }

        let recordID = CKRecord.ID(recordName: tx.id.uuidString)
        try await database?.deleteRecord(withID: recordID)
    }

    /// 複数の取引をCloudKitから削除
    func deleteTransactions(ids: [UUID]) async throws {
        guard AppFeatureFlags.cloudSyncEnabled else { return }
        guard syncEnabled && iCloudAvailable else { return }
        guard !ids.isEmpty else { return }

        let recordIDs = ids.map { CKRecord.ID(recordName: $0.uuidString) }

        let batchSize = 400
        for i in stride(from: 0, to: recordIDs.count, by: batchSize) {
            let batch = Array(recordIDs[i..<min(i + batchSize, recordIDs.count)])
            let operation = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: batch)

            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                operation.modifyRecordsResultBlock = { result in
                    switch result {
                    case .success:
                        continuation.resume()
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
                database?.add(operation)
            }
        }
    }

    // MARK: - Fetch All Transactions

    /// CloudKitから全ての取引を取得
    func fetchAllTransactions() async throws -> [Transaction] {
        guard AppFeatureFlags.cloudSyncEnabled else { return [] }
        guard iCloudAvailable else { return [] }

        var allTransactions: [Transaction] = []
        var cursor: CKQueryOperation.Cursor?

        repeat {
            let (transactions, nextCursor) = try await fetchTransactionsBatch(cursor: cursor)
            allTransactions.append(contentsOf: transactions)
            cursor = nextCursor
        } while cursor != nil

        return allTransactions
    }

    private func fetchTransactionsBatch(cursor: CKQueryOperation.Cursor?) async throws -> ([Transaction], CKQueryOperation.Cursor?) {
        return try await withCheckedThrowingContinuation { continuation in
            var fetchedTransactions: [Transaction] = []
            var nextCursor: CKQueryOperation.Cursor?

            let operation: CKQueryOperation
            if let cursor = cursor {
                operation = CKQueryOperation(cursor: cursor)
            } else {
                let query = CKQuery(recordType: transactionRecordType, predicate: NSPredicate(value: true))
                query.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
                operation = CKQueryOperation(query: query)
            }

            operation.resultsLimit = 200

            operation.recordMatchedBlock = { _, result in
                switch result {
                case .success(let record):
                    if let tx = self.recordToTransaction(record) {
                        fetchedTransactions.append(tx)
                    }
                case .failure:
                    break
                }
            }

            operation.queryResultBlock = { result in
                switch result {
                case .success(let cursor):
                    nextCursor = cursor
                    continuation.resume(returning: (fetchedTransactions, nextCursor))
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }

            database?.add(operation)
        }
    }

    // MARK: - Full Sync

    /// ローカルとCloudKitの完全同期
    func performFullSync(localTransactions: [Transaction]) async throws -> [Transaction] {
        guard AppFeatureFlags.cloudSyncEnabled else { return localTransactions }
        guard syncEnabled && iCloudAvailable else { return localTransactions }

        isSyncing = true
        syncError = nil

        defer {
            isSyncing = false
            lastSyncDate = Date()
            UserDefaults.standard.set(lastSyncDate, forKey: lastSyncKey)
        }

        do {
            // CloudKitから取得
            let cloudTransactions = try await fetchAllTransactions()

            // マージ処理
            let merged = mergeTransactions(local: localTransactions, cloud: cloudTransactions)

            // ローカルのみにある取引をアップロード
            let localOnly = localTransactions.filter { local in
                !cloudTransactions.contains(where: { $0.id == local.id })
            }
            if !localOnly.isEmpty {
                try await uploadTransactions(localOnly)
            }

            return merged
        } catch {
            syncError = "同期エラー: \(error.localizedDescription)"
            throw error
        }
    }

    /// マージ処理: より新しいデータを優先
    private func mergeTransactions(local: [Transaction], cloud: [Transaction]) -> [Transaction] {
        var result: [UUID: Transaction] = [:]

        // ローカルデータを追加
        for tx in local {
            result[tx.id] = tx
        }

        // クラウドデータをマージ（より新しい更新日のものを優先）
        for cloudTx in cloud {
            if let localTx = result[cloudTx.id] {
                // 更新日が新しい方を採用
                if cloudTx.createdAt > localTx.createdAt {
                    result[cloudTx.id] = cloudTx
                }
            } else {
                // ローカルにない場合は追加
                result[cloudTx.id] = cloudTx
            }
        }

        return Array(result.values)
    }

    // MARK: - Record Conversion

    private func transactionToRecord(_ tx: Transaction) -> CKRecord {
        let recordID = CKRecord.ID(recordName: tx.id.uuidString)
        let record = CKRecord(recordType: transactionRecordType, recordID: recordID)

        record["id"] = tx.id.uuidString
        record["date"] = tx.date
        record["type"] = tx.type.rawValue
        record["amount"] = tx.amount
        
        // ID Based Category
        if let catId = tx.categoryId {
            record["categoryId"] = catId.uuidString
            // Backward compatibility: store resolved name in 'category'
            record["category"] = DataStore.shared.categoryName(for: catId)
        } else {
            // No ID? use original name or Unknown
            let name = tx.originalCategoryName ?? "未分類"
            record["category"] = name
            if let original = tx.originalCategoryName {
                record["originalCategoryName"] = original
            }
        }
        
        record["memo"] = tx.memo
        record["isRecurring"] = tx.isRecurring ? 1 : 0
        record["createdAt"] = tx.createdAt

        if let templateId = tx.templateId {
            record["templateId"] = templateId.uuidString
        }
        if let accountId = tx.accountId {
            record["accountId"] = accountId.uuidString
        }
        if let toAccountId = tx.toAccountId {
            record["toAccountId"] = toAccountId.uuidString
        }
        if let source = tx.source {
            record["source"] = source
        }
        if let sourceId = tx.sourceId {
            record["sourceId"] = sourceId
        }
        if let parentId = tx.parentId {
            record["parentId"] = parentId.uuidString
        }
        record["isSplit"] = tx.isSplit ? 1 : 0
        record["isDeleted"] = tx.isDeleted ? 1 : 0

        return record
    }

    private func recordToTransaction(_ record: CKRecord) -> Transaction? {
        guard let idString = record["id"] as? String,
              let id = UUID(uuidString: idString),
              let date = record["date"] as? Date,
              let typeRaw = record["type"] as? String,
              let type = TransactionType(rawValue: typeRaw),
              let amount = record["amount"] as? Int,
              let memo = record["memo"] as? String,
              let createdAt = record["createdAt"] as? Date else {
            return nil
        }
        
        // Category Handling
        var categoryId: UUID?
        if let catIdStr = record["categoryId"] as? String {
            categoryId = UUID(uuidString: catIdStr)
        }
        
        let legacyCategory = record["category"] as? String
        let originalName = record["originalCategoryName"] as? String
        // If no ID, use legacy or original name as fallback originalName
        let finalOriginalName = (categoryId == nil) ? (originalName ?? legacyCategory) : nil
        
        // NOTE: if we have ID, we set default name to nil (it will be resolved by DataStore)
        // However, if we migrated it, we might want to keep originalName if specific logic requires it,
        // but generally ID is enough.

        let isRecurring = (record["isRecurring"] as? Int ?? 0) == 1
        let isSplit = (record["isSplit"] as? Int ?? 0) == 1
        let isDeleted = (record["isDeleted"] as? Int ?? 0) == 1

        var templateId: UUID?
        if let templateIdString = record["templateId"] as? String {
            templateId = UUID(uuidString: templateIdString)
        }

        var accountId: UUID?
        if let accountIdString = record["accountId"] as? String {
            accountId = UUID(uuidString: accountIdString)
        }

        var toAccountId: UUID?
        if let toAccountIdString = record["toAccountId"] as? String {
            toAccountId = UUID(uuidString: toAccountIdString)
        }

        let source = record["source"] as? String
        let sourceId = record["sourceId"] as? String

        var parentId: UUID?
        if let parentIdString = record["parentId"] as? String {
            parentId = UUID(uuidString: parentIdString)
        }

        return Transaction(
            id: id,
            date: date,
            type: type,
            amount: amount,
            categoryId: categoryId,
            originalCategoryName: finalOriginalName,
            memo: memo,
            isRecurring: isRecurring,
            templateId: templateId,
            createdAt: createdAt,
            source: source,
            sourceId: sourceId,
            accountId: accountId,
            toAccountId: toAccountId,
            parentId: parentId,
            isSplit: isSplit,
            isDeleted: isDeleted
        )
    }

    // MARK: - Subscription (リアルタイム通知)

    /// CloudKit変更通知のサブスクリプションを設定
    func setupSubscription() async {
        guard AppFeatureFlags.cloudSyncEnabled else { return }
        guard !subscriptionSaved else { return }

        let subscriptionID = "transaction-changes"
        let subscription = CKQuerySubscription(
            recordType: transactionRecordType,
            predicate: NSPredicate(value: true),
            subscriptionID: subscriptionID,
            options: [.firesOnRecordCreation, .firesOnRecordUpdate, .firesOnRecordDeletion]
        )

        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        subscription.notificationInfo = notificationInfo

        do {
            _ = try await database?.save(subscription)
            subscriptionSaved = true
        } catch let error as CKError where error.code == .serverRejectedRequest {
            // サブスクリプションが既に存在する場合は無視
            subscriptionSaved = true
        } catch {
            print("Failed to save subscription: \(error)")
        }
    }
}
