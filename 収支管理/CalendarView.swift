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

    // 明細：編集
    @State private var editingTransaction: Transaction? = nil
    
    // 複製
    @State private var showDuplicateSheet = false
    @State private var transactionToDuplicate: Transaction? = nil
    @State private var duplicateDate: Date = Date()
    
    // 振替編集
    @State private var showTransferEdit = false
    @State private var editingTransfer: Transaction? = nil

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

                dayDetailSection
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

                        Text(currentDate.yearMonthString)
                            .font(AppTheme.Typography.headlineMedium)
                            .layoutPriority(1)

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
                    }
                    .foregroundStyle(Color.themeBlue)
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSearchView = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                }
            }

            // 入力（追加/編集）
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
            
            // 振替編集
            .sheet(isPresented: $showTransferEdit) {
                TransferInputView(editingTransaction: editingTransfer) {
                    showTransferEdit = false
                    editingTransfer = nil
                }
            }

            // 🔍検索（メモ検索）
            .sheet(isPresented: $showSearchView) {
                TransactionSearchView()
            }
            
            // 複製
            .sheet(isPresented: $showDuplicateSheet) {
                DuplicateTransactionSheet(
                    transaction: transactionToDuplicate,
                    targetDate: $duplicateDate,
                    onDuplicate: { date in
                        if let tx = transactionToDuplicate {
                            dataStore.duplicateTransaction(tx, toDate: date)
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                        }
                        showDuplicateSheet = false
                        transactionToDuplicate = nil
                    }
                )
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

            if isInCurrentMonth, income > 0 {
                Text("+\(income.currencyFormattedShort)")
                    .font(.system(size: 9, weight: .semibold))
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(Color(UIColor.systemBlue))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            if isInCurrentMonth, expense > 0 {
                Text("-\(expense.currencyFormattedShort)")
                    .font(.system(size: 9, weight: .semibold))
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(Color(UIColor.systemRed))
                    .lineLimit(1)
                    .truncationMode(.tail)
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
        }
        .background(Color(.systemBackground))
    }

    // MARK: - Day List

    private var dayDetailSection: some View {
        let dayTransactions = dataStore.sortedTransactionsForDate(
            selectedDate,
            sortOrder: settings.sameDaySortOrder
        )

        return Group {
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
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    // フルスワイプまたはボタンタップで即座に削除
                                    deleteTransaction(transaction)
                                } label: {
                                    Label("削除", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    transactionToDuplicate = transaction
                                    duplicateDate = selectedDate
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
    }

    private func transactionRow(_ transaction: Transaction) -> some View {
        // IDからカテゴリ取得
        let category = dataStore.category(for: transaction.categoryId)
        let accountStore = AccountStore.shared
        // 振替の場合は動的に口座名を解決
        let displayName: String = {
            if transaction.isTransfer {
                return transaction.transferDisplayLabel(accountStore: accountStore)
            } else if let category = category {
                return category.name
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
                // 振替はアイコンで表示
                Image(systemName: "arrow.left.arrow.right")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .frame(width: 12, height: 12)
            } else if let category = category {
                Circle()
                    .fill(category.color)
                    .frame(width: 12, height: 12)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.subheadline)
                    .foregroundStyle(.primary)

                if !transaction.memo.isEmpty {
                    Text(transaction.memo)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
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
        .frame(minHeight: 50)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())

        // タップ：編集
        .onTapGesture {
            if transaction.type == .transfer {
                editingTransfer = transaction
                showTransferEdit = true
            } else {
                editingTransaction = transaction
                selectedDate = transaction.date
                showInputView = true
            }
        }
    }

    // MARK: - Helpers

    private func deleteTransaction(_ transaction: Transaction) {
        withAnimation {
            deletionManager.deleteTransaction(transaction, from: dataStore)
        }
        // ハプティックフィードバック
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
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

extension CalendarView {
    // 既存の DayDetailView は CalendarView内に定義されていたが、
    // CalendarView内で直接 dayDetailSection を使っており、DayDetailViewは使われていなかった可能性がある、
    // あるいは別画面（例えばウィジェットからのリンク）で使われていたか？
    // File contentを見ると、末尾に extension CalendarView { struct DayDetailView ... } がある。
    // しかしCalendarView.body内で使われている形跡はない。
    // DayDetailView単体で使われるケースがあるなら更新必須。
    // ここも更新しておきます。

    struct DayDetailView: View {
        @EnvironmentObject var dataStore: DataStore
        @EnvironmentObject var settings: AppSettings
        @EnvironmentObject var deletionManager: DeletionManager

        let date: Date

        @State private var showInputView = false
        @State private var editingTransaction: Transaction?

        var body: some View {
            List {
                let transactions = dataStore.sortedTransactionsForDate(date, sortOrder: settings.sameDaySortOrder)

                ForEach(transactions) { transaction in
                    HStack {
                        // カテゴリ名参照
                        Text(dataStore.categoryName(for: transaction.categoryId))
                        Spacer()
                        Text(transaction.amount.currencyFormatted)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        editingTransaction = transaction
                        showInputView = true
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            deleteTransaction(transaction)
                        } label: {
                            Label("削除", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle(date.formatted(date: .abbreviated, time: .omitted))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editingTransaction = nil
                        showInputView = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
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
        }
        
        private func deleteTransaction(_ transaction: Transaction) {
            withAnimation {
                deletionManager.deleteTransaction(transaction, from: dataStore)
            }
            // ハプティックフィードバック
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
    }
}
