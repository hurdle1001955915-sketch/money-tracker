import SwiftUI

// MARK: - Split Transaction View

struct SplitTransactionView: View {
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.dismiss) private var dismiss
    
    /// 分割元の取引（既存取引を分割する場合）
    let sourceTransaction: Transaction?
    
    @State private var date = Date()
    @State private var totalAmountText = ""
    @State private var memo = ""
    @State private var splits: [SplitItem] = []
    
    @State private var showDatePicker = false
    @State private var showValidationError = false
    @State private var validationMessage = ""
    
    init(sourceTransaction: Transaction? = nil) {
        self.sourceTransaction = sourceTransaction
    }
    
    private var totalAmount: Int {
        Int(totalAmountText.replacingOccurrences(of: ",", with: "")) ?? 0
    }
    
    private var allocatedAmount: Int {
        splits.reduce(0) { sum, item in
            sum + (Int(item.amountText.replacingOccurrences(of: ",", with: "")) ?? 0)
        }
    }
    
    private var remainingAmount: Int {
        totalAmount - allocatedAmount
    }
    
    private var isValid: Bool {
        totalAmount > 0 && allocatedAmount == totalAmount && splits.count >= 2
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
                
                // 合計金額
                Section("合計金額") {
                    HStack {
                        TextField("合計金額", text: $totalAmountText)
                            .keyboardType(.numberPad)
                        Text("円")
                            .foregroundStyle(.secondary)
                    }
                }
                
                // メモ
                Section("メモ（共通）") {
                    TextField("メモ（任意）", text: $memo)
                }
                
                // 分割項目
                Section {
                    ForEach($splits) { $item in
                        SplitItemRow(
                            item: $item,
                            categories: dataStore.expenseCategories,
                            onDelete: {
                                if let index = splits.firstIndex(where: { $0.id == item.id }) {
                                    splits.remove(at: index)
                                }
                            }
                        )
                    }
                    
                    Button {
                        addSplitItem()
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(.green)
                            Text("分割項目を追加")
                        }
                    }
                } header: {
                    HStack {
                        Text("分割項目")
                        Spacer()
                        if totalAmount > 0 {
                            Text("残り: \(remainingAmount.currencyFormatted)")
                                .font(.caption)
                                .foregroundStyle(remainingAmount == 0 ? .green : (remainingAmount < 0 ? .red : .orange))
                        }
                    }
                }
                
                // 配分状況
                if totalAmount > 0 && !splits.isEmpty {
                    Section("配分状況") {
                        VStack(spacing: 8) {
                            // プログレスバー
                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    Rectangle()
                                        .fill(Color(.systemGray5))
                                        .frame(height: 8)
                                        .clipShape(Capsule())
                                    
                                    Rectangle()
                                        .fill(allocatedAmount <= totalAmount ? Color.green : Color.red)
                                        .frame(width: min(CGFloat(allocatedAmount) / CGFloat(max(totalAmount, 1)) * geometry.size.width, geometry.size.width), height: 8)
                                        .clipShape(Capsule())
                                }
                            }
                            .frame(height: 8)
                            
                            HStack {
                                Text("配分済: \(allocatedAmount.currencyFormatted)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("合計: \(totalAmount.currencyFormatted)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            if remainingAmount != 0 {
                                Text(remainingAmount > 0 ? "あと\(remainingAmount.currencyFormatted)を配分してください" : "\((-remainingAmount).currencyFormatted)超過しています")
                                    .font(.caption)
                                    .foregroundStyle(remainingAmount > 0 ? .orange : .red)
                            } else if splits.count >= 2 {
                                Text("配分完了")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            }
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
                
                // ヘルプ
                Section {
                    Text("1つの支払いを複数のカテゴリに分けて記録できます。\n例: 5,000円の買い物を「食費 3,000円」と「日用品 2,000円」に分割")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("分割取引")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("閉じる") { dismiss() }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    if totalAmount > 0 && remainingAmount > 0 {
                        Button("残りを配分") {
                            autoAllocateRemaining()
                        }
                        .font(.subheadline)
                    }
                }
            }
            .sheet(isPresented: $showDatePicker) {
                SplitDatePickerSheet(date: $date)
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
        if let tx = sourceTransaction {
            date = tx.date
            totalAmountText = String(tx.amount)
            memo = tx.memo
            
            // 元の取引を最初の分割項目として追加
            splits = [
                SplitItem(categoryId: tx.categoryId, amountText: String(tx.amount))
            ]
        } else {
            // 空の分割項目を2つ追加
            let categories = dataStore.expenseCategories
            splits = [
                SplitItem(categoryId: categories.first?.id, amountText: ""),
                SplitItem(categoryId: categories.count > 1 ? categories[1].id : nil, amountText: "")
            ]
        }
    }
    
    private func addSplitItem() {
        let categories = dataStore.expenseCategories
        let usedCategories = Set(splits.compactMap { $0.categoryId })
        let availableCategory = categories.first { !usedCategories.contains($0.id) }?.id ?? categories.first?.id
        
        splits.append(SplitItem(categoryId: availableCategory, amountText: ""))
    }
    
    private func autoAllocateRemaining() {
        guard remainingAmount > 0, let lastIndex = splits.indices.last else { return }
        
        // 最後の項目に残りを配分
        let currentAmount = Int(splits[lastIndex].amountText.replacingOccurrences(of: ",", with: "")) ?? 0
        splits[lastIndex].amountText = String(currentAmount + remainingAmount)
    }
    
    private func save() {
        guard isValid else {
            if totalAmount <= 0 {
                validationMessage = "合計金額を入力してください"
            } else if splits.count < 2 {
                validationMessage = "2つ以上の分割項目が必要です"
            } else if remainingAmount != 0 {
                validationMessage = "配分金額が合計と一致していません"
            }
            showValidationError = true
            return
        }
        
        // 元の取引を削除（分割元がある場合）
        if let source = sourceTransaction {
            dataStore.deleteTransaction(source)
        }
        
        // 親取引IDを生成
        let parentId = UUID()
        
        // 分割取引を作成
        for item in splits {
            let amount = Int(item.amountText.replacingOccurrences(of: ",", with: "")) ?? 0
            guard amount > 0 else { continue }
            
            let tx = Transaction(
                date: date,
                type: .expense,
                amount: amount,
                categoryId: item.categoryId,
                originalCategoryName: nil, // IDベースなのでnil
                memo: memo.isEmpty ? "分割取引" : memo,
                parentId: parentId,
                isSplit: true
            )
            dataStore.addTransaction(tx)
        }
        
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}

// MARK: - Split Item Model

struct SplitItem: Identifiable {
    let id = UUID()
    var categoryId: UUID?
    var amountText: String
}

// MARK: - Split Item Row

private struct SplitItemRow: View {
    @Binding var item: SplitItem
    let categories: [Category]
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // カテゴリ選択
            Picker("", selection: $item.categoryId) {
                ForEach(categories) { cat in
                    HStack {
                        Circle()
                            .fill(cat.color)
                            .frame(width: 8, height: 8)
                        Text(cat.name)
                    }
                    .tag(Optional(cat.id))
                }
            }
            .labelsHidden()
            .frame(width: 100)
            
            // 金額入力
            HStack {
                TextField("金額", text: $item.amountText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                Text("円")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 100)
            
            // 削除ボタン
            Button(action: onDelete) {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Date Picker Sheet

private struct SplitDatePickerSheet: View {
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

#Preview {
    SplitTransactionView()
        .environmentObject(DataStore.shared)
}
