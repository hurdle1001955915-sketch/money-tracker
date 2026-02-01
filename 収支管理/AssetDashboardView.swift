import SwiftUI
import Charts

struct AssetDashboardView: View {
    @EnvironmentObject var dataStore: DataStore
    @StateObject private var accountStore = AccountStore.shared
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 総資産サマリー
                totalAssetsCard
                
                // ポートフォリオ（円グラフ）
                portfolioCard
                
                // 資産推移（全体）
                assetTrendCard
                
                // 口座一覧
                accountsSection
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("資産管理")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    // MARK: - Subviews
    
    private var totalAssetsCard: some View {
        VStack(spacing: 8) {
            Text("総資産額")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            let total = accountStore.totalBalance(transactions: dataStore.transactions, asOf: Date())
            Text(total.currencyFormatted)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(total >= 0 ? Color.primary : Color.red)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
    
    private var portfolioCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("ポートフォリオ")
                .font(.headline)
            
            let balances = accountStore.activeAccounts.map { account in
                (account, accountStore.balance(for: account.id, transactions: dataStore.transactions))
            }.filter { $0.1 > 0 }
            
            if balances.isEmpty {
                Text("データがありません")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                Chart(balances, id: \.0.id) { item in
                    SectorMark(
                        angle: .value("残高", item.1),
                        innerRadius: .ratio(0.6),
                        angularInset: 2
                    )
                    .foregroundStyle(item.0.color)
                    .cornerRadius(4)
                }
                .frame(height: 200)
                
                // 凡例
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(balances, id: \.0.id) { item in
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(item.0.color)
                                    .frame(width: 8, height: 8)
                                Text(item.0.name)
                                    .font(.caption)
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
    }
    
    private var assetTrendCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("資産推移 (6ヶ月)")
                .font(.headline)
            
            let trendData = calculateAssetTrend()
            
            if trendData.isEmpty {
                Text("データがありません")
                    .foregroundStyle(.secondary)
            } else {
                Chart {
                    ForEach(trendData) { data in
                        LineMark(
                            x: .value("月", data.month),
                            y: .value("資産", data.amount)
                        )
                        .foregroundStyle(Color.themeBlue)
                        .symbol(Circle())
                        
                        AreaMark(
                            x: .value("月", data.month),
                            y: .value("資産", data.amount)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.themeBlue.opacity(0.3), Color.themeBlue.opacity(0.0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }
                }
                .frame(height: 200)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
    }
    
    private var accountsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("各口座の情報")
                .font(.headline)
            
            ForEach(accountStore.activeAccounts) { account in
                NavigationLink(destination: AccountDetailView(account: account)) {
                    HStack {
                        Circle()
                            .fill(account.color)
                            .frame(width: 12, height: 12)
                        Text(account.name)
                        Spacer()
                        let balance = accountStore.balance(for: account.id, transactions: dataStore.transactions)
                        Text(balance.currencyFormatted)
                            .fontWeight(.medium)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    // MARK: - Helper
    
    private func calculateAssetTrend() -> [AssetTrendData] {
        let cal = Calendar.current
        var result: [AssetTrendData] = []
        
        // 過去6ヶ月分
        for i in (0..<6).reversed() {
            guard let date = cal.date(byAdding: .month, value: -i, to: Date()) else { continue }
            // その月の月末時点の残高を計算
            guard let interval = cal.dateInterval(of: .month, for: date) else { continue }
            let endOfMonth = interval.end.addingTimeInterval(-1)
            
            let total = accountStore.totalBalance(transactions: dataStore.transactions, asOf: endOfMonth)
            
            let monthStr = date.yearMonthString
            result.append(AssetTrendData(month: monthStr, amount: total))
        }
        
        return result
    }
}

struct AssetTrendData: Identifiable {
    let id = UUID()
    let month: String
    let amount: Int
}

extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        dateInterval(of: .month, for: date)?.start ?? date
    }
}
