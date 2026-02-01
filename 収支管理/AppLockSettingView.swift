import SwiftUI
import Foundation
import LocalAuthentication

// MARK: - App Lock Setting View

struct AppLockSettingView: View {
    @EnvironmentObject var settings: AppSettings

    // `shared` はViewが所有するインスタンスではないため `@StateObject` ではなく `@ObservedObject` を使用
    @ObservedObject private var lockManager = AppLockManager.shared

    @State private var showAuthError = false
    @State private var authErrorMessage = ""

    var body: some View {
        List {
            Section {
                Toggle(isOn: $settings.appLockEnabled) {
                    HStack {
                        Image(systemName: lockManager.biometricType.iconName)
                            .foregroundStyle(Color.themeBlue)
                            .frame(width: 24)
                        Text("\(lockManager.biometricName)でロック")
                    }
                }
                .onChange(of: settings.appLockEnabled) { _, newValue in
                    if newValue {
                        verifyBiometricAvailability()
                    }
                }
            } footer: {
                if lockManager.isBiometricAvailable {
                    Text("アプリを開く時に\(lockManager.biometricName)での認証が必要になります。")
                } else {
                    Text("生体認証が利用できません。デバイスの設定を確認してください。")
                        .foregroundStyle(.red)
                }
            }

            if settings.appLockEnabled {
                Section {
                    Toggle("バックグラウンド時にロック", isOn: $settings.lockOnBackground)
                } footer: {
                    Text("アプリがバックグラウンドに移行した時に自動でロックします。")
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                        Text("対応している認証方法")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        authMethodRow(icon: "faceid", name: "Face ID", available: lockManager.biometricType == .faceID)
                        authMethodRow(icon: "touchid", name: "Touch ID", available: lockManager.biometricType == .touchID)
                        authMethodRow(icon: "lock", name: "パスコード", available: true)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("アプリロック")
        .navigationBarTitleDisplayMode(.inline)
        .alert("認証エラー", isPresented: $showAuthError) {
            Button("OK", role: .cancel) {
                settings.appLockEnabled = false
            }
        } message: {
            Text(authErrorMessage)
        }
    }

    private func authMethodRow(icon: String, name: String, available: Bool) -> some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundStyle(available ? Color.themeBlue : .secondary)
            Text(name)
                .font(.caption)
            Spacer()
            if available {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Image(systemName: "xmark.circle")
                    .foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(available ? .primary : .secondary)
    }

    private func verifyBiometricAvailability() {
        let context = LAContext()
        var error: NSError?

        // まず生体認証が使えるか
        if !context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            // 生体認証が使えない場合、パスコード認証が使えるか
            if !context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
                authErrorMessage = "認証方法が設定されていません。デバイスの設定でパスコードを有効にしてください。"
                showAuthError = true
            }
        }
    }
}

#Preview {
    NavigationStack {
        AppLockSettingView()
            .environmentObject(AppSettings.shared)
    }
}
