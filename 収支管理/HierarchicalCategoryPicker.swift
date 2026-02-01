import SwiftUI

/// カテゴリ選択ビュー
/// 大分類（Group）を選んでから中分類（Item）を選ぶ2段階形式
struct HierarchicalCategoryPicker: View {
    let type: TransactionType
    @Binding var selectedCategoryId: UUID?
    
    @EnvironmentObject var dataStore: DataStore
    
    // 現在表示中のグループID（nilの場合はグループ一覧を表示）
    @State private var browsingGroupId: UUID? = nil
    @State private var hasUserInteracted = false
    
    private var groups: [CategoryGroup] {
        dataStore.groups(for: type)
    }
    
    private var itemsInBrowsingGroup: [CategoryItem] {
        guard let groupId = browsingGroupId else { return [] }
        return dataStore.items(for: groupId)
    }

    var body: some View {
        VStack(spacing: 8) {
            if let groupId = browsingGroupId {
                // 中分類一覧を表示
                headerView(title: dataStore.categoryGroups.first(where: { $0.id == groupId })?.name ?? "")
                
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(itemsInBrowsingGroup) { item in
                        itemButton(item)
                    }
                }
            } else {
                // 大分類一覧を表示
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(groups) { group in
                        groupButton(group)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .onChange(of: type) { _, _ in
            // タイプが変わったら表示をグループ一覧に戻す
            browsingGroupId = nil
        }
    }
    
    private func headerView(title: String) -> some View {
        HStack {
            Button {
                withAnimation(.spring(response: 0.3)) {
                    browsingGroupId = nil
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("戻る")
                }
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(Color.themeBlue)
                .padding(.vertical, 8)
                .padding(.trailing, 16)
            }
            
            Spacer()
            
            Text(title)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundStyle(.secondary)
            
            Spacer()
            
            // バランスのためのダミー
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                Text("戻る")
            }
            .font(.subheadline)
            .opacity(0)
        }
        .padding(.bottom, 4)
    }

    private func groupButton(_ group: CategoryGroup) -> some View {
        Button {
            withAnimation(.spring(response: 0.3)) {
                browsingGroupId = group.id
            }
            hasUserInteracted = true
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            VStack(spacing: 4) {
                if let hex = group.colorHex {
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: 24, height: 24)
                } else {
                    Image(systemName: "folder")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                }

                Text(group.name)
                    .font(.caption2)
                    .lineLimit(1)
                    .foregroundStyle(Color.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke((hasUserInteracted && isAnyItemInGroupSelected(group)) ? Color.themeBlue : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func itemButton(_ item: CategoryItem) -> some View {
        Button {
            selectedCategoryId = item.id
            hasUserInteracted = true
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(item.color)
                    .frame(width: 12, height: 12)

                Text(item.name)
                    .font(.caption2)
                    .lineLimit(1)
                    .foregroundStyle(Color.primary)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(selectedCategoryId == item.id ? Color.themeBlue.opacity(0.1) : Color.secondaryBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(selectedCategoryId == item.id ? Color.themeBlue : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    private func isAnyItemInGroupSelected(_ group: CategoryGroup) -> Bool {
        guard let selectedId = selectedCategoryId else { return false }
        return dataStore.categoryItems.contains { $0.id == selectedId && $0.groupId == group.id }
    }
}
