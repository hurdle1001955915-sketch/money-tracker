import SwiftUI

struct DayDetailView: View {
    @EnvironmentObject var dataStore: DataStore
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var deletionManager: DeletionManager
    @Environment(\.dismiss) private var dismiss

    private let accountStore = AccountStore.shared

    let date: Date

    @State private var showInputView = false
    @State private var editingTransaction: Transaction? = nil
    
    // 複製
    @State private var showDuplicateSheet = false
    @State private var transactionToDuplicate: Transaction? = nil
    @State private var duplicateDate: Date = Date()
    
    // 振替編集
    @State private var showTransferEdit = false
    @State private var editingTransfer: Transaction? = nil

    private var dayTransactions: [Transaction] {
        dataStore.sortedTransactionsForDate(date, sortOrder: settings.sameDaySortOrder)
    }

    var body: some View {
        NavigationStack {
            List {
                if dayTransactions.isEmpty {
                    VStack(spacing: 20) {
                        Spacer()
                        Image(systemName: "tray")
                            .font(.system(size: 60))
                            .foregroundStyle(.quaternary)
                        
                        VStack(spacing: 8) {
                            Text("取引がありません")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                            Text("右上の「＋」ボタンから追加できます")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        
                        Button {
                            editingTransaction = nil
                            showInputView = true
                        } label: {
                            Label("取引を追加", systemImage: "plus")
                                .fontWeight(.medium)
                        }
                        .buttonStyle(.bordered)
                        .tint(.blue)
                        .controlSize(.large)
                        
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .padding(.vertical, 40)
                } else {
                    Section {
                        ForEach(dayTransactions) { transaction in
                            transactionRow(transaction)
                                .contentShape(Rectangle())

                                // タップ：編集（振替は別画面）
                                .onTapGesture {
                                    if transaction.type == .transfer {
                                        editingTransfer = transaction
                                        showTransferEdit = true
                                    } else {
                                        editingTransaction = transaction
                                        showInputView = true
                                    }
                                }

                                // 長押し：削除（Undo可能）
                                .onLongPressGesture {
                                    deleteTransaction(transaction)
                                }

                                // 右スワイプ：削除（Undo可能）
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        deleteTransaction(transaction)
                                    } label: {
                                        Label("削除", systemImage: "trash")
                                    }
                                }
                                
                                // 左スイプ：複製
                                .swipeActions(edge: .leading) {
                                    Button {
                                        transactionToDuplicate = transaction
                                        duplicateDate = date
                                        showDuplicateSheet = true
                                    } label: {
                                        Label("複製", systemImage: "doc.on.doc")
                                    }
                                    .tint(.blue)
                                }
                        }
                    }
                }
            }
            .navigationTitle("\(date.month)月\(date.day)日(\(date.dayOfWeekString))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("閉じる") { dismiss() }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editingTransaction = nil
                        showInputView = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showInputView) {
                TransactionInputView(
                    preselectedDate: date,
                    editingTransaction: editingTransaction,
                    dismissAfterSave: true
                ) {
                    showInputView = false
                    editingTransaction = nil
                }
            }
            .sheet(isPresented: $showDuplicateSheet) {
                DuplicateTransactionSheet(
                    transaction: transactionToDuplicate,
                    targetDate: $duplicateDate,
                    onDuplicate: { targetDate in
                        if let tx = transactionToDuplicate {
                            dataStore.duplicateTransaction(tx, toDate: targetDate)
                            HapticManager.shared.success()
                        }
                        showDuplicateSheet = false
                        transactionToDuplicate = nil
                    }
                )
            }
            .sheet(isPresented: $showTransferEdit) {
                TransferInputView(editingTransaction: editingTransfer) {
                    showTransferEdit = false
                    editingTransfer = nil
                }
            }
        }
    }
    
    private func deleteTransaction(_ transaction: Transaction) {
        withAnimation {
            deletionManager.deleteTransaction(transaction, from: dataStore)
        }
        HapticManager.shared.warning()
    }

    private func transactionRow(_ transaction: Transaction) -> some View {
        let category = dataStore.category(for: transaction.categoryId)
        // 振替の場合は動的に口座名を解決、それ以外はカテゴリ名
        let displayName: String = {
            if transaction.isTransfer {
                return transaction.transferDisplayLabel(accountStore: accountStore)
            } else {
                return dataStore.categoryName(for: transaction.categoryId)
            }
        }()
        let amountColor: Color = {
            switch transaction.type {
            case .income: return Color(UIColor.systemBlue)
            case .expense: return Color(UIColor.systemRed)
            case .transfer: return Color(UIColor.systemOrange)
            }
        }()

        return HStack {
            if transaction.type == .transfer {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .frame(width: 16, height: 16)
            } else if let category = category {
                Circle()
                    .fill(category.color)
                    .frame(width: 16, height: 16)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.subheadline)

                if !transaction.memo.isEmpty {
                    Text(transaction.memo)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            HStack(spacing: 6) {
                if transaction.isRecurring {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if transaction.isSplit {
                    Image(systemName: "square.split.2x1")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(transaction.amount.currencyFormatted)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(amountColor)
            }
        }
        .frame(minHeight: 44)
    }
}

#Preview {
    DayDetailView(date: Date())
        .environmentObject(DataStore.shared)
        .environmentObject(AppSettings.shared)
        .environmentObject(DeletionManager.shared)
}

