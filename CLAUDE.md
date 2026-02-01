# CLAUDE.md - AI Assistant Guide for Kakeibo (家計簿) Money Tracker

## Project Overview

This is **Kakeibo (家計簿)** - a native iOS income/expense management application built with Swift and SwiftUI. The app provides comprehensive personal finance tracking with features including transaction management, CSV import/export, automatic categorization, receipt scanning (OCR), analytics, and multi-account support.

### Quick Facts
- **Language**: Swift 5.0+
- **UI Framework**: SwiftUI
- **Data Persistence**: SwiftData (iOS 17+)
- **Platform**: iOS 26.2+ (iPhone & iPad)
- **External Dependencies**: None (uses only Apple frameworks)
- **Primary Locale**: Japanese (`ja_JP`)

## Repository Structure

```
/home/user/money-tracker/
├── 収支管理/                    # Main application source code
│   ├── Core/
│   │   ├── DataStore.swift      # Central data persistence & CRUD (singleton)
│   │   ├── AccountStore.swift   # Account management
│   │   ├── SwiftDataModels.swift # SwiftData @Model definitions
│   │   └── DataMigration.swift  # JSON → SwiftData migration
│   │
│   ├── Models/
│   │   ├── Transaction.swift    # Main transaction entity
│   │   ├── Category.swift       # Category definitions
│   │   ├── ClassificationRule.swift  # Auto-categorization rules
│   │   └── *.swift              # Other domain models
│   │
│   ├── Views/
│   │   ├── ContentView.swift    # Main TabView container
│   │   ├── InputView.swift      # Transaction entry
│   │   ├── CalendarView.swift   # Calendar-based view
│   │   ├── GraphView.swift      # Analytics/charts
│   │   └── SettingsView.swift   # App settings
│   │
│   ├── CSV/
│   │   ├── CSVImportWizardView.swift  # Multi-format CSV import UI
│   │   ├── CSVImportTypes.swift       # Import type definitions
│   │   └── CSVDocumentPicker.swift    # File picker wrapper
│   │
│   └── Utilities/
│       ├── Extensions.swift     # Utility extensions
│       ├── AppTheme.swift       # Design system
│       └── Diagnostics.swift    # Logging/diagnostics
│
├── Tests/                       # XCTest unit tests
│   ├── AmountParserTests.swift
│   ├── CSVImportTests.swift
│   ├── CSVParserTests.swift
│   ├── DateParserTests.swift
│   └── AmazonCardCSVTests.swift
│
├── Docs/                        # Documentation & Audit reports
│   └── Audit/                   # Phase-based audit documentation
│
├── 収支管理.xcodeproj/          # Xcode project file
├── PROJECT_SPEC.md              # Feature specification (Japanese)
└── README.md                    # Basic project README
```

## Build & Development

### Build Commands

```bash
# Build the project
xcodebuild -scheme "収支管理" -destination "platform=iOS Simulator,name=iPhone 17" build

# Run tests
xcodebuild -scheme "収支管理" -destination "platform=iOS Simulator,name=iPhone 17" test

# List available schemes
xcodebuild -list
```

### Build Configuration
- **Scheme**: `収支管理`
- **Configurations**: Debug, Release
- **Code Signing**: "Sign to Run Locally" for simulator builds

### Running Tests

Tests are located in `/Tests/` directory and use XCTest framework:
- `AmountParserTests` - Numeric/currency parsing
- `DateParserTests` - Date format recognition
- `CSVParserTests` - CSV line/column parsing
- `CSVImportTests` - Import format detection
- `AmazonCardCSVTests` - Amazon card CSV handling

## Architecture & Patterns

### Core Architecture: MVVM

The app follows **MVVM (Model-View-ViewModel)** pattern with SwiftUI:

- **Models**: Data structures in `Transaction.swift`, `Category.swift`, etc.
- **Views**: SwiftUI views (`*View.swift`)
- **State Management**: `@EnvironmentObject`, `@Published`, `@StateObject`

### Key Singletons

| Singleton | Purpose |
|-----------|---------|
| `DataStore.shared` | Central data persistence & CRUD operations |
| `AccountStore.shared` | Account management and balance calculations |
| `ClassificationRulesStore.shared` | Auto-categorization rules |
| `AppSettings.shared` | User preferences and display settings |
| `AppLockManager.shared` | Security/app lock functionality |
| `CloudKitSyncManager.shared` | iCloud synchronization (optional) |

### Data Flow

```
App Launch
├── ModelContainer initialization (SwiftData)
│   ├── Success → Use persistent database
│   └── Failure → Fallback to in-memory
├── DataStore.setModelContext()
├── JSON migration (if needed)
├── Category ID migration
└── Process fixed costs (recurring transactions)
```

### Persistence Layers

1. **SwiftData (Primary)** - Main persistence via `@Model` classes
2. **UserDefaults (Secondary)** - Classification rules, app settings
3. **JSON (Legacy)** - Migration support from older versions

## Key Conventions

### File Naming
- Views: `*View.swift` (e.g., `TransactionSearchView.swift`)
- Models: PascalCase (e.g., `Transaction.swift`)
- Managers/Services: `*Manager.swift`, `*Service.swift`
- Type definitions: `*Types.swift` (e.g., `AIClassificationTypes.swift`)

### Code Style
- Use `MARK:` comments for section grouping
- Prefer `@MainActor` for thread-safety
- Use `@Published` properties for reactive updates
- Extensions grouped in `Extensions.swift`

### Japanese Text Handling
- UI strings support localization via String Catalogs
- Default category names are in Japanese
- Text normalization via `TextNormalizer.normalize(_:)` for search/matching

## Important Files

### Must-Read Before Modifications

| File | Lines | Purpose |
|------|-------|---------|
| `DataStore.swift` | ~2,800 | Central data hub - understand before data changes |
| `SwiftDataModels.swift` | ~670 | Database schema definitions |
| `Transaction.swift` | ~430 | Core transaction model |
| `ClassificationRule.swift` | ~870 | Auto-categorization system |
| `CSVImportWizardView.swift` | ~2,100 | Complex CSV import wizard |

### Entry Points
- **App Launch**: `KakeiboApp.swift:97`
- **Main UI**: `ContentView.swift:68`
- **Data Operations**: `DataStore.swift`

## Feature Modules

### Transaction Management
- Create/edit/delete via `InputView`
- Types: Expense, Income, Transfer
- Split transactions supported
- Duplicate detection via `fingerprintKey`

### CSV Import/Export
**Supported formats:**
- App export format
- Bank generic CSV
- Credit card generic CSV
- Amazon Card (Sumitomo Mitsui)
- Resona Bank
- PayPay

**Key classes:**
- `CSVFormatDetector` - Auto-detection with confidence scoring
- `CSVImportWizardView` - Import UI
- Encodings: UTF-8, UTF-16, Shift_JIS, EUC-JP

### Auto-Categorization
- Rule-based classification (`ClassificationRule`)
- Keyword matching with priority system
- AI-powered suggestions (`AIClassificationService`)
- Rule learning from manual classifications

### Receipt OCR
- Vision framework integration
- Amount/date/store extraction
- Regex-based parsing in `ReceiptParser`

## Testing Guidelines

### Running Specific Tests
```bash
# Run all tests
xcodebuild test -scheme "収支管理" -destination "platform=iOS Simulator,name=iPhone 17"

# Test modules import
@testable import 収支管理
```

### Test Coverage Areas
- Amount parsing (currency formats)
- Date parsing (multiple formats)
- CSV parsing and format detection
- Amazon card CSV handling

## Known Issues & Constraints

### Critical Crash Risks
| Location | Issue | Mitigation |
|----------|-------|------------|
| `KakeiboApp.swift:38` | `fatalError` on ModelContainer failure | Has in-memory fallback |
| `CSVImportTypes.swift:429` | Force unwrap on amount index | Needs defensive coding |
| `FixedCostBudgetViews.swift:340` | Force unwrap on categoryId | Protected by `where` clause |

### Technical Debt
- Category ID migration in progress (dual handling of name/ID)
- Some JSON legacy code still present
- CloudKit sync is simplified (no advanced conflict resolution)

## Development Workflow

### Before Making Changes
1. Read relevant files using this guide
2. Understand the singleton pattern usage
3. Check for existing tests in `/Tests/`
4. Review `Docs/Audit/` for context

### When Adding Features
1. Follow MVVM pattern
2. Use `@MainActor` for UI-related code
3. Add to appropriate singleton if state management needed
4. Consider localization (Japanese default)

### When Fixing Bugs
1. Check `Docs/Audit/IncompleteFeature_Audit.md` for known issues
2. Verify fix doesn't break existing functionality
3. Add tests if modifying parsing/import logic

## API & Frameworks Used

| Framework | Purpose |
|-----------|---------|
| SwiftUI | User interface |
| SwiftData | Data persistence |
| CloudKit | iCloud sync (optional) |
| Vision | Receipt OCR |
| LocalAuthentication | Face ID/biometric |
| Swift Charts | Analytics visualization |
| Security | Keychain operations |

## Documentation References

- `PROJECT_SPEC.md` - Full feature specification (Japanese)
- `Docs/Audit/Phase0_Overview.md` - Architecture overview
- `Docs/Audit/Phase1_BuildRun.md` - Build & execution guide
- `Docs/Audit/Phase3_CSVImport.md` - CSV import system details
- `Docs/Audit/IncompleteFeature_Audit.md` - Known gaps

## Quick Commands Reference

```bash
# Build
xcodebuild -scheme "収支管理" -destination "platform=iOS Simulator,name=iPhone 17" build

# Test
xcodebuild -scheme "収支管理" -destination "platform=iOS Simulator,name=iPhone 17" test

# Find Swift files
find . -name "*.swift" -type f | head -20

# Search for patterns
grep -rn "PATTERN" 収支管理/
```

---

*Last updated: 2026-02-01*
*Codebase: ~24,000 lines of Swift across 62 files*
