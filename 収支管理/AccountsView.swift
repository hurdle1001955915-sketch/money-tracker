import SwiftUI
import Foundation

// MARK: - Accounts List View

struct AccountsListView: View {
    @StateObject private var accountStore = AccountStore.shared
    @EnvironmentObject var dataStore: DataStore
    
    @State private var showAddSheet = false
    @State private var editingAccount: Account?
    @State private var showDeleteAlert = false
    @State private var accountToDelete: Account?
    
    var body: some View {
        List {
            // 残高サマリー
            Section {
                HStack {
                    Text("合計残高")
                        .font(.subheadline)
                    Spacer()
                    Text(accountStore.totalBalance(transactions: dataStore.transactions, asOf: Date()).currencyFormatted)
                        .font(.headline)
                        .fontWeight(.bold)
                }
                .padding(.vertical, 8)
            }
            // 口座一覧
            Section("口座") {
                if accountStore.activeAccounts.isEmpty {
                    Text("口座がありません")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(accountStore.activeAccounts) { account in
                        AccountRow(
                            account: account,
                            balance: accountStore.balance(for: account.id, transactions: dataStore.transactions)
                        ) {
                            editingAccount = account
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                accountToDelete = account
                                showDeleteAlert = true
                            } label: {
                                Label("削除", systemImage: "trash")
                            }
                        }
                    }
                    .onMove { from, to in
                        accountStore.reorderAccounts(from: from, to: to)
                    }
                }
            }
            
            Section {
                Text("口座を設定すると、振替（口座間の資金移動）を記録できます。各取引に口座を紐づけることで、口座ごとの残高を管理できます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("口座管理")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AccountEditView(account: nil)
        }
        .sheet(item: $editingAccount) { account in
            AccountEditView(account: account)
        }
        .alert("口座を削除", isPresented: $showDeleteAlert) {
            Button("キャンセル", role: .cancel) {}
            Button("削除", role: .destructive) {
                if let account = accountToDelete {
                    accountStore.deleteAccount(account)
                }
            }
        } message: {
            Text("この口座を削除しますか？\n（既存の取引データは影響を受けません）")
        }
    }
}

// MARK: - Account Row

private struct AccountRow: View {
    let account: Account
    let balance: Int
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                Circle()
                    .fill(account.color)
                    .frame(width: 32, height: 32)
                    .overlay {
                        Image(systemName: account.type.iconName)
                            .font(.caption)
                            .foregroundStyle(.white)
                    }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.name)
                        .fontWeight(.medium)
                    Text(account.type.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Text(balance.currencyFormatted)
                    .fontWeight(.medium)
                    .foregroundStyle(balance >= 0 ? Color.primary : Color.red)
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Account Edit View

struct AccountEditView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var accountStore = AccountStore.shared
    
    let account: Account?
    
    @State private var name = ""
    @State private var type: AccountType = .bank
    @State private var initialBalanceText = ""
    @State private var selectedColor = "#2196F3"
    
    private var isEditing: Bool { account != nil }
    
    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }
    
    var body: some View {
        NavigationStack {
            Form {
                // クイック選択テンプレート（新規追加時のみ表示）
                if !isEditing {
                    Section("よく使う口座を追加") {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            ForEach(accountTemplates, id: \.name) { template in
                                Button {
                                    applyTemplate(template)
                                } label: {
                                    HStack {
                                        Circle()
                                            .fill(Color(hex: template.colorHex))
                                            .frame(width: 24, height: 24)
                                            .overlay {
                                                Image(systemName: template.type.iconName)
                                                    .font(.caption2)
                                                    .foregroundStyle(.white)
                                            }
                                        Text(template.name)
                                            .font(.caption)
                                            .lineLimit(1)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .background(Color.secondaryBackground)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section("基本情報") {
                    TextField("口座名", text: $name)
                    
                    Picker("種類", selection: $type) {
                        ForEach(AccountType.allCases, id: \.self) { accountType in
                            HStack {
                                Image(systemName: accountType.iconName)
                                Text(accountType.displayName)
                            }
                            .tag(accountType)
                        }
                    }
                    
                    HStack {
                        Text("初期残高")
                        Spacer()
                        TextField("0", text: $initialBalanceText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 120)
                        Text("円")
                            .foregroundStyle(.secondary)
                    }
                }
                
                Section("カラー") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(accountColors, id: \.self) { color in
                            Button {
                                selectedColor = color
                            } label: {
                                Circle()
                                    .fill(Color(hex: color))
                                    .frame(width: 40, height: 40)
                                    .overlay {
                                        if selectedColor == color {
                                            Circle()
                                                .stroke(Color.primary, lineWidth: 3)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle(isEditing ? "口座を編集" : "口座を追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { save() }
                        .disabled(!isValid)
                }
            }
            .onAppear {
                if let a = account {
                    name = a.name
                    type = a.type
                    initialBalanceText = a.initialBalance == 0 ? "" : String(a.initialBalance)
                    selectedColor = a.colorHex
                }
            }
        }
    }
    
    private func save() {
        let initialBalance = Int(initialBalanceText.replacingOccurrences(of: ",", with: "")) ?? 0
        
        if let existing = account {
            var updated = existing
            updated.name = name.trimmingCharacters(in: .whitespaces)
            updated.type = type
            updated.initialBalance = initialBalance
            updated.colorHex = selectedColor
            accountStore.updateAccount(updated)
        } else {
            let newAccount = Account(
                name: name.trimmingCharacters(in: .whitespaces),
                type: type,
                initialBalance: initialBalance,
                colorHex: selectedColor
            )
            accountStore.addAccount(newAccount)
        }
        
        dismiss()
    }
    
    private let accountColors = [
        "#F44336", "#E91E63", "#9C27B0", "#673AB7", "#3F51B5", "#2196F3",
        "#03A9F4", "#00BCD4", "#009688", "#4CAF50", "#8BC34A", "#CDDC39",
        "#FFC107", "#FF9800", "#FF5722", "#795548", "#9E9E9E", "#607D8B"
    ]

    // よく使う口座テンプレート
    private var accountTemplates: [(name: String, type: AccountType, colorHex: String)] {
        [
            (name: "PayPay", type: .payPay, colorHex: "#FF0033"),
            (name: "Suica（iPhone）", type: .suica, colorHex: "#009E44"),
            (name: "Suica（Apple Watch）", type: .suica, colorHex: "#009E44"),
            (name: "楽天ペイ", type: .electronicMoney, colorHex: "#BF0000"),
            (name: "nanaco", type: .electronicMoney, colorHex: "#00A040"),
            (name: "WAON", type: .electronicMoney, colorHex: "#F7931E"),
            (name: "iD", type: .electronicMoney, colorHex: "#ED1C24"),
            (name: "QUICPay", type: .electronicMoney, colorHex: "#0068B7"),
        ]
    }

    private func applyTemplate(_ template: (name: String, type: AccountType, colorHex: String)) {
        name = template.name
        type = template.type
        selectedColor = template.colorHex
    }
}

// MARK: - AccountType Icon Extension

extension AccountType {
    var iconName: String {
        switch self {
        case .bank: return "building.columns"
        case .creditCard: return "creditcard"
        case .electronicMoney: return "wave.3.right"
        case .payPay: return "wave.3.left" // PayPayっぽい波形
        case .suica: return "tram.fill"    // Suicaっぽい電車
        case .cash: return "banknote"
        case .investment: return "chart.line.uptrend.xyaxis"
        case .other: return "folder"
        }
    }
}

#Preview {
    NavigationStack {
        AccountsListView()
            .environmentObject(DataStore.shared)
    }
}

