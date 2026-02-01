import SwiftUI

struct WeekStartDaySettingView: View {
    @EnvironmentObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        List {
            ForEach(1...7, id: \.self) { day in
                Button {
                    settings.weekStartDay = day
                    dismiss()
                } label: {
                    HStack {
                        Text(WeekDays.names[day - 1] + "曜日")
                            .foregroundStyle(.primary)
                        Spacer()
                        if settings.weekStartDay == day {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color(UIColor.systemBlue))
                        }
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
            }
        }
        .navigationTitle("週の開始日")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct SameDaySortSettingView: View {
    @EnvironmentObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        List {
            ForEach(SameDaySortOrder.allCases, id: \.self) { order in
                Button {
                    settings.sameDaySortOrder = order
                    dismiss()
                } label: {
                    HStack {
                        Text(order.displayName)
                            .foregroundStyle(.primary)
                        Spacer()
                        if settings.sameDaySortOrder == order {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color(UIColor.systemBlue))
                        }
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
            }
        }
        .navigationTitle("同日の収支の並び順")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct GraphTypeSettingView: View {
    @EnvironmentObject var settings: AppSettings
    
    var body: some View {
        List {
            Section {
                ForEach(settings.graphTypeOrder, id: \.self) { type in
                    HStack {
                        Image(systemName: "line.3.horizontal")
                            .foregroundStyle(.secondary)
                        
                        Text(type.displayName)
                        
                        Spacer()
                        
                        Toggle("", isOn: Binding(
                            get: { settings.enabledGraphTypes.contains(type) },
                            set: { isEnabled in
                                if isEnabled {
                                    settings.enabledGraphTypes.insert(type)
                                } else if settings.enabledGraphTypes.count > 1 {
                                    settings.enabledGraphTypes.remove(type)
                                }
                            }
                        ))
                        .labelsHidden()
                    }
                    .frame(minHeight: 44)
                }
                .onMove { from, to in
                    settings.graphTypeOrder.move(fromOffsets: from, toOffset: to)
                }
            } header: {
                Text("表示するグラフを選択し、ドラッグで並び替えができます")
            }
        }
        .navigationTitle("グラフの表示設定")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
        }
    }
}

struct CategoryEditView: View {
    @EnvironmentObject var dataStore: DataStore
    
    let type: TransactionType
    
    @State private var showAddSheet = false
    @State private var editingCategory: Category?
    
    private var categories: [Category] {
        dataStore.categories(for: type)
    }
    
    var body: some View {
        List {
            ForEach(categories) { category in
                Button {
                    editingCategory = category
                } label: {
                    HStack {
                        Circle()
                            .fill(category.color)
                            .frame(width: 24, height: 24)
                        
                        Text(category.name)
                            .foregroundStyle(.primary)
                        
                        Spacer()
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
            }
            .onMove { from, to in
                dataStore.reorderCategories(type: type, from: from, to: to)
            }
            .onDelete { indexSet in
                deleteCategories(at: indexSet)
            }
        }
        .navigationTitle(type == .expense ? "支出カテゴリー" : "収入カテゴリー")
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
            CategoryFormView(type: type, category: nil)
        }
        .sheet(item: $editingCategory) { category in
            CategoryFormView(type: type, category: category)
        }
    }
    
    private func deleteCategories(at indexSet: IndexSet) {
        for index in indexSet {
            let category = categories[index]
            withAnimation {
                dataStore.deleteCategory(category)
            }
        }
        // ハプティックフィードバック
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
}

struct CategoryFormView: View {
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.dismiss) private var dismiss
    
    let type: TransactionType
    let category: Category?
    
    @State private var name = ""
    @State private var selectedColor = "#607D8B"
    
    private var isValid: Bool {
        !name.isEmpty
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("カテゴリー名", text: $name)
                        .frame(minHeight: 44)
                }
                
                Section("カラー") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 16) {
                        ForEach(Color.categoryColors, id: \.self) { color in
                            Button {
                                selectedColor = color
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(Color(hex: color))
                                        .frame(width: 44, height: 44)
                                    
                                    if selectedColor == color {
                                        Circle()
                                            .stroke(Color.primary, lineWidth: 3)
                                            .frame(width: 52, height: 52)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle(category == nil ? "新規カテゴリー" : "カテゴリー編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        save()
                    }
                    .disabled(!isValid)
                }
            }
            .onAppear {
                if let c = category {
                    name = c.name
                    selectedColor = c.colorHex
                }
            }
        }
    }
    
    private func save() {
        if let existing = category {
            var updated = existing
            updated.name = name
            updated.colorHex = selectedColor
            dataStore.updateCategory(updated)
        } else {
            let categories = dataStore.categories(for: type)
            let newCategory = Category(
                name: name,
                colorHex: selectedColor,
                type: type,
                order: categories.count
            )
            dataStore.addCategory(newCategory)
        }
        
        dismiss()
    }
}

