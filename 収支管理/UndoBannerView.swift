import SwiftUI

/// 削除Undo用のバナー表示
struct UndoBannerView: View {
    @ObservedObject var deletionManager: DeletionManager
    let onUndo: () -> Void
    
    var body: some View {
        if deletionManager.hasPendingDeletion {
            VStack {
                Spacer()
                
                HStack(spacing: 12) {
                    // アイコン
                    Image(systemName: "trash")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white)
                    
                    // メッセージ
                    VStack(alignment: .leading, spacing: 2) {
                        Text("削除しました")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.white)
                        
                        Text(deletionManager.deletedItemName)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.8))
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    // カウントダウン
                    Text("\(deletionManager.remainingSeconds)秒")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 36)
                    
                    // Undoボタン
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            onUndo()
                        }
                    } label: {
                        Text("元に戻す")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.25))
                            .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(red: 0.2, green: 0.2, blue: 0.2))
                        .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 100) // タブバーの上
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: deletionManager.hasPendingDeletion)
        }
    }
}

// MARK: - ViewModifier

struct UndoBannerModifier: ViewModifier {
    @ObservedObject var deletionManager: DeletionManager
    let onUndo: () -> Void
    
    func body(content: Content) -> some View {
        ZStack {
            content
            UndoBannerView(deletionManager: deletionManager, onUndo: onUndo)
        }
    }
}

extension View {
    func undoBanner(deletionManager: DeletionManager, onUndo: @escaping () -> Void) -> some View {
        modifier(UndoBannerModifier(deletionManager: deletionManager, onUndo: onUndo))
    }
}

#Preview {
    Text("Preview")
        .undoBanner(deletionManager: DeletionManager.shared, onUndo: {})
}
