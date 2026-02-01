import SwiftUI
import WidgetKit

// MARK: - Widget Views

/// 小サイズウィジェット - 今日の支出
struct SmallWidgetView: View {
    let entry: KakeiboWidgetEntry
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "yensign.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Color(hex: "#1a237e"))
                Text("今日の支出")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Text(entry.data.todayExpense.currencyFormattedWidget)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(entry.data.todayExpense > 0 ? Color(UIColor.systemRed) : .primary)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            
            Text(formattedDate(entry.data.lastUpdate))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding()
        .containerBackground(for: .widget) {
            Color(.systemBackground)
        }
    }
    
    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "H:mm更新"
        return formatter.string(from: date)
    }
}

/// 中サイズウィジェット - 今月の収支
struct MediumWidgetView: View {
    let entry: KakeiboWidgetEntry
    
    var body: some View {
        HStack(spacing: 16) {
            // 左側：今日の支出
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "yensign.circle.fill")
                        .foregroundStyle(Color(hex: "#1a237e"))
                    Text("今日")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Text(entry.data.todayExpense.currencyFormattedWidget)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(Color(UIColor.systemRed))
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Divider()
            
            // 右側：今月の収支
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("今月")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("収入")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(entry.data.monthIncome.currencyFormattedWidget)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(Color(UIColor.systemBlue))
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("支出")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(entry.data.monthExpense.currencyFormattedWidget)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(Color(UIColor.systemRed))
                    }
                }
                
                HStack {
                    Text("残高")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(entry.data.monthBalance.currencyFormattedWidget)
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundStyle(entry.data.monthBalance >= 0 ? .primary : Color(UIColor.systemRed))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .containerBackground(for: .widget) {
            Color(.systemBackground)
        }
    }
}

/// 大サイズウィジェット - 収支 + 直近取引
struct LargeWidgetView: View {
    let entry: KakeiboWidgetEntry
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // ヘッダー
            HStack {
                Image(systemName: "yensign.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Color(hex: "#1a237e"))
                Text("家計簿")
                    .font(.headline)
                Spacer()
                Text(monthString(entry.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            // 収支サマリー
            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("収入")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(entry.data.monthIncome.currencyFormattedWidget)
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundStyle(Color(UIColor.systemBlue))
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("支出")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(entry.data.monthExpense.currencyFormattedWidget)
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundStyle(Color(UIColor.systemRed))
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("残高")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(entry.data.monthBalance.currencyFormattedWidget)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundStyle(entry.data.monthBalance >= 0 ? .green : Color(UIColor.systemRed))
                }
            }
            
            Divider()
            
            // 直近の取引
            Text("直近の取引")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            if entry.data.recentTransactions.isEmpty {
                Text("取引がありません")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 6) {
                    ForEach(entry.data.recentTransactions.prefix(4)) { tx in
                        HStack {
                            Text(tx.category)
                                .font(.caption)
                                .lineLimit(1)
                            Spacer()
                            Text(tx.amount.currencyFormattedWidget)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(tx.isExpense ? Color(UIColor.systemRed) : Color(UIColor.systemBlue))
                        }
                    }
                }
            }
            
            Spacer()
        }
        .padding()
        .containerBackground(for: .widget) {
            Color(.systemBackground)
        }
    }
    
    private func monthString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "M月"
        return formatter.string(from: date)
    }
}

// MARK: - Widget Extension (Int)

extension Int {
    var currencyFormattedWidget: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        let str = formatter.string(from: NSNumber(value: self)) ?? "0"
        return "¥\(str)"
    }
}

// MARK: - Preview

#Preview("SmallWidget") {
    SmallWidgetView(entry: KakeiboWidgetEntry.placeholder)
}

#Preview("MediumWidget") {
    MediumWidgetView(entry: KakeiboWidgetEntry.placeholder)
}

#Preview("LargeWidget") {
    LargeWidgetView(entry: KakeiboWidgetEntry.placeholder)
}
