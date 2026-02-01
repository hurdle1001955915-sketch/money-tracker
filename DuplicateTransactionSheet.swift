import SwiftUI

struct DuplicateTransactionSheet: View {
    let transaction: Transaction?
    @Binding var targetDate: Date
    let onDuplicate: (Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataStore: DataStore

    init(transaction: Transaction?, targetDate: Binding<Date>, onDuplicate: @escaping (Date) -> Void) {
        self.transaction = transaction
        self._targetDate = targetDate
        self.onDuplicate = onDuplicate
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("複製日") {
                    DatePicker("日付", selection: $targetDate, displayedComponents: .date)
                }
                if let transaction = transaction {
                    Section("対象") {
                        Text(dataStore.categoryName(for: transaction.categoryId))
                        Text(transaction.amount.currencyFormatted)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("複製") {
                        onDuplicate(targetDate)
                        dismiss()
                    }
                }
            }
        }
    }
}

