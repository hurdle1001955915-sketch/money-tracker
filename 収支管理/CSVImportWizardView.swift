import SwiftUI

// MARK: - CSV Import Wizard View (Phase 2 + Phase 3-2 + Phase 3-3)
// ウィザード形式のCSVインポート画面

struct CSVImportWizardView: View {
    @StateObject private var wizardState = ImportWizardState()
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.dismiss) private var dismiss

    @State private var showFilePicker = false
    @State private var showCancelConfirmation = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // プログレスバー
                WizardProgressBar(currentStep: wizardState.currentStep)
                    .padding(.horizontal)
                    .padding(.top, 4)

                // コンテンツ
                Group {
                    switch wizardState.currentStep {
                    case .settings:
                        ImportWizardStep0View(
                            state: wizardState,
                            showFilePicker: $showFilePicker
                        )
                    case .preview:
                        ImportWizardStep1View(state: wizardState)
                    case .resolve:
                        ImportWizardStep2View(state: wizardState)
                    case .summary:
                        ImportWizardStep3View(state: wizardState, onDismiss: { dismiss() })
                    }
                }
                .environmentObject(dataStore)
            }
            .navigationTitle("CSVインポート")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("キャンセル") {
                        if wizardState.draftRows.isEmpty {
                            dismiss()
                        } else {
                            showCancelConfirmation = true
                        }
                    }
                }
            }
            .sheet(isPresented: $showFilePicker) {
                CSVDocumentPicker { url in
                    loadCSVFile(from: url)
                }
            }
            .alert("インポートを中止しますか？", isPresented: $showCancelConfirmation) {
                Button("中止", role: .destructive) {
                    dismiss()
                }
                Button("続ける", role: .cancel) {}
            } message: {
                Text("現在の変更内容は保存されません。")
            }
            .overlay {
                if wizardState.isProcessing {
                    ProcessingOverlayView()
                }
            }
        }
    }

    private func loadCSVFile(from url: URL) {
        // 新しいファイルを読み込む前に状態をリセット
        wizardState.reset()

        // エンコーディング検出
        let encodings: [String.Encoding] = [.utf8, .utf16, .shiftJIS, .japaneseEUC]
        var loadedText: String? = nil

        for encoding in encodings {
            if let text = try? String(contentsOf: url, encoding: encoding) {
                loadedText = text
                break
            }
        }

        guard let csvText = loadedText else {
            wizardState.errorMessage = "ファイルの読み込みに失敗しました"
            return
        }

        wizardState.csvText = csvText
        wizardState.fileName = url.lastPathComponent
        wizardState.fileHash = dataStore.calculateCSVHash(csvText)

        // フォーマット自動検出（ファイル選択直後に実行）
        let detectionResults = CSVFormatDetector.detectWithConfidence(from: csvText)
        if let bestMatch = detectionResults.first {
            wizardState.selectedFormat = bestMatch.format
            print("[CSVImport] フォーマット自動検出: \(bestMatch.format.displayName) (確信度: \(bestMatch.confidence), 理由: \(bestMatch.reason))")
        }
    }
}

// MARK: - Wizard Progress Bar

struct WizardProgressBar: View {
    let currentStep: ImportWizardStep

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ImportWizardStep.allCases, id: \.self) { step in
                stepIndicator(step)
                if step != ImportWizardStep.allCases.last {
                    connectorLine(isCompleted: step.rawValue < currentStep.rawValue)
                }
            }
        }
        .padding(.vertical, 8)
    }

    private func stepIndicator(_ step: ImportWizardStep) -> some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(stepColor(step))
                    .frame(width: 24, height: 24)

                if step.rawValue < currentStep.rawValue {
                    Image(systemName: "checkmark")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                } else {
                    Text("\(step.rawValue + 1)")
                        .font(.caption.bold())
                        .foregroundStyle(step.rawValue <= currentStep.rawValue ? .white : .secondary)
                }
            }

            Text(step.title)
                .font(.caption2)
                .foregroundStyle(step == currentStep ? Color.primary : .secondary)
        }
    }

    private func connectorLine(isCompleted: Bool) -> some View {
        Rectangle()
            .fill(isCompleted ? Color.themeBlue : Color.gray.opacity(0.3))
            .frame(height: 2)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 4)
            .padding(.bottom, 14) // テキスト分のオフセット
    }

    private func stepColor(_ step: ImportWizardStep) -> Color {
        if step.rawValue < currentStep.rawValue {
            return .green
        } else if step == currentStep {
            return .themeBlue
        } else {
            return .gray.opacity(0.3)
        }
    }
}

// MARK: - Processing Overlay

struct ProcessingOverlayView: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)

                Text("処理中...")
                    .font(.headline)
                    .foregroundStyle(.white)
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemGray5))
            )
        }
    }
}

// MARK: - Step 0: Settings View

struct ImportWizardStep0View: View {
    @ObservedObject var state: ImportWizardState
    @Binding var showFilePicker: Bool
    @EnvironmentObject var dataStore: DataStore
    @StateObject private var accountStore = AccountStore.shared
    @State private var showMappingSheet = false

    var body: some View {
        Form {
            // フォーマット選択
            Section {
                Picker("形式", selection: $state.selectedFormat) {
                    ForEach(CSVImportFormat.allCases) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                
                if state.selectedFormat == .bankGeneric || state.selectedFormat == .cardGeneric {
                    Button {
                        showMappingSheet = true
                    } label: {
                        HStack {
                            Text("列マッピング設定")
                            Spacer()
                            if state.manualMapping != nil {
                                Text("設定済み")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            } else {
                                Image(systemName: "slider.horizontal.3")
                            }
                        }
                    }
                    .disabled(state.csvText.isEmpty)
                }

                Text(state.selectedFormat.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("インポート形式")
            }

            // 主体口座選択（Phase 3-3: 必須化）
            Section {
                Picker("主体口座", selection: $state.selectedAccountId) {
                    Text("指定なし").tag(nil as UUID?)
                    ForEach(accountStore.activeAccounts) { account in
                        HStack {
                            Circle()
                                .fill(account.color)
                                .frame(width: 12, height: 12)
                            Text(account.name)
                        }
                        .tag(account.id as UUID?)
                    }
                }
            } header: {
                Text("このCSVの口座")
            } footer: {
                Text("振替処理を正しく行うため、このCSVがどの口座の明細かを選択してください")
            }

            // ファイル選択
            Section {
                Button {
                    showFilePicker = true
                } label: {
                    HStack {
                        Image(systemName: "doc.badge.plus")
                        Text(state.fileName.isEmpty ? "ファイルを選択" : state.fileName)
                        Spacer()
                        if !state.fileName.isEmpty {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                }
            } header: {
                Text("CSVファイル")
            }

            // エラーメッセージ
            if let error = state.errorMessage {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }

            // 次へボタン
            Section {
                Button {
                    state.parseCSVToDraftRows(dataStore: dataStore)
                    if state.errorMessage == nil && !state.draftRows.isEmpty {
                        withAnimation {
                            state.currentStep = .preview
                        }
                    }
                } label: {
                    HStack {
                        Spacer()
                        Text("次へ")
                            .fontWeight(.semibold)
                        Image(systemName: "chevron.right")
                        Spacer()
                    }
                }
                .disabled(state.csvText.isEmpty)
            }
        }
        .sheet(isPresented: $showMappingSheet) {
            CSVMappingSheet(state: state)
        }
    }
}

// MARK: - Step 1: Preview View (Phase 3-2 Enhanced)

struct ImportWizardStep1View: View {
    @ObservedObject var state: ImportWizardState
    @EnvironmentObject var dataStore: DataStore

    @State private var selectedRow: ImportDraftRow?
    @State private var showBulkCategorizeSheet = false

    var body: some View {
        VStack(spacing: 0) {
            // Summary Card
            HStack(spacing: 6) {
                StatusCountView(
                    icon: "checkmark.circle.fill",
                    color: .green,
                    count: state.resolvedCount,
                    label: "解決済み"
                )
                StatusCountView(
                    icon: "exclamationmark.triangle.fill",
                    color: .orange,
                    count: state.unresolvedCount,
                    label: "未分類"
                )
                StatusCountView(
                    icon: "arrow.left.arrow.right.circle.fill",
                    color: .blue,
                    count: state.transferCandidateCount + state.transferConfirmedCount,
                    label: "振替"
                )
                StatusCountView(
                    icon: "doc.on.doc",
                    color: .gray,
                    count: state.duplicateCount,
                    label: "重複"
                )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.secondaryBackground)

            // Filter Segment & Selection Toggle
            HStack {
                Picker("フィルタ", selection: $state.filterMode) {
                    ForEach(PreviewFilterMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                
                // Selection Mode Toggle
                Button {
                    withAnimation {
                        state.toggleSelectionMode()
                    }
                } label: {
                    Image(systemName: state.isSelectionMode ? "checkmark.circle.fill" : "checkmark.circle")
                        .font(.title2)
                        .foregroundStyle(state.isSelectionMode ? .blue : .primary)
                }
                .padding(.leading, 8)
            }
            .padding(.horizontal)
            .padding(.vertical, 6)

            // Selection Status Bar (When active)
            if state.isSelectionMode {
                HStack {
                    Text("\(state.selectedTransactionIds.count)件選択中")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("すべて選択") {
                        state.selectAll()
                    }
                    .font(.caption)
                    .disabled(state.displayRows.isEmpty)

                    Text("|")
                        .foregroundStyle(.secondary)

                    Button("解除") {
                        state.deselectAll()
                    }
                    .font(.caption)
                    .disabled(state.selectedTransactionIds.isEmpty)
                }
                .padding(.horizontal)
                .padding(.bottom, 4)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Transfer Confirmed Count (Phase 3-2)
            if !state.isSelectionMode && state.transferConfirmedCount > 0 {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("振替確定: \(state.transferConfirmedCount)件")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.bottom, 4)
            }

            Divider()

            // Draft Rows List
            if state.displayRows.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "tray")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    
                    VStack(spacing: 8) {
                        Text("該当する取引がありません")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("フィルタ条件を変更するか、CSVデータを確認してください。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemGroupedBackground))
            } else {
                if state.isSelectionMode {
                    // 選択モード時: UICollectionViewベースのなぞり選択コンテナを使用
                    DragSelectableList(
                        items: state.displayRows,
                        selectedItems: $state.selectedTransactionIds,
                        isSelectionMode: $state.isSelectionMode,
                        cellContent: { row, isSelected in
                            DraftRowCell(
                                row: row,
                                categoryName: categoryName(for: row),
                                isSelectionMode: true,
                                isSelected: isSelected,
                                onTap: {
                                    selectedRow = row
                                },
                                onToggleSelection: {
                                    state.toggleSelection(for: row.id)
                                }
                            )
                        },
                        rowHeight: 80
                    )
                } else {
                    // 通常モード時: 標準Listを使用
                    List {
                        ForEach(state.displayRows) { row in
                            DraftRowCell(
                                row: row,
                                categoryName: categoryName(for: row),
                                isSelectionMode: false,
                                isSelected: false,
                                onTap: {
                                    selectedRow = row
                                },
                                onToggleSelection: { }
                            )
                        }
                    }
                    .listStyle(.plain)
                }
            }

            Divider()

            // Navigation or Bulk Actions
            if state.isSelectionMode {
                // Bulk Action Bar
                HStack(spacing: 16) {
                    Button {
                        state.bulkDelete()
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "trash")
                            Text("削除")
                                .font(.caption)
                        }
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(.red)
                    }
                    .disabled(state.selectedTransactionIds.isEmpty)
                    
                    Button {
                        showBulkCategorizeSheet = true
                    } label: {
                         VStack(spacing: 4) {
                            Image(systemName: "folder")
                            Text("カテゴリ分類")
                                .font(.caption)
                        }
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(.blue)
                    }
                    .disabled(state.selectedTransactionIds.isEmpty)
                }
                .padding()
                .background(Color.secondaryBackground)
                .transition(.move(edge: .bottom))
            } else {
                // Navigation Buttons (Original)
                HStack(spacing: 16) {
                    Button {
                        withAnimation {
                            state.currentStep = .settings
                        }
                    } label: {
                        HStack {
                            Image(systemName: "chevron.left")
                            Text("戻る")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.secondaryBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    if state.unresolvedCount > 0 || state.transferCandidateCount > 0 {
                        Button {
                            withAnimation {
                                state.currentStep = .resolve
                            }
                        } label: {
                            HStack {
                                Text("分類・振替へ")
                                Image(systemName: "chevron.right")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .foregroundStyle(.white)
                            .background(Color.orange)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    } else {
                        Button {
                            withAnimation {
                                state.currentStep = .summary
                            }
                        } label: {
                            HStack {
                                Text("保存前の確認")
                                Image(systemName: "chevron.right")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .foregroundStyle(.white)
                            .background(Color.themeBlue)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
                .padding()
            }
        }
        .sheet(item: $selectedRow) { row in
            DraftRowDetailSheet(
                row: row,
                state: state,
                dataStore: dataStore
            )
        }
        .sheet(isPresented: $showBulkCategorizeSheet) {
            BulkCategoryPickerSheet(state: state, dataStore: dataStore)
        }
    }

    private func categoryName(for row: ImportDraftRow) -> String? {
        guard let catId = row.resolvedCategoryId else { return nil }
        return dataStore.categoryName(for: catId)
    }
}

// MARK: - Bulk Category Picker Sheet
struct BulkCategoryPickerSheet: View {
    @ObservedObject var state: ImportWizardState
    var dataStore: DataStore
    @Environment(\.dismiss) private var dismiss
    
    @State private var saveRule: Bool = false
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("選択した取引をこのカテゴリで自動学習する", isOn: $saveRule)
                        .tint(.themeBlue)
                } footer: {
                     Text("オンにすると、選択した取引の説明文（キーワード）をルールとして保存し、次回から自動的にこのカテゴリに分類します。")
                }
                
                Section("収入カテゴリ") {
                    ForEach(dataStore.incomeCategories) { category in
                        CategoryPickerRow(
                            category: category,
                            onSelect: {
                                state.bulkApplyCategory(category.id, category.name, saveRule: saveRule)
                                dismiss()
                            }
                        )
                    }
                }
                
                Section("支出カテゴリ") {
                    ForEach(dataStore.expenseCategories) { category in
                        CategoryPickerRow(
                            category: category,
                            onSelect: {
                                state.bulkApplyCategory(category.id, category.name, saveRule: saveRule)
                                dismiss()
                            }
                        )
                    }
                }
            }
            .navigationTitle("カテゴリを選択")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

struct CategoryPickerRow: View {
    let category: Category
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack {
                Circle()
                    .fill(Color(hex: category.colorHex))
                    .frame(width: 12, height: 12)
                Text(category.name)
                Spacer()
            }
        }
    }
}

// MARK: - Status Count View

struct StatusCountView: View {
    let icon: String
    let color: Color
    let count: Int
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text("\(count)")
                    .fontWeight(.bold)
            }
            .font(.subheadline)

            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Draft Row Cell (Phase 3-2 Enhanced)

struct DraftRowCell: View {
    let row: ImportDraftRow
    let categoryName: String?
    let isSelectionMode: Bool
    let isSelected: Bool
    var onTap: (() -> Void)? = nil
    var onToggleSelection: (() -> Void)? = nil

    var body: some View {
        Button {
            if isSelectionMode {
                onToggleSelection?()
            } else {
                onTap?()
            }
        } label: {
            HStack(spacing: 0) {
                if isSelectionMode {
                    selectionCheckbox
                }

                indicatorBar
                
                VStack(alignment: .leading, spacing: 6) {
                    headerView
                    
                    HStack {
                        badgeView
                        Spacer()
                        amountView
                    }
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(row.status == .duplicate || row.status == .invalid ? 0.4 : 1.0)
    }
    
    private var selectionCheckbox: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.title3)
            .foregroundStyle(isSelected ? .blue : .gray)
            .padding(.trailing, 12)
            .transition(.scale.combined(with: .opacity))
    }
    
    private var indicatorBar: some View {
        Rectangle()
            .fill(amountColor)
            .frame(width: 4)
            .padding(.vertical, 4)
            .clipShape(Capsule())
            .padding(.trailing, 12)
    }
    
    private var headerView: some View {
        HStack(spacing: 8) {
            Text(row.date.fullDateString)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            
            Text(row.description)
                .font(.system(.subheadline, design: .rounded))
                .fontWeight(.bold)
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
    }
    
    @ViewBuilder
    private var badgeView: some View {
        if row.status == .transferCandidate || row.status == .transferConfirmed {
            Label(row.transferCandidateReason.displayName, systemImage: row.status.iconName)
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.blue)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.blue.opacity(0.1))
                .clipShape(Capsule())
        } else if let catName = categoryName {
            Text(catName)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color(.systemGray5))
                .clipShape(Capsule())
        } else {
            Text("未分類")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundStyle(.orange)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.orange.opacity(0.1))
                .clipShape(Capsule())
        }
    }
    
    private var amountView: some View {
        HStack(spacing: 2) {
            Text(row.amountSign.symbol)
                .font(.system(.subheadline, design: .rounded))
                .fontWeight(.heavy)
            Text(row.amount.currencyFormatted)
                .font(.system(.headline, design: .rounded))
                .fontWeight(.black)
        }
        .foregroundStyle(amountColor)
    }
    
    private var amountColor: Color {
        switch row.type {
        case .income: return .green
        case .expense: return .red
        case .transfer: return .blue
        }
    }
}

// MARK: - Draft Row Detail Sheet (Phase 3-2 + Phase 3-3)

struct DraftRowDetailSheet: View {
    let row: ImportDraftRow
    @ObservedObject var state: ImportWizardState
    let dataStore: DataStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var accountStore = AccountStore.shared

    @State private var selectedCategoryId: UUID?
    @State private var showCategoryPicker = false
    @State private var selectedCounterAccountId: UUID?

    var body: some View {
        NavigationStack {
            List {
                // 基本情報
                TransactionInfoSection(row: row)

                // ステータス
                ClassificationInfoSection(row: row, dataStore: dataStore)

                // 分類ルールの保存（Phase 3-4）
                if let catId = row.resolvedCategoryId, row.type != .transfer {
                    RuleSaveSection(row: row, state: state, categoryId: catId)
                }

                // 振替候補/確定の場合のアクション（Phase 3-3）
                if row.status == .transferCandidate || row.status == .transferConfirmed {
                    TransferSettingsSection(
                        row: row,
                        state: state,
                        accountStore: accountStore,
                        selectedCounterAccountId: $selectedCounterAccountId,
                        onRevert: {
                            state.revertTransferConfirmation(rowId: row.id)
                            dismiss()
                        },
                        onConfirm: { counterAccountId in
                            state.confirmTransfer(rowId: row.id, counterAccountId: counterAccountId)
                            dismiss()
                        },
                        onMarkNormal: {
                            showCategoryPicker = true
                        }
                    )
                }

                // 元CSV行
                Section {
                    Text(row.originalRow.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("元データ (行\(row.rowIndex + 1))")
                }

                // パースエラー
                if let error = row.parseError {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                    } header: {
                        Text("エラー")
                    }
                }
            }
            .navigationTitle("取引詳細")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showCategoryPicker) {
                NavigationStack {
                    CategorySelectionForDraftView(
                        type: row.type,
                        onSelect: { categoryId in
                            state.markAsNormalTransaction(rowId: row.id, categoryId: categoryId)
                            dismiss()
                        }
                    )
                    .environmentObject(dataStore)
                }
            }
            .onAppear {
                selectedCounterAccountId = row.counterAccountId
            }
        }
    }
}

// MARK: - DraftRowDetailSheet Subviews

struct TransactionInfoSection: View {
    let row: ImportDraftRow
    
    var body: some View {
        Section {
            LabeledContent("日付") {
                Text(row.date.fullDateString)
            }
            LabeledContent("説明") {
                Text(row.displayDescription)
            }
            LabeledContent("金額") {
                HStack {
                    Image(systemName: row.amountSign.icon)
                        .foregroundStyle(row.amountSign.color)
                    Text(row.amount.currencyFormatted)
                }
            }
            LabeledContent("方向") {
                Text(row.amountSign.displayName)
                    .foregroundStyle(row.amountSign.color)
            }
        } header: {
            Text("取引情報")
        }
    }
}

struct ClassificationInfoSection: View {
    let row: ImportDraftRow
    let dataStore: DataStore
    
    var body: some View {
        Section {
            LabeledContent("ステータス") {
                HStack {
                    Image(systemName: row.status.iconName)
                        .foregroundStyle(row.status.iconColor)
                    Text(row.status.displayName)
                }
            }

            if row.status == .transferCandidate || row.status == .transferConfirmed {
                LabeledContent("判定理由") {
                    Text(row.transferCandidateReason.displayName)
                        .foregroundStyle(.blue)
                }
            }

            if let catId = row.resolvedCategoryId {
                let catName = dataStore.categoryName(for: catId)
                if !catName.isEmpty {
                    LabeledContent("カテゴリ") {
                        Text(catName)
                    }
                }
            }

            if let aiReason = row.aiReason {
                VStack(alignment: .leading, spacing: 4) {
                    Text("AIの判定理由")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(aiReason)
                        .font(.subheadline)
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text("分類情報")
        }
    }
}

struct RuleSaveSection: View {
    let row: ImportDraftRow
    @ObservedObject var state: ImportWizardState
    let categoryId: UUID
    
    var body: some View {
        Section {
            Button {
                state.addRule(keyword: row.description, categoryId: categoryId, type: row.type)
            } label: {
                HStack {
                    Image(systemName: "plus.square.dashed")
                    Text("この分類をルールとして保存")
                }
            }
        } header: {
            Text("自動分類設定")
        } footer: {
            Text("次回インポート時から、『\(row.description)』を含む取引にこのカテゴリを自動的に割り当てます。")
        }
    }
}

struct TransferSettingsSection: View {
    let row: ImportDraftRow
    @ObservedObject var state: ImportWizardState
    @ObservedObject var accountStore: AccountStore
    @Binding var selectedCounterAccountId: UUID?
    let onRevert: () -> Void
    let onConfirm: (UUID) -> Void
    let onMarkNormal: () -> Void
    
    var body: some View {
        Section {
            // 相手口座選択
            Picker("相手口座", selection: $selectedCounterAccountId) {
                Text("選択してください").tag(nil as UUID?)
                ForEach(accountStore.activeAccounts.filter { $0.id != state.selectedAccountId }) { account in
                    HStack {
                        Circle()
                            .fill(account.color)
                            .frame(width: 12, height: 12)
                        Text(account.name)
                    }
                    .tag(account.id as UUID?)
                }
            }

            // 振替確定ボタン
            if row.status == .transferCandidate {
                Button {
                    if let counterAccountId = selectedCounterAccountId {
                        onConfirm(counterAccountId)
                    }
                } label: {
                    HStack {
                        Image(systemName: "checkmark.circle")
                        Text("振替として確定")
                    }
                }
                .disabled(selectedCounterAccountId == nil)
            } else {
                // 振替確定を解除
                Button(role: .destructive, action: onRevert) {
                    HStack {
                        Image(systemName: "xmark.circle")
                        Text("振替確定を解除")
                    }
                }
            }

            // 通常取引に変更ボタン
            Button(action: onMarkNormal) {
                HStack {
                    Image(systemName: "tag")
                    Text("通常の取引として分類する")
                }
            }
        } header: {
            Text("振替設定")
        } footer: {
            if row.status == .transferCandidate {
                Text("振替として保存する場合は相手口座を選択して確定してください。通常の支出/収入として保存する場合はカテゴリを選択してください。")
            }
        }
    }
}

// MARK: - Category Selection for Draft View (Phase 3-2)

struct CategorySelectionForDraftView: View {
    let type: TransactionType
    let onSelect: (UUID) -> Void
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedCategoryId: UUID?

    var body: some View {
        VStack {
            HierarchicalCategoryPicker(
                type: type,
                selectedCategoryId: $selectedCategoryId
            )
            .padding()

            Button {
                if let catId = selectedCategoryId {
                    onSelect(catId)
                }
            } label: {
                Text("適用")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundStyle(.white)
                    .background(selectedCategoryId != nil ? Color.themeBlue : Color.gray)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .disabled(selectedCategoryId == nil)
            .padding()
        }
        .navigationTitle("カテゴリを選択")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("キャンセル") {
                    dismiss()
                }
            }
        }
    }
}

// MARK: - Step 2: Resolve View (Phase 3-3 Enhanced with Tabs)

struct ImportWizardStep2View: View {
    @ObservedObject var state: ImportWizardState
    @EnvironmentObject var dataStore: DataStore
    @StateObject private var accountStore = AccountStore.shared

    var body: some View {
        VStack(spacing: 0) {
            // タブ切り替え
            Picker("モード", selection: $state.resolveTabMode) {
                HStack {
                    Text("未分類")
                    if state.unresolvedCount > 0 {
                        Text("(\(state.unresolvedCount))")
                            .foregroundStyle(.orange)
                    }
                }
                .tag(ResolveTabMode.unresolved)

                HStack {
                    Text("振替")
                    if state.transferCandidateCount > 0 {
                        Text("(\(state.transferCandidateCount))")
                            .foregroundStyle(.blue)
                    }
                }
                .tag(ResolveTabMode.transfer)
            }
            .pickerStyle(.segmented)
            .padding()

            // コンテンツ
            if state.resolveTabMode == .unresolved {
                UnresolvedResolveContent(state: state)
            } else {
                TransferResolveContent(state: state)
            }

            Divider()

            // ナビゲーションボタン
            HStack(spacing: 16) {
                Button {
                    withAnimation {
                        state.currentStep = .preview
                    }
                } label: {
                    HStack {
                        Image(systemName: "chevron.left")
                        Text("戻る")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.secondaryBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                Button {
                    withAnimation {
                        state.currentStep = .summary
                    }
                } label: {
                    HStack {
                        Text("次へ")
                        Image(systemName: "chevron.right")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundStyle(.white)
                    .background(canProceed ? Color.themeBlue : Color.gray)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .disabled(!canProceed)
            }
            .padding()
        }
    }

    private var canProceed: Bool {
        state.unresolvedCount == 0 && state.transferCandidateCount == 0
    }
}

// MARK: - Unresolved Resolve Content (Phase 3-3)

struct UnresolvedResolveContent: View {
    @ObservedObject var state: ImportWizardState
    @EnvironmentObject var dataStore: DataStore

    @State private var showAPIKeyAlert = false

    var body: some View {
        VStack(spacing: 0) {
            // ヘッダー
            VStack(spacing: 12) {
                HStack {
                    Text("未分類: \(state.unresolvedCount)件")
                        .font(.headline)
                    Spacer()
                    if state.unresolvedCount == 0 {
                        Label("すべて解決済み", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }

                // AI分類ボタンと進捗表示
                if state.unresolvedCount > 0 {
                    aiClassificationSection
                }

                // AI分類結果表示
                if let result = state.lastAIClassificationResult, state.showAIClassificationResult {
                    aiResultBanner(result)
                }
            }
            .padding()
            .background(Color.secondaryBackground)

            // グループリスト
            if state.unresolvedGroups.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.green)
                    Text("未分類はありません")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(state.unresolvedGroups) { group in
                        DescriptionGroupRow(
                            group: group,
                            onSelectCategory: { categoryId, saveAsRule, keyword in
                                state.applyCategoryToDescription(categoryId, description: group.description)

                                // Phase 3-3: ルール保存
                                if saveAsRule, !keyword.isEmpty {
                                    state.saveAsRule(keyword: keyword, categoryId: categoryId, type: group.type)
                                    state.reapplyClassificationRules(dataStore: dataStore)
                                }
                            }
                        )
                    }
                }
                .listStyle(.plain)
            }
        }
        .alert("APIキーが未設定", isPresented: $showAPIKeyAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("設定画面でOpenAI APIキーを登録してください。")
        }
    }

    // MARK: - AI Classification Section

    @ViewBuilder
    private var aiClassificationSection: some View {
        if state.isAIClassifying {
            // 処理中の進捗表示
            VStack(spacing: 8) {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("AI分類中...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                if let progress = state.aiClassificationProgress {
                    VStack(spacing: 4) {
                        ProgressView(value: progress.progressRatio)
                            .tint(.themeBlue)
                        Text(progress.displayText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 8)
        } else {
            // AI分類ボタン
            Button {
                if KeychainStore.hasOpenAIAPIKey {
                    Task {
                        await state.performAIClassification(dataStore: dataStore)
                    }
                } else {
                    showAPIKeyAlert = true
                }
            } label: {
                HStack {
                    Image(systemName: "sparkles")
                    Text("AI補完")
                    Text("(\(state.aiClassificationTargetCount)件)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .foregroundStyle(.white)
                .background(state.canPerformAIClassification ? Color.purple : Color.gray)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .disabled(!state.canPerformAIClassification)
        }
    }

    @ViewBuilder
    private func aiResultBanner(_ result: AIClassificationResult) -> some View {
        HStack {
            if result.isSuccess {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("AI分類: \(result.totalConfirmed)件を自動分類")
                    .font(.caption)
            } else {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(result.error?.localizedDescription ?? "エラーが発生しました")
                    .font(.caption)
                    .lineLimit(2)
            }
            Spacer()
            Button {
                state.showAIClassificationResult = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(result.isSuccess ? Color.green.opacity(0.1) : Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Transfer Resolve Content (Phase 3-3)

struct TransferResolveContent: View {
    @ObservedObject var state: ImportWizardState
    @EnvironmentObject var dataStore: DataStore
    @StateObject private var accountStore = AccountStore.shared

    @State private var selectedCounterAccountId: UUID?

    var body: some View {
        VStack(spacing: 0) {
            // ヘッダー
            VStack(spacing: 12) {
                HStack {
                    Text("振替候補: \(state.transferCandidateCount)件")
                        .font(.headline)
                    Spacer()
                    if state.transferCandidateCount == 0 {
                        Label("すべて解決済み", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }

                // 主体口座表示
                if let accountId = state.selectedAccountId,
                   let account = accountStore.account(for: accountId) {
                    HStack {
                        Text("主体口座:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Circle()
                            .fill(account.color)
                            .frame(width: 10, height: 10)
                        Text(account.name)
                            .font(.caption)
                    }
                }

                // 一括設定
                if state.transferCandidateCount > 0 {
                    VStack(spacing: 8) {
                        Picker("相手口座", selection: $selectedCounterAccountId) {
                            Text("選択してください").tag(nil as UUID?)
                            ForEach(accountStore.activeAccounts.filter { $0.id != state.selectedAccountId }) { account in
                                HStack {
                                    Circle()
                                        .fill(account.color)
                                        .frame(width: 12, height: 12)
                                    Text(account.name)
                                }
                                .tag(account.id as UUID?)
                            }
                        }
                        .pickerStyle(.menu)

                        Button {
                            if let counterAccountId = selectedCounterAccountId {
                                state.confirmAllTransferCandidates(counterAccountId: counterAccountId)
                            }
                        } label: {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                Text("すべて振替として確定")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .foregroundStyle(.white)
                            .background(selectedCounterAccountId != nil ? Color.blue : Color.gray)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .disabled(selectedCounterAccountId == nil)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }
            }
            .padding()
            .background(Color.secondaryBackground)

            // 振替候補リスト
            if state.transferCandidateRows.isEmpty && state.transferConfirmedCount == 0 {
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.green)
                    Text("振替候補はありません")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    // 未確定の振替候補
                    if !state.transferCandidateRows.isEmpty {
                        Section {
                            ForEach(state.transferCandidateRows) { row in
                                TransferCandidateRowView(row: row, state: state)
                            }
                        } header: {
                            Text("未確定 (\(state.transferCandidateCount)件)")
                        }
                    }

                    // 確定済みの振替
                    let confirmedRows = state.draftRows.filter { $0.status == .transferConfirmed }
                    if !confirmedRows.isEmpty {
                        Section {
                            ForEach(confirmedRows) { row in
                                TransferConfirmedRowView(row: row, state: state)
                            }
                        } header: {
                            Text("確定済み (\(state.transferConfirmedCount)件)")
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }
}

// MARK: - Transfer Candidate Row View

struct TransferCandidateRowView: View {
    let row: ImportDraftRow
    @ObservedObject var state: ImportWizardState
    @StateObject private var accountStore = AccountStore.shared

    @State private var selectedCounterAccountId: UUID?
    @State private var showCategoryPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 基本情報
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.date.fullDateString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(row.displayDescription)
                        .font(.subheadline)
                        .lineLimit(2)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 2) {
                        Image(systemName: row.amountSign.icon)
                            .font(.caption2)
                            .foregroundStyle(row.amountSign.color)
                        Text(row.amount.currencyFormatted)
                            .fontWeight(.medium)
                    }
                    Text(row.transferCandidateReason.displayName)
                        .font(.caption2)
                        .foregroundStyle(.blue)
                }
            }

            // 口座選択と確定
            HStack {
                Picker("相手口座", selection: $selectedCounterAccountId) {
                    Text("選択").tag(nil as UUID?)
                    ForEach(accountStore.activeAccounts.filter { $0.id != state.selectedAccountId }) { account in
                        Text(account.name).tag(account.id as UUID?)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 150)

                Button {
                    if let counterAccountId = selectedCounterAccountId {
                        state.confirmTransfer(rowId: row.id, counterAccountId: counterAccountId)
                    }
                } label: {
                    Text("確定")
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .foregroundStyle(.white)
                        .background(selectedCounterAccountId != nil ? Color.blue : Color.gray)
                        .clipShape(Capsule())
                }
                .disabled(selectedCounterAccountId == nil)

                Button {
                    showCategoryPicker = true
                } label: {
                    Text("通常取引")
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .foregroundStyle(.orange)
                        .background(Color.orange.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
        }
        .padding(.vertical, 4)
        .sheet(isPresented: $showCategoryPicker) {
            NavigationStack {
                CategorySelectionForDraftView(
                    type: row.type,
                    onSelect: { categoryId in
                        state.markAsNormalTransaction(rowId: row.id, categoryId: categoryId)
                    }
                )
            }
        }
    }
}

// MARK: - Transfer Confirmed Row View

struct TransferConfirmedRowView: View {
    let row: ImportDraftRow
    @ObservedObject var state: ImportWizardState
    @StateObject private var accountStore = AccountStore.shared

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.date.fullDateString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(row.displayDescription)
                    .font(.subheadline)
                    .lineLimit(1)

                // 相手口座表示
                if let counterAccountId = row.counterAccountId,
                   let account = accountStore.account(for: counterAccountId) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.caption2)
                        Circle()
                            .fill(account.color)
                            .frame(width: 8, height: 8)
                        Text(account.name)
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 2) {
                    Image(systemName: row.amountSign.icon)
                        .font(.caption2)
                        .foregroundStyle(row.amountSign.color)
                    Text(row.amount.currencyFormatted)
                        .fontWeight(.medium)
                }

                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            }

            // 解除ボタン
            Button {
                state.revertTransferConfirmation(rowId: row.id)
            } label: {
                Image(systemName: "xmark.circle")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Description Group Row (Phase 3-3 Enhanced with Rule Save)

struct DescriptionGroupRow: View {
    let group: DescriptionGroup
    let onSelectCategory: (UUID, Bool, String) -> Void  // categoryId, saveAsRule, keyword
    @EnvironmentObject var dataStore: DataStore

    @State private var selectedCategoryId: UUID?
    @State private var saveAsRule: Bool = true  // デフォルトON
    @State private var ruleKeyword: String = ""
    @State private var isExpanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // ヘッダー
            Button {
                withAnimation {
                    isExpanded.toggle()
                    if isExpanded && ruleKeyword.isEmpty {
                        ruleKeyword = group.suggestedKeyword
                    }
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(group.displayDescription)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.primary)
                            .lineLimit(2)

                        HStack(spacing: 8) {
                            Label("\(group.count)件", systemImage: "doc.text")
                            Label(group.totalAmount.currencyFormatted, systemImage: "yensign.circle")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            // カテゴリ選択（展開時）
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Text("カテゴリを選択")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HierarchicalCategoryPicker(
                        type: group.type,
                        selectedCategoryId: $selectedCategoryId
                    )

                    // ルール保存オプション（Phase 3-3）
                    Toggle("今後も同じカテゴリにする", isOn: $saveAsRule)
                        .font(.caption)

                    if saveAsRule {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("キーワード:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField("キーワード", text: $ruleKeyword)
                                .textFieldStyle(.roundedBorder)
                                .font(.caption)
                        }
                    }

                    // 適用ボタン
                    Button {
                        if let catId = selectedCategoryId {
                            onSelectCategory(catId, saveAsRule, ruleKeyword)
                        }
                    } label: {
                        HStack {
                            Image(systemName: "checkmark")
                            Text("\(group.count)件に適用")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .foregroundStyle(.white)
                        .background(selectedCategoryId != nil ? Color.themeBlue : Color.gray)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .disabled(selectedCategoryId == nil)
                }
                .padding(.top, 8)
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Step 3: Summary View (Phase 3-3 Enhanced)

struct ImportWizardStep3View: View {
    @ObservedObject var state: ImportWizardState
    let onDismiss: () -> Void
    @EnvironmentObject var dataStore: DataStore

    @State private var showUndoConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            if let result = state.commitResult {
                // 完了画面
                completedView(result: result)
            } else {
                // 確認画面
                confirmationView
            }
        }
    }

    private var confirmationView: some View {
        VStack(spacing: 0) {
            List {
                // サマリー
                Section {
                    SummaryRow(label: "合計行数", value: "\(state.draftRows.count)件")
                    SummaryRow(label: "通常取引追加", value: "\(state.resolvedCount)件", color: .green)
                    SummaryRow(label: "振替追加", value: "\(state.transferConfirmedCount)件", color: .blue)
                    SummaryRow(label: "重複スキップ", value: "\(state.duplicateCount)件", color: .gray)
                    SummaryRow(label: "無効行", value: "\(state.invalidCount)件", color: .red)

                    if state.unresolvedCount > 0 {
                        SummaryRow(label: "未分類", value: "\(state.unresolvedCount)件", color: .orange)
                    }
                    if state.transferCandidateCount > 0 {
                        SummaryRow(label: "振替未確定", value: "\(state.transferCandidateCount)件", color: .orange)
                    }
                } header: {
                    Text("インポート内容")
                }

                // 設定確認
                Section {
                    HStack {
                        Text("形式")
                        Spacer()
                        Text(state.selectedFormat.displayName)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("ファイル")
                        Spacer()
                        Text(state.fileName)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    if let accountId = state.selectedAccountId,
                       let account = AccountStore.shared.account(for: accountId) {
                        HStack {
                            Text("主体口座")
                            Spacer()
                            HStack {
                                Circle()
                                    .fill(account.color)
                                    .frame(width: 10, height: 10)
                                Text(account.name)
                            }
                            .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("設定")
                }

                // 保存不可の理由（Phase 3-3）
                if let reason = state.commitBlockReason {
                    Section {
                        Label(reason, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    } header: {
                        Text("保存できない理由")
                    }
                }
            }

            Divider()

            // ナビゲーションボタン
            HStack(spacing: 16) {
                Button {
                    withAnimation {
                        state.currentStep = .resolve
                    }
                } label: {
                    HStack {
                        Image(systemName: "chevron.left")
                        Text("戻る")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.secondaryBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                Button {
                    commitImport()
                } label: {
                    HStack {
                        Image(systemName: "square.and.arrow.down")
                        Text("保存")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundStyle(.white)
                    .background(state.canProceedToCommit ? Color.themeBlue : Color.gray)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .disabled(!state.canProceedToCommit)
            }
            .padding()
        }
    }

    private func completedView(result: ImportCommitResult) -> some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.green)

            Text("インポート完了")
                .font(.title2)
                .fontWeight(.bold)

            VStack(spacing: 8) {
                Text("\(result.addedCount)件を追加しました")
                    .font(.headline)

                if result.transferPairCount > 0 {
                    Text("\(result.transferPairCount)件を振替ペアとして保存")
                        .font(.subheadline)
                        .foregroundStyle(.blue)
                }

                if result.duplicateCount > 0 {
                    Text("\(result.duplicateCount)件は重複のためスキップ")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // アクションボタン
            VStack(spacing: 12) {
                Button {
                    showUndoConfirmation = true
                } label: {
                    HStack {
                        Image(systemName: "arrow.uturn.backward")
                        Text("このインポートを取り消す")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundStyle(.red)
                    .background(Color.red.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                Button {
                    onDismiss()
                } label: {
                    Text("閉じる")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundStyle(.white)
                        .background(Color.themeBlue)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding()
        }
        .alert("インポートを取り消しますか？", isPresented: $showUndoConfirmation) {
            Button("取り消す", role: .destructive) {
                undoImport(result: result)
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("追加した\(result.addedCount)件の取引を削除します。")
        }
    }

    private func commitImport() {
        state.isProcessing = true

        // 確定保存（Phase 3-3: 振替対応）
        let result = dataStore.commitDraftRowsWithTransfer(
            state.draftRows,
            primaryAccountId: state.selectedAccountId,
            fileName: state.fileName,
            fileHash: state.fileHash,
            format: state.selectedFormat
        )

        state.commitResult = result
        state.isProcessing = false
    }

    private func undoImport(result: ImportCommitResult) {
        // インポート履歴を取得して削除
        let histories = dataStore.fetchImportHistory()
        if let history = histories.first(where: { $0.importId == result.importId }) {
            dataStore.deleteTransactionsByImportHistory(history)
        } else {
            // 履歴が見つからない場合はIDで直接削除
            dataStore.deleteTransactions(ids: result.addedTransactionIds)
        }

        onDismiss()
    }
}

// MARK: - Summary Row

struct SummaryRow: View {
    let label: String
    let value: String
    var color: Color = .primary

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .foregroundStyle(color)
        }
    }
}

// MARK: - CSV Mapping Sheet (Phase R1-3)

struct CSVMappingSheet: View {
    @ObservedObject var state: ImportWizardState
    @Environment(\.dismiss) private var dismiss

    @State private var headers: [String] = []
    @State private var sampleRow: [String] = []
    @State private var mapping: CSVManualMapping = CSVManualMapping()

    var body: some View {
        NavigationStack {
            Form {
                if headers.isEmpty {
                    Text("CSVデータの読み込みに失敗しました。")
                } else {
                    Section("ヘッダー情報") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(Array(headers.enumerated()), id: \.offset) { index, header in
                                    VStack {
                                        Text("\(index)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text(header)
                                            .font(.caption)
                                            .padding(4)
                                            .background(Color.secondaryBackground)
                                            .cornerRadius(4)
                                    }
                                }
                            }
                        }
                    }

                    Section("必須項目") {
                        Picker("日付列", selection: Binding(get: { mapping.dateIndex ?? -1 }, set: { mapping.dateIndex = $0 == -1 ? nil : $0 })) {
                            Text("未選択").tag(-1)
                            ForEach(Array(headers.enumerated()), id: \.offset) { i, h in
                                Text("\(i): \(h)").tag(i)
                            }
                        }
                        
                        Picker("金額列", selection: Binding(get: { mapping.amountIndex ?? -1 }, set: { mapping.amountIndex = $0 == -1 ? nil : $0 })) {
                            Text("未選択").tag(-1)
                            ForEach(Array(headers.enumerated()), id: \.offset) { i, h in
                                Text("\(i): \(h)").tag(i)
                            }
                        }
                    }
                    
                    Section("入出金（必要な場合のみ）") {
                        Picker("入金列", selection: Binding(get: { mapping.creditIndex ?? -1 }, set: { mapping.creditIndex = $0 == -1 ? nil : $0 })) {
                            Text("未選択").tag(-1)
                            ForEach(Array(headers.enumerated()), id: \.offset) { i, h in
                                Text("\(i): \(h)").tag(i)
                            }
                        }
                        Picker("出金列", selection: Binding(get: { mapping.debitIndex ?? -1 }, set: { mapping.debitIndex = $0 == -1 ? nil : $0 })) {
                            Text("未選択").tag(-1)
                            ForEach(Array(headers.enumerated()), id: \.offset) { i, h in
                                Text("\(i): \(h)").tag(i)
                            }
                        }
                    }
                    
                    Section("その他") {
                        Picker("メモ/摘要", selection: Binding(get: { mapping.memoIndex ?? -1 }, set: { mapping.memoIndex = $0 == -1 ? nil : $0 })) {
                            Text("未選択").tag(-1)
                            ForEach(Array(headers.enumerated()), id: \.offset) { i, h in
                                Text("\(i): \(h)").tag(i)
                            }
                        }
                        Picker("カテゴリ", selection: Binding(get: { mapping.categoryIndex ?? -1 }, set: { mapping.categoryIndex = $0 == -1 ? nil : $0 })) {
                            Text("未選択").tag(-1)
                            ForEach(Array(headers.enumerated()), id: \.offset) { i, h in
                                Text("\(i): \(h)").tag(i)
                            }
                        }
                    }
                }
            }
            .navigationTitle("列マッピング設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("適用") {
                        state.manualMapping = mapping
                        dismiss()
                    }
                }
            }
            .onAppear {
                loadHeaders()
            }
        }
    }

    private func loadHeaders() {
        let rows = CSVParser.parse(state.csvText)
        if let first = rows.first {
            headers = first
            // 既存のマッピングがあれば読み込む、なければテンプレート
            if let existing = state.manualMapping {
                mapping = existing
            } else {
                mapping = CSVManualMapping.template(for: state.selectedFormat)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    CSVImportWizardView()
        .environmentObject(DataStore.shared)
}
