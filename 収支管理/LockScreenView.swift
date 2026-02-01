import SwiftUI

// MARK: - Lock Screen View

struct LockScreenView: View {
    @ObservedObject var lockManager = AppLockManager.shared
    @ObservedObject var settings = AppSettings.shared
    
    var body: some View {
        ZStack {
            // 背景
            Color(.systemBackground)
                .ignoresSafeArea()
            
            VStack(spacing: 32) {
                Spacer()
                
                // アプリアイコン
                Image(systemName: "yensign.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(Color.themeBlue)
                
                Text("家計簿")
                    .font(.title)
                    .fontWeight(.bold)
                
                Spacer()
                
                // 認証ボタン
                VStack(spacing: 16) {
                    Button {
                        Task {
                            await lockManager.authenticate()
                        }
                    } label: {
                        HStack(spacing: 12) {
                            // プロパティアクセスを分離して型推論を助ける
                            let iconName = lockManager.biometricType.iconName
                            let bioName = lockManager.biometricName
                            
                            Image(systemName: iconName)
                                .font(.title2)
                            Text("\(bioName)でロック解除")
                                .fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.themeBlue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(lockManager.isAuthenticating)
                    .padding(.horizontal, 40)
                    
                    if lockManager.isAuthenticating {
                        ProgressView()
                            .progressViewStyle(.circular)
                    }
                    
                    if let error = lockManager.authError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }
                }
                
                Spacer()
                    .frame(height: 60)
            }
        }
        .onAppear {
            // 画面表示時に自動認証
            Task {
                try? await Task.sleep(nanoseconds: 300_000_000) // 0.3秒待機
                await lockManager.authenticate()
            }
        }
    }
}

// MARK: - Lock Screen Modifier

struct LockScreenModifier: ViewModifier {
    @ObservedObject var lockManager = AppLockManager.shared
    @ObservedObject var settings = AppSettings.shared
    @Environment(\.scenePhase) var scenePhase
    
    func body(content: Content) -> some View {
        ZStack {
            content
            
            if settings.appLockEnabled && lockManager.isLocked {
                LockScreenView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: lockManager.isLocked)
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background:
                lockManager.handleBackground()
            case .active:
                if lockManager.isLocked {
                    Task {
                        await lockManager.authenticate()
                    }
                }
            default:
                break
            }
        }
    }
}

extension View {
    func withLockScreen() -> some View {
        modifier(LockScreenModifier())
    }
}

#Preview {
    LockScreenView()
}
