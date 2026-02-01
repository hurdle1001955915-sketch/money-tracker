import SwiftUI
import Charts

struct GraphView: View {
    @EnvironmentObject var dataStore: DataStore
    @EnvironmentObject var settings: AppSettings
    
    @State private var currentDate = Date()
    @State private var selectedGraphType: GraphType = .expense
    @State private var showReorderSheet = false
    @State private var selectedCategoryDetail: CategoryDetailInfo?

    // Optimization: Graph Data Model
    private struct GraphData: Equatable {
        let type: GraphType
        let sections: [CategorySection]
        let total: Int
        
        static func build(
            type: GraphType,
            currentDate: Date,
            transactions: [Transaction],
            categories: [Category] // 常に最新のカテゴリリストを渡す
        ) -> GraphData {
            let filtered = transactions.filter {
                $0.type.rawValue == type.rawValue &&
                !$0.isDeleted &&
                $0.date.isSameMonth(as: currentDate)
            }
            
            // 全合計（これを基準にする）
            let grandTotal = filtered.reduce(0) { $0 + $1.amount }
            
            // カテゴリごとに集計
            var categoryTotals: [UUID: Int] = [:]
            var uncategorizedTotal = 0
            
            for tx in filtered {
                if let catId = tx.categoryId {
                    categoryTotals[catId, default: 0] += tx.amount
                } else {
                    uncategorizedTotal += tx.amount
                }
            }
            
            var sections: [CategorySection] = []
            let masterCategoryIds = Set(categories.map { $0.id })
            
            // 1. カテゴリマスタに存在する項目を追加
            for cat in categories where cat.type.rawValue == type.rawValue {
                if let amount = categoryTotals[cat.id], amount > 0 {
                    sections.append(CategorySection(
                        category: cat,
                        amount: amount,
                        color: Color(hex: cat.colorHex)
                    ))
                    categoryTotals.removeValue(forKey: cat.id)
                }
            }
            
            // 2. カテゴリマスタに存在しないID（削除済みカテゴリ等）を「その他（不明）」として集計
            let unknownTotal = categoryTotals.values.reduce(0, +)
            if unknownTotal > 0 {
                let dummyCat = Category(
                    id: UUID(),
                    name: "不明なカテゴリ",
                    colorHex: "#757575",
                    type: type == .expense ? .expense : .income,
                    order: 998
                )
                sections.append(CategorySection(
                    category: dummyCat,
                    amount: unknownTotal,
                    color: Color(hex: "#757575")
                ))
            }
            
            // 3. 未分類 (categoryId == nil)
            if uncategorizedTotal > 0 {
                let dummyCat = Category(
                    id: UUID(),
                    name: "未分類",
                    colorHex: "#9E9E9E",
                    type: type == .expense ? .expense : .income,
                    order: 999
                )
                sections.append(CategorySection(
                    category: dummyCat,
                    amount: uncategorizedTotal,
                    color: Color(hex: "#9E9E9E")
                ))
            }
            
            // 金額順ソート（パーセンテージ計算用）
            sections.sort { $0.amount > $1.amount }
            
            return GraphData(type: type, sections: sections, total: grandTotal)
        }
    }
    
    private var chartData: GraphData {
        let allCategories = dataStore.expenseCategories + dataStore.incomeCategories
        return GraphData.build(
            type: selectedGraphType,
            currentDate: currentDate,
            transactions: dataStore.transactions,
            categories: allCategories
        )
    }

    // 横スワイプでグラフ種別を切り替え
    private func moveGraphType(_ delta: Int) {
        let types = enabledGraphTypesOrdered
        guard !types.isEmpty else { return }
        guard let currentIndex = types.firstIndex(of: selectedGraphType) else {
            selectedGraphType = types.first!
            return
        }
        let count = types.count
        let nextIndex = (currentIndex + delta % count + count) % count
        withAnimation {
            selectedGraphType = types[nextIndex]
        }
    }

    private var graphSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 50)  // 最小距離を増やしてスクロールと競合しにくく
            .onEnded { value in
                // 縦スクロールを邪魔しないよう、横方向が優位なときだけ反応
                let dx = value.translation.width
                let dy = value.translation.height
                // 横方向が縦方向の2倍以上で、かつ60px以上のスワイプのみ反応
                guard abs(dx) > abs(dy) * 2, abs(dx) > 60 else { return }

                if dx < 0 {
                    // 左スワイプ = 次
                    moveGraphType(1)
                } else {
                    // 右スワイプ = 前
                    moveGraphType(-1)
                }
            }
    }
    
    private var enabledGraphTypesOrdered: [GraphType] {
        settings.graphTypeOrder.filter { settings.enabledGraphTypes.contains($0) }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                graphTypeSelector
                
                ScrollView {
                    VStack(spacing: 0) {
                        chartContent
                    }
                }
                .simultaneousGesture(graphSwipeGesture)  // スクロールと共存
                .background(Color(.systemGroupedBackground))
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .padding(.top, -12)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    let now = Date()
                    let cal = Calendar.current
                    if cal.component(.year, from: currentDate) != cal.component(.year, from: now) ||
                        cal.component(.month, from: currentDate) != cal.component(.month, from: now) {
                        Button {
                            withAnimation {
                                currentDate = now
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "calendar.badge.clock")
                                Text("今月")
                            }
                            .font(.subheadline)
                        }
                    }
                }

                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        Button {
                            HapticManager.shared.selection()
                            withAnimation(AppTheme.Animation.springDefault) {
                                if let newDate = Calendar.current.date(byAdding: .month, value: -1, to: currentDate) {
                                    currentDate = newDate
                                }
                            }
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .bold))
                                .padding(.horizontal, 4)
                        }

                        Text(currentDate.yearMonthString)
                            .font(AppTheme.Typography.headlineMedium)
                            .layoutPriority(1)

                        Button {
                            HapticManager.shared.selection()
                            withAnimation(AppTheme.Animation.springDefault) {
                                if let newDate = Calendar.current.date(byAdding: .month, value: 1, to: currentDate) {
                                    currentDate = newDate
                                }
                            }
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 16, weight: .bold))
                                .padding(.horizontal, 4)
                        }
                    }
                    .foregroundStyle(Color.themeBlue)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("並び替え") {
                        showReorderSheet = true
                    }
                }
            }
            .sheet(isPresented: $showReorderSheet) {
                GraphTypeReorderView()
            }
            .onChange(of: currentDate) { _, newValue in
                // 月が変わったら固定費を処理
                dataStore.processFixedCosts(for: newValue)
            }
        }
    }
    
    
    private var graphTypeSelector: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(enabledGraphTypesOrdered) { type in
                        Button {
                            withAnimation {
                                selectedGraphType = type
                            }
                        } label: {
                            Text(type.displayName)
                                .font(.subheadline)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(
                                    selectedGraphType == type
                                    ? Color.themeBlue.opacity(0.15)
                                    : Color(.systemBackground)
                                )
                                .foregroundStyle(
                                    selectedGraphType == type
                                    ? Color.themeBlue
                                    : .primary
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(
                                            selectedGraphType == type
                                            ? Color.themeBlue
                                            : Color(.systemGray4),
                                            lineWidth: 1
                                        )
                                )
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                        .id(type)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 4)
                .padding(.bottom, 12)
            }
            .background(Color(.systemGray6))
            .onChange(of: selectedGraphType) { _, newValue in
                withAnimation {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
        .navigationDestination(item: $selectedCategoryDetail) { detail in
            CategoryDetailGraphView(categoryId: detail.categoryId, type: detail.type)
        }
    }
    
    @ViewBuilder
    private var chartContent: some View {
        switch selectedGraphType {
        case .expense:
            categoryPieChart(type: .expense)
        case .income:
            categoryPieChart(type: .income)
        case .savings:
            savingsChart
        case .yearlyExpense:
            yearlyBarChart(type: .expense)
        case .yearlyIncome:
            yearlyBarChart(type: .income)
        case .incomeTrend:
            incomeTrendChart
        case .budget:
            budgetChart
        }
    }
    
    private func categoryPieChart(type: TransactionType) -> some View {
        let sectionType = GraphType(rawValue: type.rawValue) ?? .expense
        let data = chartData
        // グラフ種別が一致しない場合は空を表示（切り替えアニメーション中など）
        if data.type != sectionType {
            return AnyView(EmptyView())
        }
        
        return AnyView(CategoryPieChart(
            data: data,
            selectedCategoryDetail: $selectedCategoryDetail
        ))
    }

    // Optimization: Extracted Subview
    private struct CategoryPieChart: View {
        let data: GraphData
        @Binding var selectedCategoryDetail: CategoryDetailInfo?
        
        var body: some View {
            VStack(spacing: 0) {
                ZStack {
                    if data.sections.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "chart.pie")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                            Text("データがありません")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Chart(data.sections) { item in
                            SectorMark(
                                angle: .value("金額", item.amount),
                                innerRadius: .ratio(0.55),
                                angularInset: 1.5
                            )
                            .cornerRadius(4)
                            .foregroundStyle(item.color)
                        }
                        .chartLegend(.hidden)
                        
                        VStack(spacing: 2) {
                            Text("合計")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(data.total.currencyFormatted)
                                .font(.headline)
                                .fontWeight(.bold)
                        }
                    }
                }
                .frame(height: 250)
                .padding()
                .background(Color(.systemBackground))
                
                VStack(spacing: 0) {
                    HStack {
                        Text("合計")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                        Text(data.total.currencyFormatted)
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .foregroundStyle(.primary)
                    .frame(minHeight: 50)
                    .padding(.horizontal, 16)
                    
                    Divider()
                    
                    ForEach(data.sections) { item in
                        Button {
                            // GraphType(data.type) -> TransactionType への変換が必要
                            let txType = TransactionType(rawValue: data.type.rawValue) ?? .expense
                            selectedCategoryDetail = CategoryDetailInfo(categoryId: item.category.id, type: txType)
                        } label: {
                            HStack {
                                Circle()
                                    .fill(item.color)
                                    .frame(width: 12, height: 12)
                                
                                Text(item.category.name)
                                    .font(.subheadline)
                                
                                Spacer()
                                
                                let percent = data.total > 0 ? Double(item.amount) / Double(data.total) * 100 : 0
                                Text(String(format: "%.1f%%", percent))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                
                                Text(item.amount.currencyFormatted)
                                    .font(.subheadline)
                                
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .foregroundStyle(.primary)
                            .frame(minHeight: 50)
                            .padding(.horizontal, 16)
                            .contentShape(Rectangle())
                        }
                        
                        if item.id != data.sections.last?.id {
                            Divider().padding(.leading, 40)
                        }
                    }
                }
                .background(Color(.systemBackground))
            }
        }
    }
    
    private var savingsChart: some View {
        let income = dataStore.monthlyIncome(for: currentDate)
        let expense = dataStore.monthlyExpense(for: currentDate)
        let savings = income - expense
        
        let calendar = Calendar.current
        var monthlyData: [MonthlyChartData] = []
        
        for i in (0..<12).reversed() {
            guard let date = calendar.date(byAdding: .month, value: -i, to: currentDate) else { continue }
            let inc = dataStore.monthlyIncome(for: date)
            let exp = dataStore.monthlyExpense(for: date)
            monthlyData.append(MonthlyChartData(month: "\(date.month)月", amount: inc - exp))
        }
        
        return VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text("今月の貯金額")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                
                Text(savings.currencyFormatted)
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(savings >= 0 ? Color(UIColor.systemGreen) : Color(UIColor.systemRed))
                
                HStack(spacing: 40) {
                    VStack(spacing: 4) {
                        Text("収入")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        Text(income.currencyFormatted)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(Color(UIColor.systemBlue))
                    }
                    
                    VStack(spacing: 4) {
                        Text("支出")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        Text(expense.currencyFormatted)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(Color(UIColor.systemRed))
                    }
                }
            }
            .padding()
            .background(Color(.systemBackground))
            
            VStack(alignment: .leading, spacing: 12) {
                Text("貯金額推移")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                
                Chart(monthlyData) { item in
                    BarMark(
                        x: .value("月", item.month),
                        y: .value("貯金額", item.amount)
                    )
                    .foregroundStyle(item.amount >= 0 ? Color(UIColor.systemGreen).opacity(0.7) : Color(UIColor.systemRed).opacity(0.7))
                }
                .frame(height: 200)
                .padding(.horizontal)
            }
            .padding(.vertical)
            .background(Color(.systemBackground))
        }
    }
    
    private func yearlyBarChart(type: TransactionType) -> some View {
        let calendar = Calendar.current
        var monthlyData: [MonthlyChartData] = []
        
        for i in (0..<12).reversed() {
            guard let date = calendar.date(byAdding: .month, value: -i, to: currentDate) else { continue }
            let amount = type == .expense
            ? dataStore.monthlyExpense(for: date)
            : dataStore.monthlyIncome(for: date)
            monthlyData.append(MonthlyChartData(month: "\(date.month)月", amount: amount))
        }
        
        let total = monthlyData.reduce(0) { $0 + $1.amount }
        
        return VStack(spacing: 16) {
            VStack(spacing: 8) {
                Text(type == .expense ? "年間支出" : "年間収入")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                
                Text(total.currencyFormatted)
                .font(.system(size: 28, weight: .bold))
            }
            .padding()
            .background(Color(.systemBackground))
            
            VStack(alignment: .leading, spacing: 12) {
                Text("月別推移")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                
                Chart(monthlyData) { item in
                    BarMark(
                        x: .value("月", item.month),
                        y: .value("金額", item.amount)
                    )
                    .foregroundStyle(type == .expense ? Color(UIColor.systemRed).opacity(0.7) : Color(UIColor.systemBlue).opacity(0.7))
                }
                .frame(height: 200)
                .padding(.horizontal)
            }
            .padding(.vertical)
            .background(Color(.systemBackground))
        }
    }
    
    private var incomeTrendChart: some View {
        let calendar = Calendar.current
        var monthlyData: [IncomeTrendData] = []
        
        for i in (0..<12).reversed() {
            guard let date = calendar.date(byAdding: .month, value: -i, to: currentDate) else { continue }
            monthlyData.append(IncomeTrendData(
                month: "\(date.month)月",
                income: dataStore.monthlyIncome(for: date),
                expense: dataStore.monthlyExpense(for: date)
            ))
        }
        
        return VStack(spacing: 16) {
            Text("収支推移")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            
            Chart {
                ForEach(monthlyData) { item in
                    LineMark(
                        x: .value("月", item.month),
                        y: .value("収入", item.income)
                    )
                    .foregroundStyle(Color(UIColor.systemBlue))
                    .symbol(Circle())
                    
                    LineMark(
                        x: .value("月", item.month),
                        y: .value("支出", item.expense)
                    )
                    .foregroundStyle(Color(UIColor.systemRed))
                    .symbol(Circle())
                }
            }
            .frame(height: 250)
            .padding()
            
            HStack(spacing: 20) {
                HStack(spacing: 4) {
                    Circle().fill(Color(UIColor.systemBlue)).frame(width: 10, height: 10)
                    Text("収入").font(.caption)
                }
                HStack(spacing: 4) {
                    Circle().fill(Color(UIColor.systemRed)).frame(width: 10, height: 10)
                    Text("支出").font(.caption)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
    }
    
    private var budgetChart: some View {
        let totalBudget = dataStore.totalBudget()
        let expense = dataStore.monthlyExpense(for: currentDate)
        
        return VStack(spacing: 20) {
            Text("予算")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            
            if let budget = totalBudget {
                let remaining = budget.amount - expense
                let progress = min(Double(expense) / Double(budget.amount), 1.0)
                
                VStack(spacing: 12) {
                    // 達成エフェクト
                    if remaining >= 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "star.fill")
                            Text("予算達成中！")
                                .fontWeight(.bold)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(Color.green)
                                .shadow(color: .green.opacity(0.5), radius: 10)
                        )
                        .padding(.bottom, 8)
                    }

                    Text(remaining >= 0 ? "残り" : "超過")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    
                    Text(abs(remaining).currencyFormatted)
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(remaining >= 0 ? Color(UIColor.systemGreen) : Color(UIColor.systemRed))
                    
                    ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(progress > 0.8 ? Color(UIColor.systemRed) : Color(UIColor.systemBlue))
                    .padding(.horizontal, 40)
                    
                    HStack {
                        Text("支出: \(expense.currencyFormatted)")
                        Text("/")
                        Text("予算: \(budget.amount.currencyFormatted)")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            } else {
                Text("予算が設定されていません")
                .foregroundStyle(.secondary)
                
                Text("設定 > 予算設定 から設定できます")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(Color(.systemBackground))
    }
}

// MARK: - Helper Structures
struct CategorySection: Identifiable, Equatable {
    let id = UUID()
    let category: Category
    let amount: Int
    let color: Color
}

struct CategoryDetailInfo: Identifiable, Hashable {
    let id = UUID()
    let categoryId: UUID
    let type: TransactionType

    static func == (lhs: CategoryDetailInfo, rhs: CategoryDetailInfo) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct CategoryChartData: Identifiable {
    let id = UUID() // Chart Identifiableのため
    let categoryId: UUID
    let name: String
    let amount: Int
    let color: Color
    let percent: Double
}

struct MonthlyChartData: Identifiable {
    let id = UUID()
    let month: String
    let amount: Int
}

struct IncomeTrendData: Identifiable {
    let id = UUID()
    let month: String
    let income: Int
    let expense: Int
}

// MARK: - Category Detail Graph View
struct CategoryDetailGraphView: View {
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.dismiss) private var dismiss
    
    let categoryId: UUID
    let type: TransactionType
    
    @State private var selectedMonthTransactions: [Transaction]? = nil
    @State private var selectedMonthDate: Date? = nil
    
    private var showMonthTransactions: Binding<Bool> {
        Binding(
            get: { selectedMonthTransactions != nil },
            set: { if !$0 { selectedMonthTransactions = nil; selectedMonthDate = nil } }
        )
    }
    
    private var categoryName: String {
        dataStore.categoryName(for: categoryId)
    }
    
    private var monthlyData: [MonthDateData] {
        let calendar = Calendar.current
        var data: [MonthDateData] = []
        
        for i in (0..<12).reversed() {
            guard let date = calendar.date(byAdding: .month, value: -i, to: Date()) else { continue }
            let amount = dataStore.categoryTotal(categoryId: categoryId, type: type, month: date)
            data.append(MonthDateData(date: date, amount: amount))
        }
        
        return data
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let category = dataStore.category(for: categoryId) {
                    HStack {
                        Circle()
                        .fill(category.color)
                        .frame(width: 32, height: 32)
                        Text(category.name)
                        .font(.title2)
                        .fontWeight(.bold)
                    }
                    .padding(.top)
                } else {
                    // カテゴリが見つからない場合（削除済みなど）
                    Text(categoryName)
                        .font(.title2)
                        .fontWeight(.bold)
                        .padding(.top)
                }
                
                Chart(monthlyData) { item in
                    BarMark(
                        x: .value("月", item.date, unit: .month),
                        y: .value("金額", item.amount)
                    )
                    .foregroundStyle(type == .expense ? Color(UIColor.systemRed).opacity(0.7) : Color(UIColor.systemBlue).opacity(0.7))
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .month)) { value in
                        if let date = value.as(Date.self) {
                            AxisValueLabel {
                                Text("\(date.month)月")
                                .font(.caption)
                            }
                        }
                    }
                }
                .frame(height: 250)
                .padding()
                
                VStack(spacing: 0) {
                    ForEach(monthlyData.reversed()) { item in
                        Button {
                            showTransactions(for: item.date)
                        } label: {
                            HStack {
                                Text(item.date.yearMonthString)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                                Spacer()
                                Text(item.amount.currencyFormatted)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(.primary)
                                if item.amount > 0 {
                                    Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                            }
                            .frame(minHeight: 44)
                            .padding(.horizontal)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        
                        if item.id != monthlyData.reversed().last?.id {
                            Divider().padding(.leading, 16)
                        }
                    }
                }
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("月別推移")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: showMonthTransactions) {
            if let transactions = selectedMonthTransactions, let date = selectedMonthDate {
                CategoryMonthTransactionsView(
                    transactions: transactions,
                    categoryId: categoryId,
                    date: date,
                    type: type
                )
            }
        }
    }
    
    private func showTransactions(for date: Date) {
        let transactions = dataStore.transactionsForMonth(date)
            .filter { $0.type == type && $0.categoryId == categoryId }
            .sorted { $0.date > $1.date }
        
        guard !transactions.isEmpty else { return }
        
        selectedMonthDate = date
        selectedMonthTransactions = transactions
        
        // ハプティックフィードバック
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

// MARK: - Category Month Transactions View
struct CategoryMonthTransactionsView: View {
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.dismiss) private var dismiss
    
    let transactions: [Transaction]
    let categoryId: UUID
    let date: Date
    let type: TransactionType
    
    @State private var editingTransaction: Transaction? = nil
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(transactions) { tx in
                    Button {
                        editingTransaction = tx
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(tx.date.formatted(date: .abbreviated, time: .omitted))
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                                
                                if !tx.memo.isEmpty {
                                    Text(tx.memo)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                }
                            }
                            
                            Spacer()
                            
                            Text(tx.amount.currencyFormatted)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(type == .expense ? Color(UIColor.systemRed) : Color(UIColor.systemBlue))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            deleteTransaction(tx)
                        } label: {
                            Label("削除", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle("\(date.yearMonthString) - \(dataStore.categoryName(for: categoryId))")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $editingTransaction) { tx in
                TransactionInputView(
                    preselectedDate: tx.date,
                    editingTransaction: tx,
                    dismissAfterSave: true
                ) {
                    editingTransaction = nil
                }
            }
        }
    }
    
    private func deleteTransaction(_ transaction: Transaction) {
        withAnimation {
            dataStore.deleteTransaction(transaction)
        }
        // ハプティックフィードバック
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
}

struct MonthDateData: Identifiable {
    let id = UUID()
    let date: Date
    let amount: Int
}

// MARK: - Graph Type Reorder View
struct GraphTypeReorderView: View {
    @EnvironmentObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(settings.graphTypeOrder, id: \.self) { type in
                    HStack {
                        Image(systemName: "line.3.horizontal")
                        .foregroundStyle(.secondary)
                        
                        Text(type.displayName)
                        
                        Spacer()
                        
                        if settings.enabledGraphTypes.contains(type) {
                            Image(systemName: "checkmark")
                            .foregroundStyle(Color.themeBlue)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        toggleType(type)
                    }
                }
                .onMove(perform: move)
            }
            .navigationTitle("グラフの並び替え")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                }
            }
        }
    }
    
    private func move(from source: IndexSet, to destination: Int) {
        settings.graphTypeOrder.move(fromOffsets: source, toOffset: destination)
    }
    
    private func toggleType(_ type: GraphType) {
        if settings.enabledGraphTypes.contains(type) {
            if settings.enabledGraphTypes.count > 1 {
                settings.enabledGraphTypes.remove(type)
            }
        } else {
            settings.enabledGraphTypes.insert(type)
        }
    }
}
