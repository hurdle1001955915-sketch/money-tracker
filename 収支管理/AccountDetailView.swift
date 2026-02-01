import SwiftUI
import Charts

struct AccountDetailView: View {
    let account: Account
    @EnvironmentObject var dataStore: DataStore
    @StateObject private var accountStore = AccountStore.shared
    
    var body: some View {
        List {
            // 残高サマリー
            Section {
                VStack(spacing: 8) {
                    Text("現在の残高")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    let balance = accountStore.balance(for: account.id, transactions: dataStore.transactions)
                    Text(balance.currencyFormatted)
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(balance >= 0 ? Color.primary : Color.red)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            }
            
            // 残高推移グラフ
            Section("残高の推移") {
                let trendData = calculateAccountTrend()
                
                if trendData.isEmpty {
                    Text("データがありません")
                        .foregroundStyle(.secondary)
                } else {
                    Chart(trendData) { data in
                        LineMark(
                            x: .value("日付", data.date),
                            y: .value("残高", data.balance)
                        )
                        .foregroundStyle(account.color)
                        
                        AreaMark(
                            x: .value("日付", data.date),
                            y: .value("残高", data.balance)
                        )
                        .foregroundStyle(account.color.opacity(0.1))
                    }
                    .frame(height: 180)
                    .padding(.vertical, 8)
                }
            }
            
            // 取引履歴
            Section("最近の取引") {
                let txs = dataStore.transactions.filter { 
                    ($0.accountId == account.id || $0.toAccountId == account.id) && !$0.isDeleted 
                }.sorted { $0.date > $1.date }
                
                if txs.isEmpty {
                    Text("取引履歴はありません")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(txs.prefix(50)) { tx in
                        TransactionRow(tx: tx, dataStore: dataStore)
                    }
                }
            }
        }
        .navigationTitle(account.name)
        .navigationBarTitleDisplayMode(.inline)
    }
    
    // MARK: - Helper
    
    struct AccountTrendData: Identifiable {
        let id = UUID()
        let date: Date
        let balance: Int
    }
    
    private func calculateAccountTrend() -> [AccountTrendData] {
        let cal = Calendar.current
        var result: [AccountTrendData] = []
        
        // 直近30日間の推移
        for i in (0..<30).reversed() {
            guard let date = cal.date(byAdding: .day, value: -i, to: Date()) else { continue }
            guard let nextDay = cal.date(byAdding: .day, value: 1, to: date) else { continue }
            let endOfDay = cal.startOfDay(for: nextDay)
            
            let balance = accountStore.balance(for: account.id, transactions: dataStore.transactions, asOf: endOfDay)
            result.append(AccountTrendData(date: date, balance: balance))
        }
        
        return result
    }
}

// DataStore.swiftなどに既に似たものがあるかもしれないが、簡易的に実装or再利用
private struct TransactionRow: View {
    let tx: Transaction
    let dataStore: DataStore
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(tx.memo.isEmpty ? dataStore.categoryName(for: tx.categoryId) : tx.memo)
                    .fontWeight(.medium)
                Text(tx.date.formatted(date: .numeric, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Text(tx.amount.currencyFormatted)
                .foregroundStyle(tx.type == .income ? Color.green : Color.primary)
        }
    }
}
