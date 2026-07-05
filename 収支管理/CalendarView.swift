import SwiftUI

struct CalendarView: View {
    @EnvironmentObject var dataStore: DataStore
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var deletionManager: DeletionManager

    @State private var currentDate = Date()
    @State private var selectedDate = Date()

    @State private var showInputView = false

    // 🔍検索
    @State private var showSearchView = false

    // カレンダーグリッドのダブルタップ用（明細編集はDayDetailViewが管理）
    @State private var editingTransaction: Transaction? = nil

    private var monthSummary: (income: Int, expense: Int, balance: Int, carryOver: Int) {
        let income = dataStore.monthlyIncome(for: currentDate)
        let expense = dataStore.monthlyExpense(for: currentDate)
        let carryOver = settings.showPreviousBalance ? dataStore.previousMonthBalance(before: currentDate) : 0

        return (income, expense, income - expense, carryOver)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                calendarGrid
                    .padding(.horizontal, 8)

                summaryBar

                DayDetailView(date: selectedDate, embedded: true)
                    .frame(maxHeight: .infinity)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .padding(.top, -12)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !isSameMonth(currentDate, Date()) {
                        Button {
                            withAnimation {
                                currentDate = Date()
                                selectedDate = Date()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "calendar.badge.clock")
                                Text("今日")
                            }
                            .font(.subheadline)
                        }
                        .accessibilityLabel("今日に戻る")
                        .accessibilityHint("ダブルタップで今月のカレンダーに戻ります")
                    }
                }

                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        Button {
                            HapticManager.shared.selection()
                            withAnimation(AppTheme.Animation.springDefault) {
                                currentDate = addMonth(currentDate, delta: -1)
                            }
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .bold))
                                .padding(.horizontal, 4)
                        }
                        .accessibilityLabel("前の月へ")

                        Text(currentDate.yearMonthString)
                            .font(AppTheme.Typography.headlineMedium)
                            .layoutPriority(1)
                            .accessibilityLabel("\(currentDate.yearMonthString)を表示中")

                        Button {
                            HapticManager.shared.selection()
                            withAnimation(AppTheme.Animation.springDefault) {
                                currentDate = addMonth(currentDate, delta: 1)
                            }
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 16, weight: .bold))
                                .padding(.horizontal, 4)
                        }
                        .accessibilityLabel("次の月へ")
                    }
                    .foregroundStyle(Color.themeBlue)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSearchView = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .accessibilityLabel("取引を検索")
                    .accessibilityHint("ダブルタップでメモ検索画面を開きます")
                }
            }

            // 入力（カレンダーグリッドのダブルタップから起動）
            .sheet(isPresented: $showInputView) {
                TransactionInputView(
                    preselectedDate: selectedDate,
                    editingTransaction: editingTransaction,
                    dismissAfterSave: true
                ) {
                    showInputView = false
                    editingTransaction = nil
                }
            }

            // 🔍検索（メモ検索）
            .sheet(isPresented: $showSearchView) {
                TransactionSearchView()
            }
        }
        .onChange(of: currentDate) { _, newValue in
            // 月移動時に「存在しない日」になるのを防止（例: 31→30）
            let y = Calendar.current.component(.year, from: newValue)
            let m = Calendar.current.component(.month, from: newValue)
            let days = Date.daysInMonth(year: y, month: m)
            let newDay = min(Calendar.current.component(.day, from: selectedDate), days)
            selectedDate = Date.createDate(year: y, month: m, day: newDay)
        }
    }


    // MARK: - Calendar Grid（崩れ防止：必ず 6週(42マス)で描画）

    private var calendarGrid: some View {
        let weekDays = WeekDays.orderedNames(startingFrom: settings.weekStartDay)
        let dates = gridDates(for: currentDate, weekStartDay: settings.weekStartDay)
        
        // Optimisation: Fetch transactions once for the month
        let monthlyTransactions = dataStore.transactionsForMonth(currentDate)
        let transactionsByDay = Dictionary(grouping: monthlyTransactions) {
            Calendar.current.component(.day, from: $0.date)
        }

        return VStack(spacing: 0) {
            // 曜日行
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 7), spacing: 1) {
                ForEach(Array(weekDays.enumerated()), id: \.offset) { _, day in
                    Text(day)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(weekdayColor(for: day))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                        .padding(.bottom, 8)
                        .background(Color(.systemGray6))
                }
            }
            .background(Color(.systemGray5))

            // 日付マス（42個固定）
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 7), spacing: 1) {
                ForEach(dates, id: \.self) { date in
                    let day = Calendar.current.component(.day, from: date)
                    // 同月の場合のみ辞書から取得、それ以外は空（または必要なら別途取得だが、現状仕様ではグレーアウトで表示なし）
                    let txs = isSameMonth(date, currentDate) ? (transactionsByDay[day] ?? []) : []
                    dayCell(date: date, dayTransactions: txs)
                }
            }
            .background(Color(.systemGray5))
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.top, 0)
        .padding(.bottom, 8)
        .simultaneousGesture(
            DragGesture(minimumDistance: 20, coordinateSpace: .local)
                .onEnded { value in
                    // 横方向のスワイプだけ反応（縦スクロールと干渉しにくくする）
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }

                    if value.translation.width > 50 {
                        // 右フリック：前月
                        withAnimation {
                            currentDate = addMonth(currentDate, delta: -1)
                        }
                    } else if value.translation.width < -50 {
                        // 左フリック：次月
                        withAnimation {
                            currentDate = addMonth(currentDate, delta: 1)
                        }
                    }
                }
        )
    }

    private func dayCell(date: Date, dayTransactions: [Transaction]) -> some View {
        let cal = Calendar.current
        let day = cal.component(.day, from: date)

        let isInCurrentMonth = isSameMonth(date, currentDate)
        let isSelected = date.isSameDay(as: selectedDate)
        let isToday = date.isSameDay(as: Date())
        let weekday = cal.component(.weekday, from: date)

        // dayTransactions is passed in
        let income = dayTransactions.filter { $0.type == .income }.reduce(0) { $0 + $1.amount }
        let expense = dayTransactions.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }

        let dayColor: Color = {
            if !isInCurrentMonth { return .secondary }
            if isToday { return Color.themeBlue }
            if weekday == 1 { return Color(UIColor.systemRed) }   // 日
            if weekday == 7 { return Color(UIColor.systemBlue) }  // 土
            return .primary
        }()

        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("\(day)")
                    .font(.subheadline)
                    .fontWeight(isToday ? .bold : .medium)
                    .foregroundStyle(dayColor)
                Spacer()
            }

            if isInCurrentMonth {
                if income > 0 {
                    Text(income.currencyFormatted)
                        .font(.system(size: 8, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.income)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                if expense > 0 {
                    Text(expense.currencyFormatted)
                        .font(.system(size: 8, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.expense)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 55)
        .padding(.horizontal, 4)
        .padding(.top, 4)
        .background(
            isSelected ? Color.themeBlue.opacity(0.15)
            : (isInCurrentMonth ? Color(.systemBackground) : Color(.systemGray6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    (isInCurrentMonth && isToday) ? Color.themeBlue : Color.clear,
                    lineWidth: 2
                )
                .padding(2)
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(dayCellAccessibilityLabel(date: date, day: day, isInCurrentMonth: isInCurrentMonth, income: income, expense: expense))
        .accessibilityHint(isInCurrentMonth ? "タップで選択、ダブルタップで新規取引を追加" : "タップで月を移動して選択")
        .accessibilityAddTraits(isSelected ? .isSelected : [])

        // ▼ ダブルタップ：入力画面
        .highPriorityGesture(
            TapGesture(count: 2).onEnded {
                if !isInCurrentMonth {
                    withAnimation { currentDate = startOfMonth(date) }
                }
                selectedDate = date
                editingTransaction = nil
                showInputView = true
            }
        )

        // ▼ シングルタップ：日付選択（前月/翌月セルなら月も移動）
        .onTapGesture {
            if !isInCurrentMonth {
                withAnimation { currentDate = startOfMonth(date) }
            }
            selectedDate = date
        }
    }

    // MARK: - Summary

    private var summaryBar: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(spacing: 4) {
                    Text("収入")
                        .font(AppTheme.Typography.labelSmall)
                        .foregroundStyle(.secondary)
                    AnimatedCounter(
                        value: monthSummary.income,
                        font: AppTheme.Typography.amountSmall,
                        color: AppTheme.income
                    )
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("収入 \(monthSummary.income)円")

                VStack(spacing: 4) {
                    Text("支出")
                        .font(AppTheme.Typography.labelSmall)
                        .foregroundStyle(.secondary)
                    AnimatedCounter(
                        value: monthSummary.expense,
                        font: AppTheme.Typography.amountSmall,
                        color: AppTheme.expense
                    )
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("支出 \(monthSummary.expense)円")

                VStack(spacing: 4) {
                    Text("合計")
                        .font(AppTheme.Typography.labelSmall)
                        .foregroundStyle(.secondary)
                    AnimatedCounter(
                        value: monthSummary.balance,
                        font: AppTheme.Typography.amountSmall,
                        color: monthSummary.balance >= 0 ? .primary : AppTheme.expense
                    )
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("合計 \(monthSummary.balance)円")
            }
            .padding(.vertical, AppTheme.Spacing.sm)
            .padding(.horizontal, AppTheme.Spacing.lg)
            
            if settings.showPreviousBalance && monthSummary.carryOver != 0 {
                Divider().padding(.horizontal)
                HStack {
                    Text("前月繰越")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(monthSummary.carryOver.currencyFormatted)
                        .font(.caption2)
                        .foregroundStyle(monthSummary.carryOver >= 0 ? .secondary : AppTheme.expense)
                }
                .padding(.horizontal, AppTheme.Spacing.lg + 8)
                .padding(.vertical, 4)
            }

            if let overallBudget = overallBudgetForCurrentMonth {
                let remaining = overallBudget.amount - monthSummary.expense
                Divider().padding(.horizontal)
                HStack {
                    Text("予算残り")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if remaining >= 0 {
                        Text(remaining.currencyFormatted)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("\(abs(remaining).currencyFormatted) 超過")
                            .font(.caption2)
                            .foregroundStyle(AppTheme.expense)
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.lg + 8)
                .padding(.vertical, 4)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(remaining >= 0 ? "予算残り \(remaining)円" : "予算 \(abs(remaining))円超過")
            }
        }
        .background(Color(.systemBackground))
    }

    /// 当月の全体予算（categoryId == nil）を返す
    private var overallBudgetForCurrentMonth: Budget? {
        let cal = Calendar.current
        let year = cal.component(.year, from: currentDate)
        let month = cal.component(.month, from: currentDate)
        return dataStore.budgets.first { budget in
            budget.categoryId == nil && budget.year == year && budget.month == month
        }
    }

    // MARK: - Helpers

    private func dayCellAccessibilityLabel(date: Date, day: Int, isInCurrentMonth: Bool, income: Int, expense: Int) -> String {
        guard isInCurrentMonth else { return "\(day)日、別の月" }
        var label = "\(date.month)月\(day)日"
        if income > 0 { label += "、収入\(income.currencyFormatted)" }
        if expense > 0 { label += "、支出\(expense.currencyFormatted)" }
        if income == 0 && expense == 0 { label += "、取引なし" }
        return label
    }

    private func weekdayColor(for day: String) -> Color {
        if day == "日" { return Color(UIColor.systemRed) }
        if day == "土" { return Color(UIColor.systemBlue) }
        return .secondary
    }

    private func startOfMonth(_ date: Date) -> Date {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: date)
        return cal.date(from: comps) ?? date
    }

    private func addMonth(_ date: Date, delta: Int) -> Date {
        let cal = Calendar.current
        let base = startOfMonth(date)
        return cal.date(byAdding: .month, value: delta, to: base) ?? date
    }

    private func isSameMonth(_ a: Date, _ b: Date) -> Bool {
        let cal = Calendar.current
        let ca = cal.dateComponents([.year, .month], from: a)
        let cb = cal.dateComponents([.year, .month], from: b)
        return ca.year == cb.year && ca.month == cb.month
    }

    private func gridDates(for month: Date, weekStartDay: Int) -> [Date] {
        let cal = Calendar.current
        let first = startOfMonth(month)

        // Calendarのweekdayは 1(日)〜7(土)
        let firstWeekday = cal.component(.weekday, from: first)

        // 週の開始曜日(1〜7)との差分で「月初の左に何マス空けるか」を決める
        var leading = firstWeekday - weekStartDay
        if leading < 0 { leading += 7 }

        let gridStart = cal.date(byAdding: .day, value: -leading, to: first) ?? first

        // 6週(42マス)固定で返す → 表示崩れ/日付飛び防止
        return (0..<42).compactMap { cal.date(byAdding: .day, value: $0, to: gridStart) }
    }

}

