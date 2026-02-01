import Foundation

/// アプリの機能フラグ
/// 本番リリース時やテスト時に機能の有効/無効を切り替えるために使用
enum AppFeatureFlags {
    /// CloudKit同期機能の有効/無効
    /// - Note: 無料のApple Developer Teamでは使用不可のため、現在は無効化
    static let cloudSyncEnabled = false
}
