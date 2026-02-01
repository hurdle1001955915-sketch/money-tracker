import SwiftUI
import UIKit

// MARK: - App Theme

struct AppTheme {
    // MARK: - Primary Colors
    static let primary = Color.themeBlue
    static let primaryBackground = Color(.systemBackground)
    static let secondaryBackground = Color(.systemGroupedBackground)
    static let tertiaryBackground = Color(.systemGray6)

    // MARK: - Semantic Colors
    static let income = Color(UIColor.systemBlue)
    static let expense = Color(UIColor.systemRed)
    static let transfer = Color(UIColor.systemOrange)
    static let savings = Color(UIColor.systemGreen)
    static let warning = Color(UIColor.systemYellow)

    // MARK: - Chart Colors
    static let chartPositive = Color(UIColor.systemGreen).opacity(0.7)
    static let chartNegative = Color(UIColor.systemRed).opacity(0.7)
    static let chartIncome = Color(UIColor.systemBlue).opacity(0.7)
    static let chartExpense = Color(UIColor.systemRed).opacity(0.7)

    // MARK: - Text Colors
    static let primaryText = Color.primary
    static let secondaryText = Color.secondary
    static let tertiaryText = Color(.systemGray4)

    // MARK: - Gradient Colors
    struct Gradients {
        static let income = LinearGradient(
            colors: [Color(hex: "#2196F3"), Color(hex: "#64B5F6")],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        static let expense = LinearGradient(
            colors: [Color(hex: "#F44336"), Color(hex: "#E57373")],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        static let balance = LinearGradient(
            colors: [Color(hex: "#4CAF50"), Color(hex: "#81C784")],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        static let card = LinearGradient(
            colors: [Color(.systemBackground), Color(.systemGray6).opacity(0.5)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: - Spacing (8pt Grid System)
    struct Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
        static let xxxl: CGFloat = 48
    }

    // MARK: - Corner Radius
    struct CornerRadius {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
        static let capsule: CGFloat = 999
    }

    // MARK: - Typography
    struct Typography {
        // Display
        static let displayLarge = Font.system(size: 34, weight: .bold, design: .rounded)
        static let displayMedium = Font.system(size: 28, weight: .bold, design: .rounded)
        static let displaySmall = Font.system(size: 24, weight: .semibold, design: .rounded)

        // Headline
        static let headlineLarge = Font.system(size: 22, weight: .semibold, design: .default)
        static let headlineMedium = Font.system(size: 17, weight: .semibold, design: .default)
        static let headlineSmall = Font.system(size: 15, weight: .semibold, design: .default)

        // Body
        static let bodyLarge = Font.system(size: 17, weight: .regular, design: .default)
        static let bodyMedium = Font.system(size: 15, weight: .regular, design: .default)
        static let bodySmall = Font.system(size: 13, weight: .regular, design: .default)

        // Label
        static let labelLarge = Font.system(size: 14, weight: .medium, design: .default)
        static let labelMedium = Font.system(size: 12, weight: .medium, design: .default)
        static let labelSmall = Font.system(size: 11, weight: .medium, design: .default)

        // Amount (Tabular figures for alignment)
        static let amountLarge = Font.system(size: 28, weight: .bold, design: .rounded).monospacedDigit()
        static let amountMedium = Font.system(size: 20, weight: .semibold, design: .rounded).monospacedDigit()
        static let amountSmall = Font.system(size: 15, weight: .medium, design: .rounded).monospacedDigit()
    }

    // MARK: - Font Sizes (Legacy Support)
    struct FontSize {
        static let caption: CGFloat = 11
        static let footnote: CGFloat = 13
        static let subheadline: CGFloat = 15
        static let body: CGFloat = 17
        static let headline: CGFloat = 17
        static let title3: CGFloat = 20
        static let title2: CGFloat = 22
        static let title: CGFloat = 28
        static let largeTitle: CGFloat = 34
    }

    // MARK: - Shadow
    struct Shadow {
        static let small = (color: Color.black.opacity(0.06), radius: CGFloat(4), x: CGFloat(0), y: CGFloat(2))
        static let medium = (color: Color.black.opacity(0.08), radius: CGFloat(8), x: CGFloat(0), y: CGFloat(4))
        static let large = (color: Color.black.opacity(0.12), radius: CGFloat(16), x: CGFloat(0), y: CGFloat(8))
    }

    // MARK: - Minimum Touch Target
    static let minTouchTarget: CGFloat = 44

    // MARK: - Animation
    struct Animation {
        static let fast: Double = 0.15
        static let normal: Double = 0.25
        static let slow: Double = 0.35

        // Spring animations
        static let springResponse: Double = 0.4
        static let springDamping: Double = 0.75

        static var springDefault: SwiftUI.Animation {
            .spring(response: springResponse, dampingFraction: springDamping)
        }

        static var springBouncy: SwiftUI.Animation {
            .spring(response: 0.35, dampingFraction: 0.6)
        }

        static var springSmooth: SwiftUI.Animation {
            .spring(response: 0.5, dampingFraction: 0.85)
        }

        static var easeOutQuick: SwiftUI.Animation {
            .easeOut(duration: fast)
        }
    }
}

// MARK: - Haptic Feedback Manager

@MainActor
final class HapticManager {
    static let shared = HapticManager()

    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    private let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    private let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
    private let impactSoft = UIImpactFeedbackGenerator(style: .soft)
    private let impactRigid = UIImpactFeedbackGenerator(style: .rigid)
    private let selectionGenerator = UISelectionFeedbackGenerator()
    private let notification = UINotificationFeedbackGenerator()

    private init() {
        // Prepare generators for immediate response
        impactLight.prepare()
        impactMedium.prepare()
        selectionGenerator.prepare()
        notification.prepare()
    }

    // MARK: - Semantic Haptics

    /// Tab/segment selection
    func selection() {
        selectionGenerator.selectionChanged()
    }

    /// Button tap
    func tap() {
        impactLight.impactOccurred()
    }

    /// Important action (save, confirm)
    func impact() {
        impactMedium.impactOccurred()
    }

    /// Toggle switch
    func toggle() {
        impactSoft.impactOccurred()
    }

    /// Long press activation
    func longPress() {
        impactHeavy.impactOccurred()
    }

    /// Success (save completed, etc.)
    func success() {
        notification.notificationOccurred(.success)
    }

    /// Warning
    func warning() {
        notification.notificationOccurred(.warning)
    }

    /// Error
    func error() {
        notification.notificationOccurred(.error)
    }

    /// Swipe action
    func swipe() {
        impactRigid.impactOccurred(intensity: 0.6)
    }

    /// Scroll snap
    func snap() {
        impactLight.impactOccurred(intensity: 0.5)
    }
}

// MARK: - View Modifiers

extension View {
    /// Apply card style with subtle shadow
    func cardStyle(padding: CGFloat = AppTheme.Spacing.lg) -> some View {
        self
            .padding(padding)
            .background(Color.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.lg))
            .shadow(
                color: AppTheme.Shadow.small.color,
                radius: AppTheme.Shadow.small.radius,
                x: AppTheme.Shadow.small.x,
                y: AppTheme.Shadow.small.y
            )
    }

    /// Apply glass effect (subtle blur background)
    func glassStyle(cornerRadius: CGFloat = AppTheme.CornerRadius.lg) -> some View {
        self
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    /// Animate on appear with delay
    func animateOnAppear(delay: Double = 0) -> some View {
        self.modifier(AnimateOnAppearModifier(delay: delay))
    }

    /// Scale button effect
    func scaleButtonStyle() -> some View {
        self.buttonStyle(ScaleButtonStyle())
    }

    /// Apply haptic feedback on tap
    func hapticTap(_ style: HapticStyle = .tap) -> some View {
        self.modifier(HapticTapModifier(style: style))
    }
}

// MARK: - Haptic Style

enum HapticStyle {
    case tap
    case selection
    case impact
    case success
    case warning
    case error
}

// MARK: - Haptic Tap Modifier

struct HapticTapModifier: ViewModifier {
    let style: HapticStyle

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(TapGesture().onEnded {
                switch style {
                case .tap: HapticManager.shared.tap()
                case .selection: HapticManager.shared.selection()
                case .impact: HapticManager.shared.impact()
                case .success: HapticManager.shared.success()
                case .warning: HapticManager.shared.warning()
                case .error: HapticManager.shared.error()
                }
            })
    }
}

// MARK: - Animate On Appear Modifier

struct AnimateOnAppearModifier: ViewModifier {
    let delay: Double
    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : 10)
            .onAppear {
                withAnimation(AppTheme.Animation.springDefault.delay(delay)) {
                    isVisible = true
                }
            }
    }
}

// MARK: - Scale Button Style

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(AppTheme.Animation.easeOutQuick, value: configuration.isPressed)
    }
}

// MARK: - Animated Progress Bar

struct AnimatedProgressBar: View {
    let progress: Double
    let color: Color
    let height: CGFloat
    let cornerRadius: CGFloat

    @State private var animatedProgress: Double = 0

    init(
        progress: Double,
        color: Color = AppTheme.primary,
        height: CGFloat = 8,
        cornerRadius: CGFloat = 4
    ) {
        self.progress = progress
        self.color = color
        self.height = height
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.gray.opacity(0.15))
                    .frame(height: height)

                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(color)
                    .frame(width: geo.size.width * CGFloat(min(animatedProgress, 1.0)), height: height)
            }
        }
        .frame(height: height)
        .onAppear {
            withAnimation(AppTheme.Animation.springSmooth.delay(0.1)) {
                animatedProgress = progress
            }
        }
        .onChange(of: progress) { _, newValue in
            withAnimation(AppTheme.Animation.springDefault) {
                animatedProgress = newValue
            }
        }
    }
}

// MARK: - Animated Counter

struct AnimatedCounter: View {
    let value: Int
    let font: Font
    let color: Color

    @State private var displayValue: Int = 0

    init(value: Int, font: Font = AppTheme.Typography.amountMedium, color: Color = .primary) {
        self.value = value
        self.font = font
        self.color = color
    }

    var body: some View {
        Text(displayValue.currencyFormatted)
            .font(font)
            .foregroundStyle(color)
            .contentTransition(.numericText(value: Double(displayValue)))
            .onAppear {
                withAnimation(AppTheme.Animation.springSmooth.delay(0.1)) {
                    displayValue = value
                }
            }
            .onChange(of: value) { _, newValue in
                withAnimation(AppTheme.Animation.springDefault) {
                    displayValue = newValue
                }
            }
    }
}

// MARK: - Shimmer Effect

struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { geo in
                    LinearGradient(
                        colors: [
                            .clear,
                            .white.opacity(0.3),
                            .clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.5)
                    .offset(x: geo.size.width * (phase - 0.5))
                }
                .mask(content)
            }
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    phase = 1.5
                }
            }
    }
}

extension View {
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
}

// MARK: - App Strings (Localization Ready)

struct AppStrings {
    // MARK: - Transaction Types
    struct TransactionTypes {
        static let expense = "支出"
        static let income = "収入"
        static let transfer = "振替"
    }

    // MARK: - Common Actions
    struct Actions {
        static let save = "保存"
        static let cancel = "キャンセル"
        static let delete = "削除"
        static let edit = "編集"
        static let add = "追加"
        static let close = "閉じる"
        static let done = "完了"
        static let back = "戻る"
        static let search = "検索"
        static let duplicate = "複製"
        static let reorder = "並び替え"
    }

    // MARK: - Tab Names
    struct Tabs {
        static let input = "入力"
        static let calendar = "カレンダー"
        static let graph = "グラフ"
        static let settings = "設定"
    }

    // MARK: - Summary Labels
    struct Summary {
        static let income = "収入"
        static let expense = "支出"
        static let balance = "合計"
        static let total = "合計"
        static let remaining = "残り"
        static let exceeded = "超過"
    }

    // MARK: - Empty States
    struct EmptyStates {
        static let noTransactions = "取引がありません"
        static let noData = "データがありません"
        static let noBudget = "予算が設定されていません"
        static let noBudgetHint = "設定 > 予算設定 から設定できます"
    }

    // MARK: - Date Labels
    struct DateLabels {
        static let today = "今日"
        static let yesterday = "昨日"
        static let thisMonth = "今月"
        static let lastMonth = "先月"
    }

    // MARK: - Form Labels
    struct FormLabels {
        static let date = "日付"
        static let amount = "金額"
        static let category = "カテゴリ"
        static let memo = "メモ"
        static let memoPlaceholder = "メモ（任意）"
        static let yen = "円"
    }

    // MARK: - Weekdays
    struct Weekdays {
        static let sunday = "日"
        static let monday = "月"
        static let tuesday = "火"
        static let wednesday = "水"
        static let thursday = "木"
        static let friday = "金"
        static let saturday = "土"
    }

    // MARK: - Settings
    struct Settings {
        static let title = "設定"
        static let account = "口座管理"
        static let display = "表示設定"
        static let category = "カテゴリ設定"
        static let security = "セキュリティ"
        static let tools = "ツール"
        static let data = "データ管理"
        static let budget = "予算設定"
        static let fixedCost = "固定費設定"
        static let receiptScanner = "レシート読取"
    }

    // MARK: - Account Types
    struct AccountTypes {
        static let bank = "銀行口座"
        static let creditCard = "クレジットカード"
        static let electronicMoney = "電子マネー"
        static let cash = "現金"
        static let investment = "投資口座"
        static let other = "その他"
    }

    // MARK: - Graph Types
    struct GraphTypes {
        static let expenseCategory = "支出カテゴリ"
        static let incomeCategory = "収入カテゴリ"
        static let savings = "貯金額"
        static let yearlyExpense = "年間支出"
        static let yearlyIncome = "年間収入"
        static let incomeTrend = "収支推移"
        static let budget = "予算"
    }

    // MARK: - Receipt Scanner
    struct ReceiptScanner {
        static let title = "レシート読取"
        static let selectPrompt = "レシートの写真を選択してください"
        static let aiHint = "AIが自動で金額や日付を読み取ります"
        static let camera = "カメラで撮影"
        static let photoLibrary = "写真から選択"
        static let parseComplete = "読み取り完了"
        static let store = "店舗:"
        static let confirmInfo = "取引情報を確認"
    }

    // MARK: - Errors & Alerts
    struct Errors {
        static let cameraUnavailable = "カメラが利用できません"
        static let cameraUnavailableMessage = "このデバイスではカメラが利用できません。"
        static let permissionRequired = "アクセス許可が必要です"
        static let configurationMissing = "設定が不足しています"
        static let openSettings = "設定を開く"
    }
}

// MARK: - Color Extension for Semantic Colors

extension Color {
    static var appIncome: Color { AppTheme.income }
    static var appExpense: Color { AppTheme.expense }
    static var appTransfer: Color { AppTheme.transfer }
    static var appSavings: Color { AppTheme.savings }
}
