import Foundation
import Combine
import SwiftUI

/// 削除Undo管理（直前1件を保持し、一定時間後に確定）
@MainActor
final class DeletionManager: ObservableObject {
    static let shared = DeletionManager()
    
    /// Undo可能な時間（秒）
    private let undoTimeout: TimeInterval = 6.0
    
    /// 保留中の削除対象
    enum PendingDeletion {
        case transaction(Transaction, categoryName: String)
        case category(Category)
        case fixedCost(FixedCostTemplate)
        case budget(Budget, categoryName: String)
        
        var displayName: String {
            switch self {
            case .transaction(let t, let catName):
                return "\(catName) \(t.amount.currencyFormatted)"
            case .category(let c):
                return c.name
            case .fixedCost(let f):
                return f.name
            case .budget(_, let catName):
                return catName
            }
        }
    }
    
    @Published private(set) var pendingDeletion: PendingDeletion?
    @Published private(set) var remainingSeconds: Int = 0
    
    private var timer: Timer?
    private var confirmationTimer: Timer?
    
    var hasPendingDeletion: Bool {
        pendingDeletion != nil
    }
    
    var deletedItemName: String {
        pendingDeletion?.displayName ?? ""
    }
    
    private init() {}
    
    // MARK: - Transaction削除
    
    func deleteTransaction(_ tx: Transaction, from dataStore: DataStore) {
        // 前の保留があれば確定
        confirmPendingDeletion(from: dataStore)
        
        // カテゴリ名を解決
        let catName = dataStore.categoryName(for: tx.categoryId)
        
        // 新しい削除を保留
        pendingDeletion = .transaction(tx, categoryName: catName)
        
        // 論理削除 (isDeleted = true)
        var deletedTx = tx
        deletedTx.isDeleted = true
        dataStore.updateTransaction(deletedTx)
        
        startUndoTimer(for: dataStore)
    }
    
    // MARK: - Category削除
    
    func deleteCategory(_ category: Category, from dataStore: DataStore) {
        confirmPendingDeletion(from: dataStore)
        
        pendingDeletion = .category(category)
        dataStore.deleteCategory(category)
        
        startUndoTimer(for: dataStore)
    }
    
    // MARK: - FixedCostTemplate削除
    
    func deleteFixedCost(_ template: FixedCostTemplate, from dataStore: DataStore) {
        confirmPendingDeletion(from: dataStore)
        
        pendingDeletion = .fixedCost(template)
        dataStore.deleteFixedCostTemplate(template)
        
        startUndoTimer(for: dataStore)
    }
    
    // MARK: - Budget削除
    
    func deleteBudget(_ budget: Budget, from dataStore: DataStore) {
        confirmPendingDeletion(from: dataStore)
        
        let catName: String
        if let catId = budget.categoryId {
            catName = dataStore.categoryName(for: catId)
        } else {
            catName = "全体予算"
        }
        
        pendingDeletion = .budget(budget, categoryName: catName)
        dataStore.deleteBudget(budget)
        
        startUndoTimer(for: dataStore)
    }
    
    // MARK: - Undo
    
    func undo(to dataStore: DataStore) {
        guard let pending = pendingDeletion else { return }
        
        stopTimers()
        
        switch pending {
        case .transaction(let tx, _):
            // 論理削除からの復帰
            var restored = tx
            restored.isDeleted = false
            dataStore.updateTransaction(restored)
        case .category(let c):
            dataStore.addCategory(c)
        case .fixedCost(let f):
            dataStore.addFixedCostTemplate(f)
        case .budget(let b, _):
            dataStore.addBudget(b)
        }
        
        pendingDeletion = nil
        remainingSeconds = 0
    }
    
    // MARK: - 確定
    
    func confirmPendingDeletion(from dataStore: DataStore) {
        stopTimers()
        pendingDeletion = nil
        remainingSeconds = 0
    }
    
    // MARK: - タイマー管理
    
    private func startUndoTimer(for dataStore: DataStore) {
        stopTimers()
        
        remainingSeconds = Int(undoTimeout)
        
        // カウントダウンタイマー
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                self.remainingSeconds -= 1
                if self.remainingSeconds <= 0 {
                    self.confirmPendingDeletion(from: dataStore)
                }
            }
        }
        
        // 確定タイマー（バックアップ）
        confirmationTimer = Timer.scheduledTimer(withTimeInterval: undoTimeout, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.confirmPendingDeletion(from: dataStore)
            }
        }
    }
    
    private func stopTimers() {
        timer?.invalidate()
        timer = nil
        confirmationTimer?.invalidate()
        confirmationTimer = nil
    }
}
