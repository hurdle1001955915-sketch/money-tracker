import SwiftUI

// MARK: - Transfer Input View

struct TransferInputView: View {
    @EnvironmentObject var dataStore: DataStore
    @StateObject private var accountStore = AccountStore.shared
    @Environment(\.dismiss) private var dismiss
    
    let editingTransaction: Transaction?
    let onSave: (() -> Void)?
    
    @State private var date = Date()
    @State private var amountText = ""
    @State private var fromAccountId: UUID?
    @State private var toAccountId: UUID?
    @State private var memo = ""
    
    @State private var showDatePicker = false
    
    @State private var showValidationError = false
    @State private var validationMessage = ""
    
    private var isEditing: Bool { editingTransaction != nil }
    
    private var isValid: Bool {
        guard let amount = Int(amountText.replacingOccurrences(of: ",", with: "")),
              amount > 0 else { return false }
        guard fromAccountId != nil, toAccountId != nil else { return false }
        guard fromAccountId != toAccountId else { return false }
        return true
    }
    
    init(editingTransaction: Transaction? = nil, onSave: (() -> Void)? = nil) {
        self.editingTransaction = editingTransaction
        self.onSave = onSave
    }
    
    var body: some View {
        NavigationStack {
            Form {
                // 日付
                Section("日付") {
                    Button {
                        showDatePicker = true
                    } label: {
                        HStack {
                            Text("日付")
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(date.fullDateString)
                                .foregroundStyle(Color.themeBlue)
                                .fontWeight(.semibold)
                        }
                    }
                }
                
                // 金額
                Section("金額") {
                    HStack {
                        TextField("金額", text: $amountText)
                            .keyboardType(.numberPad)
                        Text("円")
                            .foregroundStyle(.secondary)
                    }
                }
                
                // 振替元
                Section("振替元") {
                    if accountStore.activeAccounts.isEmpty {
                        Text("口座を先に登録してください")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("口座", selection: $fromAccountId) {
                            Text("選択してください").tag(UUID?.none)
                            ForEach(accountStore.activeAccounts) { account in
                                HStack {
                                    Circle()
                                        .fill(account.color)
                                        .frame(width: 12, height: 12)
                                    Text(account.name)
                                }
                                .tag(UUID?.some(account.id))
                            }
                        }
                        
                        if let fromId = fromAccountId {
                            let balance = accountStore.balance(for: fromId, transactions: dataStore.transactions)
                            HStack {
                                Text("現在残高")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(balance.currencyFormatted)
                                    .font(.caption)
                                    .foregroundStyle(balance >= 0 ? Color.secondary : Color.red)
                            }
                        }
                    }
                }
                
                // 振替先
                Section("振替先") {
                    if accountStore.activeAccounts.isEmpty {
                        Text("口座を先に登録してください")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("口座", selection: $toAccountId) {
                            Text("選択してください").tag(UUID?.none)
                            ForEach(accountStore.activeAccounts.filter { $0.id != fromAccountId }) { account in
                                HStack {
                                    Circle()
                                        .fill(account.color)
                                        .frame(width: 12, height: 12)
                                    Text(account.name)
                                }
                                .tag(UUID?.some(account.id))
                            }
                        }
                        
                        if let toId = toAccountId {
                            let balance = accountStore.balance(for: toId, transactions: dataStore.transactions)
                            HStack {
                                Text("現在残高")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(balance.currencyFormatted)
                                    .font(.caption)
                                    .foregroundStyle(balance >= 0 ? Color.secondary : Color.red)
                            }
                        }
                    }
                }
                
                // メモ
                Section("メモ") {
                    TextField("メモ（任意）", text: $memo)
                }
                
                // プレビュー
                if isValid, let fromId = fromAccountId, let toId = toAccountId,
                   let fromAccount = accountStore.account(for: fromId),
                   let toAccount = accountStore.account(for: toId) {
                    Section("確認") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Circle()
                                    .fill(fromAccount.color)
                                    .frame(width: 20, height: 20)
                                Text(fromAccount.name)
                                
                                Image(systemName: "arrow.right")
                                    .foregroundStyle(.secondary)
                                
                                Circle()
                                    .fill(toAccount.color)
                                    .frame(width: 20, height: 20)
                                Text(toAccount.name)
                            }
                            
                            Text("\(amountText)円 を振替")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
                
                // 保存ボタン
                Section {
                    Button {
                        save()
                    } label: {
                        Text("保存")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(isValid ? Color.themeBlue : Color.gray)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(!isValid)
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                }
            }
            .navigationTitle(isEditing ? "振替を編集" : "振替")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("閉じる") { dismiss() }
                }
            }
            .sheet(isPresented: $showDatePicker) {
                DatePickerSheet(date: $date)
            }
            .alert("入力エラー", isPresented: $showValidationError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(validationMessage)
            }
            .onAppear {
                setupInitialValues()
            }
        }
    }
    
    private func setupInitialValues() {
        if let tx = editingTransaction {
            date = tx.date
            amountText = String(tx.amount)
            fromAccountId = tx.accountId
            toAccountId = tx.toAccountId
            memo = tx.memo
        } else {
            // デフォルトで最初の2つの口座を選択
            let accounts = accountStore.activeAccounts
            if accounts.count >= 2 {
                fromAccountId = accounts[0].id
                toAccountId = accounts[1].id
            } else if accounts.count == 1 {
                fromAccountId = accounts[0].id
            }
        }
    }
    
    private func save() {
        guard let amount = Int(amountText.replacingOccurrences(of: ",", with: "")),
              amount > 0 else {
            validationMessage = "金額を正しく入力してください"
            showValidationError = true
            return
        }
        
        guard let fromId = fromAccountId, let toId = toAccountId else {
            validationMessage = "振替元と振替先を選択してください"
            showValidationError = true
            return
        }
        
        guard fromId != toId else {
            validationMessage = "振替元と振替先は異なる口座を選択してください"
            showValidationError = true
            return
        }
        
        // 振替元と振替先の名前を取得してカテゴリに設定
        let fromName = accountStore.account(for: fromId)?.name ?? ""
        let toName = accountStore.account(for: toId)?.name ?? ""
        let transferLabel = "\(fromName) → \(toName)"

        if let existing = editingTransaction {
            var updated = existing
            updated.date = date
            updated.amount = amount
            updated.accountId = fromId
            updated.toAccountId = toId
            updated.memo = memo
            // 振替はカテゴリIDなし、ラベルはoriginalCategoryNameに入れる
            updated.categoryId = nil
            updated.originalCategoryName = transferLabel
            dataStore.updateTransaction(updated)
        } else {
            let tx = Transaction(
                date: date,
                type: .transfer,
                amount: amount,
                categoryId: nil,
                originalCategoryName: transferLabel,
                memo: memo,
                accountId: fromId,
                toAccountId: toId
            )
            dataStore.addTransaction(tx)
        }
        
        onSave?()
        dismiss()
    }
}

// MARK: - Date Picker Sheet

private struct DatePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var date: Date
    
    var body: some View {
        NavigationStack {
            DatePicker("", selection: $date, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .padding()
                .onChange(of: date) { _, _ in
                    dismiss()
                }
                .navigationTitle("日付を選択")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("閉じる") { dismiss() }
                    }
                }
        }
        .presentationDetents([.medium])
    }
}

#Preview("振替入力") {
    TransferInputView()
        .environmentObject(DataStore.shared)
}
