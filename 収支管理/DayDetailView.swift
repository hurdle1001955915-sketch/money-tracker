import SwiftUI

struct DayDetailView: View {
    @EnvironmentObject var dataStore: DataStore
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var deletionManager: DeletionManager
    @Environment(\.dismiss) private var dismiss

    private let accountStore = AccountStore.shared

    let date: Date
    /// true = CalendarView内のインライン埋め込み（NavigationStack/toolbarなし）
    var embedded: Bool = false

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
        if embedded {
            embeddedBody
        } else {
            fullScreenBody
        }
    }

    // MARK: - Full-screen（モーダル表示用）

    private var fullScreenBody: some View {
        NavigationStack {
            transactionListFullScreen
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
                .modifier(TransactionSheetsModifier(
                    date: date,
                    showInputView: $showInputView,
                    editingTransaction: $editingTransaction,
                    showDuplicateSheet: $showDuplicateSheet,
                    transactionToDuplicate: $transactionToDuplicate,
                    duplicateDate: $duplicateDate,
                    showTransferEdit: $showTransferEdit,
                    editingTransfer: $editingTransfer,
                    dataStore: dataStore
                ))
        }
    }

    // MARK: - Embedded（CalendarView内インライン表示用）

    private var embeddedBody: some View {
        Group {
            if dayTransactions.isEmpty {
                Text("取引がありません")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 24)
                    .background(Color(.systemBackground))
            } else {
                List {
                    ForEach(dayTransactions) { transaction in
                        transactionRow(transaction)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                handleTap(transaction)
                            }
                            .onLongPressGesture {
                                deleteTransaction(transaction)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    deleteTransaction(transaction)
                                } label: {
                                    Label("削除", systemImage: "trash")
                                }
                            }
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
                            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                            .listRowSeparator(.visible)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Color(.systemBackground))
            }
        }
        .modifier(TransactionSheetsModifier(
            date: date,
            showInputView: $showInputView,
            editingTransaction: $editingTransaction,
            showDuplicateSheet: $showDuplicateSheet,
            transactionToDuplicate: $transactionToDuplicate,
            duplicateDate: $duplicateDate,
            showTransferEdit: $showTransferEdit,
            editingTransfer: $editingTransfer,
            dataStore: dataStore
        ))
    }

    // MARK: - Full-screen用リスト

    private var transactionListFullScreen: some View {
        List {
            if dayTransactions.isEmpty {
                EmptyStateView(
                    icon: "tray",
                    title: "取引がありません",
                    subtitle: "右上の「＋」ボタンから追加できます",
                    actionTitle: "取引を追加"
                ) {
                    editingTransaction = nil
                    showInputView = true
                }
                .listRowBackground(Color.clear)
                .padding(.vertical, 40)
            } else {
                Section {
                    ForEach(dayTransactions) { transaction in
                        transactionRow(transaction)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                handleTap(transaction)
                            }
                            .onLongPressGesture {
                                deleteTransaction(transaction)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    deleteTransaction(transaction)
                                } label: {
                                    Label("削除", systemImage: "trash")
                                }
                            }
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
    }

    // MARK: - Shared Helpers

    private func handleTap(_ transaction: Transaction) {
        if transaction.type == .transfer {
            editingTransfer = transaction
            showTransferEdit = true
        } else {
            editingTransaction = transaction
            showInputView = true
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
        .padding(.horizontal, embedded ? 16 : 0)
    }
}

// MARK: - Sheet表示を共通化するViewModifier

private struct TransactionSheetsModifier: ViewModifier {
    let date: Date
    @Binding var showInputView: Bool
    @Binding var editingTransaction: Transaction?
    @Binding var showDuplicateSheet: Bool
    @Binding var transactionToDuplicate: Transaction?
    @Binding var duplicateDate: Date
    @Binding var showTransferEdit: Bool
    @Binding var editingTransfer: Transaction?
    let dataStore: DataStore

    func body(content: Content) -> some View {
        content
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

#Preview {
    DayDetailView(date: Date())
        .environmentObject(DataStore.shared)
        .environmentObject(AppSettings.shared)
        .environmentObject(DeletionManager.shared)
}
