import SwiftUI

struct ImportHistoryManagementView: View {
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.dismiss) private var dismiss
    
    @State private var histories: [ImportHistory] = []
    @State private var showingDeleteAllAlert = false
    @State private var historyToDelete: ImportHistory? = nil
    @State private var showingIndividualDeleteAlert = false
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button(role: .destructive) {
                        showingDeleteAllAlert = true
                    } label: {
                        HStack {
                            Image(systemName: "trash.fill")
                            Text("インポートした全データを削除")
                        }
                    }
                    .disabled(histories.isEmpty)
                } footer: {
                    Text("これまでにインポートした全ての取引データと履歴を削除します。手動で入力した取引は残ります。")
                }
                
                Section("インポート履歴") {
                    if histories.isEmpty {
                        Text("インポート履歴がありません")
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(histories) { history in
                            historyRow(history)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    historyToDelete = history
                                    showingIndividualDeleteAlert = true
                                } label: {
                                    Label("削除", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("インポート履歴管理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("閉じる") { dismiss() }
                }
            }
            .onAppear(perform: loadHistories)
            .alert("インポートデータを削除", isPresented: $showingDeleteAllAlert) {
                Button("キャンセル", role: .cancel) {}
                Button("削除する", role: .destructive) {
                    dataStore.deleteAllImportedTransactions()
                    loadHistories()
                }
            } message: {
                Text("これまでにインポートした全ての取引を削除しますか？\nこの操作は取り記せません。")
            }
            .alert("このインポートを削除", isPresented: $showingIndividualDeleteAlert) {
                Button("キャンセル", role: .cancel) {}
                Button("削除する", role: .destructive) {
                    if let history = historyToDelete {
                        dataStore.deleteTransactionsByImportHistory(history)
                        loadHistories()
                    }
                }
            } message: {
                if let history = historyToDelete {
                    Text("「\(history.filename)」で追加された取引を削除しますか？")
                }
            }
        }
    }
    
    private func loadHistories() {
        histories = dataStore.fetchImportHistory()
    }
    
    private func historyRow(_ history: ImportHistory) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(history.filename)
                .font(.subheadline)
                .fontWeight(.medium)
            
            HStack {
                Text(history.importDate.formatted(date: .abbreviated, time: .shortened))
                Spacer()
                Text("\(history.addedCount)件追加")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    ImportHistoryManagementView()
        .environmentObject(DataStore.shared)
}
