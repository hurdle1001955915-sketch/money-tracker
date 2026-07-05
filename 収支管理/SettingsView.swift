import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var dataStore: DataStore
    @EnvironmentObject var settings: AppSettings
    @StateObject private var syncManager = CloudKitSyncManager.shared

    @State private var showResetAlert = false
    @State private var showCSVExport = false

    @State private var showCSVImportWizard = false
    @State private var showImportHistoryManagement = false
    @State private var showAdvancedSettings = false

    @State private var showBackupSuccessAlert = false
    @State private var showBackupErrorAlert = false
    @State private var showRestoreAlert = false
    @State private var showRestoreSuccessAlert = false
    @State private var showRestoreErrorAlert = false

    @State private var showSyncErrorAlert = false
    @State private var showSyncSuccessAlert = false
    @State private var isSyncing = false

    // ZIPバックアップ用
    @State private var showZipExporter = false
    @State private var zipDocument: ZIPBackupDocument?
    @State private var showZipImporter = false
    @State private var showZipExportSuccessAlert = false
    @State private var showZipExportErrorAlert = false
    @State private var showZipImportConfirmAlert = false
    @State private var showZipImportSuccessAlert = false
    @State private var showZipImportErrorAlert = false
    @State private var zipImportData: Data?
    @State private var zipErrorMessage: String = ""

    var body: some View {
        NavigationStack {
            List {
                // 基本設定（よく使う）
                accountSection
                categorySection
                budgetSection

                // 表示・通知
                displaySection
                notificationSection

                // データ管理
                dataManagementSection
                zipBackupSection
                if AppFeatureFlags.cloudSyncEnabled {
                    iCloudSyncSection
                }

                // 詳細・セキュリティ
                advancedSection
                securitySection
                aiSection
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .modifier(SettingsAlertsWrapper(
                showResetAlert: $showResetAlert,
                showBackupSuccessAlert: $showBackupSuccessAlert,
                showBackupErrorAlert: $showBackupErrorAlert,
                showRestoreAlert: $showRestoreAlert,
                showRestoreSuccessAlert: $showRestoreSuccessAlert,
                showRestoreErrorAlert: $showRestoreErrorAlert,
                dataStore: dataStore
            ))
            .sheet(isPresented: $showCSVExport) {
                CSVExportView().environmentObject(dataStore)
            }
            .fullScreenCover(isPresented: $showCSVImportWizard) {
                CSVImportWizardView().environmentObject(dataStore)
            }
            .sheet(isPresented: $showImportHistoryManagement) {
                ImportHistoryManagementView().environmentObject(dataStore)
            }
            .fileExporter(
                isPresented: $showZipExporter,
                document: zipDocument,
                contentType: .zip,
                defaultFilename: zipBackupFileName()
            ) { result in
                handleZipExportResult(result)
            }
            .fileImporter(
                isPresented: $showZipImporter,
                allowedContentTypes: [.zip],
                allowsMultipleSelection: false
            ) { result in
                handleZipImportResult(result)
            }
            .syncAlerts(
                showSyncSuccessAlert: $showSyncSuccessAlert,
                showSyncErrorAlert: $showSyncErrorAlert,
                syncManager: syncManager
            )
            .zipBackupAlerts(
                showZipExportSuccessAlert: $showZipExportSuccessAlert,
                showZipExportErrorAlert: $showZipExportErrorAlert,
                showZipImportConfirmAlert: $showZipImportConfirmAlert,
                showZipImportSuccessAlert: $showZipImportSuccessAlert,
                showZipImportErrorAlert: $showZipImportErrorAlert,
                zipErrorMessage: zipErrorMessage,
                performZipRestore: performZipRestore
            )
        }
    }

    private func handleZipExportResult(_ result: Result<URL, Error>) {
        switch result {
        case .success:
            showZipExportSuccessAlert = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .failure(let error):
            zipErrorMessage = error.localizedDescription
            showZipExportErrorAlert = true
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }
    
    // MARK: - Sections
    
    private var accountSection: some View {
        Section("口座・振替") {
            NavigationLink {
                AccountsListView()
            } label: {
                SettingRow(title: "口座管理")
            }
        }
    }

    private var iCloudSyncSection: some View {
        Section {
            Toggle("iCloud同期", isOn: $syncManager.syncEnabled)
                .frame(minHeight: 44)
                .disabled(!syncManager.iCloudAvailable)

            if syncManager.iCloudAvailable {
                // 同期ステータス
                HStack {
                    Text("同期状態")
                    Spacer()
                    if isSyncing || syncManager.isSyncing {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("同期中...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if let lastSync = syncManager.lastSyncDate {
                        Text(lastSyncText(lastSync))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("未同期")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(minHeight: 44)

                // 手動同期ボタン
                Button {
                    performManualSync()
                } label: {
                    HStack {
                        Text("今すぐ同期")
                            .foregroundStyle(syncManager.syncEnabled ? .primary : .secondary)
                        Spacer()
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .foregroundStyle(syncManager.syncEnabled ? Color.themeBlue : .secondary)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .disabled(!syncManager.syncEnabled || isSyncing)
            } else {
                // iCloud利用不可の警告
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(syncManager.syncError ?? "iCloudが利用できません")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(minHeight: 44)
            }
        } header: {
            Text("iCloud同期")
        } footer: {
            Text("取引データを複数のデバイス間で自動的に同期します。")
        }
    }

    private func lastSyncText(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func performManualSync() {
        isSyncing = true
        Task {
            do {
                try await dataStore.performiCloudSync()
                showSyncSuccessAlert = true
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch {
                showSyncErrorAlert = true
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
            isSyncing = false
        }
    }
    
    private var securitySection: some View {
        Section("セキュリティ") {
            NavigationLink {
                AppLockSettingView()
            } label: {
                SettingRow(
                    title: "アプリロック",
                    value: settings.appLockEnabled ? "オン" : "オフ"
                )
            }
        }
    }

    private var aiSection: some View {
        Section {
            NavigationLink {
                OpenAIAPIKeySettingView()
            } label: {
                SettingRow(
                    title: "OpenAI APIキー",
                    value: KeychainStore.hasOpenAIAPIKey ? "設定済み" : "未設定"
                )
            }
        } header: {
            Text("AI機能")
        } footer: {
            Text("CSVインポート時の未分類取引をAIで自動分類します。")
        }
    }

    private var displaySection: some View {
        Section("表示設定") {
            NavigationLink {
                WeekStartDaySettingView()
            } label: {
                SettingRow(title: "週の開始日", value: WeekDays.names[settings.weekStartDay - 1] + "曜日")
            }
            Toggle("前月の繰越金を表示", isOn: $settings.showPreviousBalance)
                .frame(minHeight: 44)
        }
    }
    
    private var unprocessedFixedCostCount: Int {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        let currentMonth = formatter.string(from: Date())
        return dataStore.fixedCostTemplates
            .filter { $0.isEnabled && $0.lastProcessedMonth != currentMonth }
            .count
    }

    private var categorySection: some View {
        Section("カテゴリーと固定費") {
            NavigationLink {
                CategoryEditView(type: .expense)
            } label: {
                SettingRow(title: "支出カテゴリー")
            }
            NavigationLink {
                CategoryEditView(type: .income)
            } label: {
                SettingRow(title: "収入カテゴリー")
            }
            NavigationLink {
                FixedCostSettingView()
            } label: {
                HStack {
                    Text("固定費・定期収入")
                    Spacer()
                    if unprocessedFixedCostCount > 0 {
                        ZStack {
                            Circle()
                                .fill(.red)
                                .frame(width: 20, height: 20)
                            Text("\(unprocessedFixedCostCount)")
                                .font(.caption2)
                                .foregroundColor(.white)
                        }
                    }
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            NavigationLink {
                ClassificationRulesView()
            } label: {
                SettingRow(title: "自動分類ルール")
            }
        }
    }
    
    private var budgetSection: some View {
        Section("予算") {
            NavigationLink {
                BudgetSettingView()
            } label: {
                SettingRow(title: "予算設定")
            }
        }
    }
    
    private var notificationSection: some View {
        Section("通知") {
            NavigationLink {
                ReminderSettingView()
            } label: {
                SettingRow(title: "入れ忘れ防止通知", value: settings.reminderEnabled ? "ON" : "OFF")
            }
        }
    }
    
    private var dataManagementSection: some View {
        Section("データ管理") {
            exportButton
            importButton
            importHistoryButton
        }
    }
    
    private var advancedSection: some View {
        Section("詳細設定") {
            NavigationLink {
                MonthStartDayPickerView()
            } label: {
                SettingRow(title: "月の開始日", value: "\(settings.monthStartDay)日")
            }
            NavigationLink {
                SameDaySortSettingView()
            } label: {
                SettingRow(title: "同日の並び順", value: settings.sameDaySortOrder.shortDisplayName)
            }
            NavigationLink {
                GraphTypeSettingView()
            } label: {
                SettingRow(title: "グラフの表示設定")
            }
        }
    }

    // MARK: - ZIP Backup Section
    private var zipBackupSection: some View {
        Section {
            Button {
                createZipBackup()
            } label: {
                HStack {
                    Text("バックアップをFilesに保存")
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "square.and.arrow.up")
                        .foregroundStyle(Color.themeBlue)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }

            Button {
                showZipImporter = true
            } label: {
                HStack {
                    Text("Filesからバックアップを復元")
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "square.and.arrow.down")
                        .foregroundStyle(Color.orange)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
        } header: {
            Text("バックアップ")
        } footer: {
            Text("全データをZIPファイルとしてFilesアプリに保存・復元します。機種変更時のデータ移行や、万が一のデータ消失に備えて定期的にバックアップしてください。")
        }
    }

    // MARK: - ZIP Backup Methods
    private func zipBackupFileName() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let dateString = dateFormatter.string(from: Date())
        return "kakeibo_backup_\(dateString).zip"
    }

    private func createZipBackup() {
        do {
            let backupData = try dataStore.createZipBackupData()
            zipDocument = ZIPBackupDocument(zipData: backupData)
            showZipExporter = true
        } catch {
            zipErrorMessage = error.localizedDescription
            showZipExportErrorAlert = true
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    private func handleZipImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else {
                zipErrorMessage = "ファイルが選択されていません"
                showZipImportErrorAlert = true
                return
            }
            // セキュリティスコープのアクセス
            guard url.startAccessingSecurityScopedResource() else {
                zipErrorMessage = "ファイルへのアクセス権限がありません"
                showZipImportErrorAlert = true
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }

            do {
                zipImportData = try Data(contentsOf: url)
                showZipImportConfirmAlert = true
            } catch {
                zipErrorMessage = error.localizedDescription
                showZipImportErrorAlert = true
            }
        case .failure(let error):
            zipErrorMessage = error.localizedDescription
            showZipImportErrorAlert = true
        }
    }

    private func performZipRestore() {
        guard let data = zipImportData else {
            zipErrorMessage = "バックアップデータがありません"
            showZipImportErrorAlert = true
            return
        }

        do {
            try dataStore.restoreFromZipBackupData(data)
            showZipImportSuccessAlert = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            zipErrorMessage = error.localizedDescription
            showZipImportErrorAlert = true
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
        zipImportData = nil
    }
    
    // MARK: - Buttons
    
    private var backupButton: some View {
        Button {
            if dataStore.createBackup() {
                showBackupSuccessAlert = true
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } else {
                showBackupErrorAlert = true
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        } label: {
            HStack {
                Text("バックアップ作成")
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "externaldrive.badge.plus")
                    .foregroundStyle(Color.green)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
    }
    
    private var restoreButton: some View {
        Button {
            showRestoreAlert = true
        } label: {
            HStack {
                Text("バックアップから復元")
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "arrow.clockwise")
                    .foregroundStyle(Color.orange)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
    }
    
    private var exportButton: some View {
        Button {
            showCSVExport = true
        } label: {
            HStack {
                Text("データをエクスポート")
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "square.and.arrow.up")
                    .foregroundStyle(Color.themeBlue)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
    }
    
    private var importButton: some View {
        Button {
            showCSVImportWizard = true
        } label: {
            HStack {
                Text("データをインポート")
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "square.and.arrow.down")
                    .foregroundStyle(Color.themeBlue)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
    }
    
    private var importHistoryButton: some View {
        Button {
            showImportHistoryManagement = true
        } label: {
            HStack {
                Text("インポート履歴を管理")
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundStyle(Color.themeBlue)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
    }
}

// MARK: - Settings Alerts ViewModifier

// MARK: - Refactored Alert Modifiers

struct SettingsAlertsWrapper: ViewModifier {
    @Binding var showResetAlert: Bool
    @Binding var showBackupSuccessAlert: Bool
    @Binding var showBackupErrorAlert: Bool
    @Binding var showRestoreAlert: Bool
    @Binding var showRestoreSuccessAlert: Bool
    @Binding var showRestoreErrorAlert: Bool
    var dataStore: DataStore
    
    func body(content: Content) -> some View {
        content
            .alert("すべてのデータを削除", isPresented: $showResetAlert) {
                Button("キャンセル", role: .cancel) {}
                Button("削除", role: .destructive) {
                    dataStore.resetAllData()
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            } message: {
                Text("すべての取引、カテゴリー、固定費、予算が削除されます。\nこの操作は取り消せません。")
            }
            .alert("バックアップ完了", isPresented: $showBackupSuccessAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("データのバックアップを作成しました。\n「バックアップから復元」で元に戻せます。")
            }
            .alert("バックアップ失敗", isPresented: $showBackupErrorAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("バックアップの作成に失敗しました。")
            }
            .alert("バックアップから復元", isPresented: $showRestoreAlert) {
                Button("キャンセル", role: .cancel) {}
                Button("復元", role: .destructive) {
                    if dataStore.restoreFromBackup() {
                        showRestoreSuccessAlert = true
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    } else {
                        showRestoreErrorAlert = true
                        UINotificationFeedbackGenerator().notificationOccurred(.error)
                    }
                }
            } message: {
                Text("現在のデータを最新のバックアップで上書きします。\nこの操作は取り消せません。")
            }
            .alert("復元完了", isPresented: $showRestoreSuccessAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("バックアップからデータを復元しました。")
            }
            .alert("復元失敗", isPresented: $showRestoreErrorAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("バックアップが見つかりませんでした。\n先に「バックアップ作成」を実行してください。")
            }
    }
}

extension View {
    func syncAlerts(showSyncSuccessAlert: Binding<Bool>, showSyncErrorAlert: Binding<Bool>, syncManager: CloudKitSyncManager) -> some View {
        self.alert("同期完了", isPresented: showSyncSuccessAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("iCloudとの同期が完了しました。")
        }
        .alert("同期エラー", isPresented: showSyncErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(syncManager.syncError ?? "同期中にエラーが発生しました。")
        }
    }
    
    func zipBackupAlerts(
        showZipExportSuccessAlert: Binding<Bool>,
        showZipExportErrorAlert: Binding<Bool>,
        showZipImportConfirmAlert: Binding<Bool>,
        showZipImportSuccessAlert: Binding<Bool>,
        showZipImportErrorAlert: Binding<Bool>,
        zipErrorMessage: String,
        performZipRestore: @escaping () -> Void
    ) -> some View {
        self.alert("バックアップ保存完了", isPresented: showZipExportSuccessAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("ZIPバックアップをFilesに保存しました。")
        }
        .alert("バックアップ保存失敗", isPresented: showZipExportErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("保存に失敗しました: \(zipErrorMessage)")
        }
        .alert("バックアップから復元", isPresented: showZipImportConfirmAlert) {
            Button("キャンセル", role: .cancel) { }
            Button("復元", role: .destructive) {
                performZipRestore()
            }
        } message: {
            Text("現在のデータをバックアップファイルで上書きします。\nこの操作は取り消せません。")
        }
        .alert("復元完了", isPresented: showZipImportSuccessAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("バックアップからデータを復元しました。")
        }
        .alert("復元失敗", isPresented: showZipImportErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("復元に失敗しました: \(zipErrorMessage)")
        }
    }
}

// MARK: - Setting Row

struct SettingRow: View {
    let title: String
    var value: String? = nil

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            if let value = value {
                Text(value)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

// MARK: - CSV Export

struct CSVExportView: View {
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.dismiss) private var dismiss

    @State private var showExporter = false
    @State private var csvDocument: CSVDocument?
    @State private var exportError: String?
    @State private var showSuccessAlert = false
    @State private var exportOptions = CSVExportOptions.load()

    private var transactionCount: Int {
        dataStore.transactions.filter { !$0.isDeleted }.count
    }

    var body: some View {
        NavigationStack {
            List {
                // 概要セクション
                Section {
                    HStack {
                        Image(systemName: "doc.text")
                            .font(.system(size: 40))
                            .foregroundStyle(Color.themeBlue)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("CSVエクスポート")
                                .font(.headline)
                            Text("取引データをCSV形式で出力")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 8)

                    HStack {
                        Text("データ件数")
                        Spacer()
                        Text("\(transactionCount)件")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("出力列数")
                        Spacer()
                        Text("\(exportOptions.orderedColumns.count)列")
                            .foregroundStyle(.secondary)
                    }
                }

                // 列選択セクション
                Section {
                    NavigationLink {
                        CSVColumnSelectionView(options: $exportOptions)
                    } label: {
                        HStack {
                            Text("出力列を選択")
                            Spacer()
                            Text("\(exportOptions.columns.count)/\(CSVExportColumn.allCases.count)")
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("出力設定")
                } footer: {
                    Text("先頭5列（日付、種類、金額、カテゴリ、メモ）は必須です")
                }

                // フォーマット設定セクション
                Section("フォーマット") {
                    Toggle("BOM付き（Excel互換）", isOn: $exportOptions.includeBOM)

                    Picker("改行コード", selection: $exportOptions.lineEnding) {
                        ForEach(CSVLineEnding.allCases, id: \.self) { ending in
                            Text(ending.displayName).tag(ending)
                        }
                    }
                }

                // エラー表示
                if let error = exportError {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }

                // エクスポートボタン
                Section {
                    Button {
                        exportCSV()
                    } label: {
                        HStack {
                            Spacer()
                            Text("エクスポート")
                                .font(.headline)
                            Spacer()
                        }
                    }
                    .listRowBackground(Color.themeBlue)
                    .foregroundStyle(.white)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
            .fileExporter(
                isPresented: $showExporter,
                document: csvDocument,
                contentType: .commaSeparatedText,
                defaultFilename: defaultFileName()
            ) { result in
                switch result {
                case .success(let url):
                    print("✅ CSV exported to: \(url.path)")
                    showSuccessAlert = true
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                case .failure(let error):
                    exportError = error.localizedDescription
                    print("❌ Failed to export CSV: \(error)")
                }
            }
            .alert("エクスポート完了", isPresented: $showSuccessAlert) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text("CSVファイルを保存しました")
            }
        }
    }

    private func exportCSV() {
        exportError = nil
        // オプションを保存
        exportOptions.save()
        // オプション付きでCSV生成
        csvDocument = CSVDocument(csvText: dataStore.generateCSV(options: exportOptions))
        showExporter = true
        print("📊 Exporting \(transactionCount) transactions with \(exportOptions.orderedColumns.count) columns")
    }

    private func defaultFileName() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd-HHmmss"
        let dateString = dateFormatter.string(from: Date())
        return "kakeibo_export_\(dateString).csv"
    }
}

// MARK: - CSV Column Selection View

struct CSVColumnSelectionView: View {
    @Binding var options: CSVExportOptions
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            // 基本列（必須）
            Section {
                ForEach(CSVExportColumn.basicColumns, id: \.self) { column in
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text(column.rawValue)
                        Spacer()
                        Text("必須")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("基本列（必須）")
            } footer: {
                Text("これらの列は常に出力され、順序も固定です")
            }

            // 拡張列（選択可能）
            Section {
                ForEach(CSVExportColumn.extendedColumns, id: \.self) { column in
                    Toggle(column.rawValue, isOn: Binding(
                        get: { options.columns.contains(column) },
                        set: { isOn in
                            if isOn {
                                options.columns.insert(column)
                            } else {
                                options.columns.remove(column)
                            }
                        }
                    ))
                }
            } header: {
                Text("拡張列（選択可能）")
            }

            // 一括操作
            Section {
                Button("すべて選択") {
                    options.columns = CSVExportColumn.defaultSet
                }

                Button("基本列のみ") {
                    options.columns = CSVExportColumn.minimalSet
                }
            }
        }
        .navigationTitle("出力列の選択")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - CSV Document

struct CSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    
    var csvText: String
    
    init(csvText: String = "") {
        self.csvText = csvText
    }
    
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let string = String(data: data, encoding: .utf8)
        else {
            throw CocoaError(.fileReadCorruptFile)
        }
        csvText = string
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        guard let data = csvText.data(using: .utf8) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - ZIP Backup Document

struct ZIPBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.zip] }

    var zipData: Data

    init(zipData: Data = Data()) {
        self.zipData = zipData
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        zipData = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        return FileWrapper(regularFileWithContents: zipData)
    }
}

// MARK: - OpenAI API Key Setting View

struct OpenAIAPIKeySettingView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var apiKey: String = ""
    @State private var isKeySet: Bool = false
    @State private var showDeleteConfirmation = false
    @State private var showSaveSuccessAlert = false
    @State private var showSaveErrorAlert = false

    var body: some View {
        List {
            Section {
                if isKeySet {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("APIキーは設定済みです")
                            .foregroundStyle(.secondary)
                    }
                    .frame(minHeight: 44)

                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                            Text("APIキーを削除")
                        }
                        .frame(minHeight: 44)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("OpenAI APIキー")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        SecureField("sk-...", text: $apiKey)
                            .textContentType(.password)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                    .frame(minHeight: 60)

                    Button {
                        saveAPIKey()
                    } label: {
                        HStack {
                            Image(systemName: "key.fill")
                            Text("保存")
                        }
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                    }
                    .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } header: {
                Text("APIキー設定")
            } footer: {
                Text("OpenAIのAPIキーはKeychainに安全に保存されます。キーはOpenAI公式サイト(platform.openai.com)で取得できます。")
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("AI分類について", systemImage: "sparkles")
                        .font(.headline)

                    Text("CSVインポート時に未分類の取引をAIが自動的にカテゴリ分類します。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Divider()

                    VStack(alignment: .leading, spacing: 4) {
                        Text("・確信度80%以上の場合のみ自動適用")
                        Text("・1回最大25件ずつ処理")
                        Text("・振替取引は対象外")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            } header: {
                Text("機能説明")
            }
        }
        .navigationTitle("OpenAI API設定")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            isKeySet = KeychainStore.hasOpenAIAPIKey
        }
        .alert("APIキーを削除", isPresented: $showDeleteConfirmation) {
            Button("キャンセル", role: .cancel) {}
            Button("削除", role: .destructive) {
                deleteAPIKey()
            }
        } message: {
            Text("保存されているAPIキーを削除しますか？")
        }
        .alert("保存完了", isPresented: $showSaveSuccessAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("APIキーを保存しました。")
        }
        .alert("保存失敗", isPresented: $showSaveErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("APIキーの保存に失敗しました。")
        }
    }

    private func saveAPIKey() {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { return }

        if KeychainStore.saveOpenAIAPIKey(trimmedKey) {
            isKeySet = true
            apiKey = ""
            showSaveSuccessAlert = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } else {
            showSaveErrorAlert = true
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    private func deleteAPIKey() {
        KeychainStore.deleteOpenAIAPIKey()
        isKeySet = false
        apiKey = ""
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
        .environmentObject(DataStore.shared)
        .environmentObject(AppSettings.shared)
}
