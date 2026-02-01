import SwiftUI

// MARK: - Calculator Input View

struct CalculatorInputView: View {
    @Binding var value: String
    @Environment(\.dismiss) private var dismiss
    
    @State private var expression: String = ""
    @State private var displayValue: String = "0"
    @State private var hasDecimal: Bool = false
    @State private var lastOperator: String? = nil
    @State private var previousValue: Double = 0
    @State private var shouldResetDisplay: Bool = false
    
    private let buttons: [[CalculatorButton]] = [
        [.clear, .plusMinus, .percent, .divide],
        [.seven, .eight, .nine, .multiply],
        [.four, .five, .six, .minus],
        [.one, .two, .three, .plus],
        [.zero, .decimal, .equals]
    ]
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Display
                VStack(alignment: .trailing, spacing: AppTheme.Spacing.xs) {
                    if !expression.isEmpty {
                        Text(expression)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    
                    Text(displayValue)
                        .font(.system(size: 48, weight: .light, design: .rounded))
                        .foregroundStyle(AppTheme.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, AppTheme.Spacing.lg)
                .padding(.vertical, AppTheme.Spacing.xl)
                .background(AppTheme.secondaryBackground)
                
                // Keypad
                VStack(spacing: 1) {
                    ForEach(buttons, id: \.self) { row in
                        HStack(spacing: 1) {
                            ForEach(row) { button in
                                CalculatorButtonView(button: button) {
                                    handleButtonPress(button)
                                }
                            }
                        }
                    }
                }
                .background(Color(.systemGray5))
            }
            .background(AppTheme.primaryBackground)
            .navigationTitle(AppStrings.FormLabels.amount)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(AppStrings.Actions.cancel) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(AppStrings.Actions.done) {
                        saveValue()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .onAppear {
            if let existingValue = Int(value), existingValue > 0 {
                displayValue = String(existingValue)
            }
        }
    }
    
    private func handleButtonPress(_ button: CalculatorButton) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        
        switch button {
        case .zero, .one, .two, .three, .four, .five, .six, .seven, .eight, .nine:
            appendDigit(button.rawValue)
        case .decimal:
            appendDecimal()
        case .plus, .minus, .multiply, .divide:
            setOperator(button.symbol)
        case .equals:
            calculate()
        case .clear:
            clear()
        case .plusMinus:
            toggleSign()
        case .percent:
            applyPercent()
        }
    }
    
    private func appendDigit(_ digit: String) {
        if shouldResetDisplay {
            displayValue = digit
            shouldResetDisplay = false
        } else if displayValue == "0" {
            displayValue = digit
        } else {
            displayValue += digit
        }
    }
    
    private func appendDecimal() {
        if shouldResetDisplay {
            displayValue = "0."
            shouldResetDisplay = false
            hasDecimal = true
        } else if !hasDecimal {
            displayValue += "."
            hasDecimal = true
        }
    }
    
    private func setOperator(_ op: String) {
        if let value = Double(displayValue) {
            if let currentOp = lastOperator {
                // Chain calculation
                let result = performOperation(currentOp, previousValue, value)
                previousValue = result
                displayValue = formatResult(result)
                expression = "\(formatResult(result)) \(op)"
            } else {
                previousValue = value
                expression = "\(displayValue) \(op)"
            }
            lastOperator = op
            shouldResetDisplay = true
            hasDecimal = false
        }
    }
    
    private func calculate() {
        guard let op = lastOperator, let value = Double(displayValue) else { return }
        
        let result = performOperation(op, previousValue, value)
        expression = ""
        displayValue = formatResult(result)
        previousValue = 0
        lastOperator = nil
        shouldResetDisplay = true
        hasDecimal = displayValue.contains(".")
    }
    
    private func performOperation(_ op: String, _ a: Double, _ b: Double) -> Double {
        switch op {
        case "+": return a + b
        case "−": return a - b
        case "×": return a * b
        case "÷": return b != 0 ? a / b : 0
        default: return b
        }
    }
    
    private func formatResult(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", value)
        } else {
            return String(format: "%.2f", value).trimmingCharacters(in: CharacterSet(charactersIn: "0")).trimmingCharacters(in: CharacterSet(charactersIn: "."))
        }
    }
    
    private func clear() {
        displayValue = "0"
        expression = ""
        previousValue = 0
        lastOperator = nil
        shouldResetDisplay = false
        hasDecimal = false
    }
    
    private func toggleSign() {
        if let value = Double(displayValue) {
            displayValue = formatResult(-value)
        }
    }
    
    private func applyPercent() {
        if let value = Double(displayValue) {
            displayValue = formatResult(value / 100)
        }
    }
    
    private func saveValue() {
        // Calculate if there's a pending operation
        if lastOperator != nil {
            calculate()
        }
        
        // Extract integer part only (家計簿なので整数のみ)
        if let numValue = Double(displayValue) {
            value = String(Int(abs(numValue)))
        }
        dismiss()
    }
}

// MARK: - Calculator Button Enum

enum CalculatorButton: String, Identifiable, Hashable {
    case zero = "0", one = "1", two = "2", three = "3", four = "4"
    case five = "5", six = "6", seven = "7", eight = "8", nine = "9"
    case decimal = "."
    case plus = "+", minus = "-", multiply = "×", divide = "÷"
    case equals = "=", clear = "C", plusMinus = "±", percent = "%"
    
    var id: String { rawValue }
    
    var symbol: String {
        switch self {
        case .plus: return "+"
        case .minus: return "−"
        case .multiply: return "×"
        case .divide: return "÷"
        default: return rawValue
        }
    }
    
    var backgroundColor: Color {
        switch self {
        case .plus, .minus, .multiply, .divide, .equals:
            return AppTheme.primary
        case .clear, .plusMinus, .percent:
            return Color(.systemGray4)
        default:
            return Color(.systemGray6)
        }
    }
    
    var foregroundColor: Color {
        switch self {
        case .plus, .minus, .multiply, .divide, .equals:
            return .white
        default:
            return AppTheme.primaryText
        }
    }
    
    var isWide: Bool {
        self == .zero
    }
}

// MARK: - Calculator Button View

struct CalculatorButtonView: View {
    let button: CalculatorButton
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(button.symbol)
                .font(.system(size: 24, weight: .medium, design: .rounded))
                .foregroundStyle(button.foregroundColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(height: 70)
                .background(button.backgroundColor)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: button.isWide ? .infinity : nil)
        .layoutPriority(button.isWide ? 2 : 1)
    }
}

#Preview {
    CalculatorInputView(value: .constant("1000"))
}
