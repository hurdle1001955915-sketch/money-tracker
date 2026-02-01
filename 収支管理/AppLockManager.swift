import Foundation
import LocalAuthentication
import Combine
import SwiftUI

// MARK: - App Lock Manager

@MainActor
final class AppLockManager: ObservableObject {
    static let shared = AppLockManager()

    @Published var isLocked: Bool = true
    @Published var isAuthenticating: Bool = false
    @Published var authError: String?

    private let context = LAContext()

    private init() {
        // 起動時にロック設定を確認
        if AppSettings.shared.appLockEnabled {
            isLocked = true
        } else {
            isLocked = false
        }
    }

    private func hasUsageDescription(_ key: String) -> Bool {
        Bundle.main.object(forInfoDictionaryKey: key) != nil
    }

    // MARK: - Biometric Info (for Settings UI)

    /// 生体認証が利用可能か（Touch ID / Face ID / Optic ID）
    var isBiometricAvailable: Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    /// 現在の端末で利用される生体認証タイプ
    /// NOTE: `biometryType` は `canEvaluatePolicy` 後に確定するため、必ず評価後に参照する
    var biometricType: BiometricType {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return .none
        }
        switch context.biometryType {
        case .touchID:
            return .touchID
        case .faceID:
            return .faceID
        case .opticID:
            return .opticID
        default:
            return .none
        }
    }

    /// 設定画面表示用の名称
    /// 生体認証が使えない場合は「パスコード」を返す（UIの文言が自然になる）
    var biometricName: String {
        if isBiometricAvailable {
            return biometricType.displayName
        }
        return "パスコード"
    }

    // MARK: - Authentication

    func authenticate() async {
        // Prevent re-entrant calls
        guard !isAuthenticating else { return }

        guard AppSettings.shared.appLockEnabled else {
            isLocked = false
            return
        }

        guard !isAuthenticating else { return }

        isAuthenticating = true
        authError = nil

        let context = LAContext()
        var error: NSError?

        // 生体認証が利用可能か確認
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            // 生体認証が使えない場合はパスコード認証にフォールバック
            await authenticateWithPasscode()
            return
        }

        // If Face ID/Optic ID will be used, ensure usage description exists to avoid OS termination
        if context.biometryType == .faceID || context.biometryType == .opticID {
            if !hasUsageDescription("NSFaceIDUsageDescription") {
                self.authError = "Face IDの使用理由（NSFaceIDUsageDescription）が設定されていません。パスコード認証に切り替えます。"
                await authenticateWithPasscode()
                return
            }
        }

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "家計簿アプリのロックを解除"
            )

            if success {
                isLocked = false
            }
        } catch let authError as LAError {
            switch authError.code {
            case .userFallback, .biometryLockout:
                // パスコードにフォールバック
                await authenticateWithPasscode()
            case .userCancel:
                self.authError = "認証がキャンセルされました"
            case .biometryNotAvailable:
                self.authError = "生体認証が利用できません"
            case .biometryNotEnrolled:
                self.authError = "生体認証が設定されていません"
            default:
                self.authError = "認証に失敗しました"
            }
        } catch {
            self.authError = "認証に失敗しました"
        }

        isAuthenticating = false
    }

    private func authenticateWithPasscode() async {
        let context = LAContext()

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "家計簿アプリのロックを解除"
            )

            if success {
                isLocked = false
            }
        } catch {
            authError = "認証に失敗しました"
        }

        isAuthenticating = false
    }

    // MARK: - Lock Control

    func lock() {
        if AppSettings.shared.appLockEnabled {
            isLocked = true
        }
    }

    func unlock() {
        isLocked = false
    }

    /// アプリがバックグラウンドに移行した時の処理
    func handleBackground() {
        if AppSettings.shared.appLockEnabled && AppSettings.shared.lockOnBackground {
            isLocked = true
        }
    }
}

// MARK: - Biometric Type

enum BiometricType {
    case none
    case touchID
    case faceID
    case opticID

    var displayName: String {
        switch self {
        case .none: return "なし"
        case .touchID: return "Touch ID"
        case .faceID: return "Face ID"
        case .opticID: return "Optic ID"
        }
    }

    var iconName: String {
        switch self {
        case .none: return "lock"
        case .touchID: return "touchid"
        case .faceID: return "faceid"
        case .opticID: return "opticid"
        }
    }
}
